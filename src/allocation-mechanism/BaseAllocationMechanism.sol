// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Abstract Allocation Mechanism for ERC4626 Vault-Based Voting
/// @notice Provides the core structure for on-chain voting mechanisms that mint ERC4626 shares to proposal recipients based on vote tallies.
/// @dev Use by inheriting and implementing the five key hooks and the conversion hook `_convertVotesToShares`.
abstract contract BaseAllocationMechanism {
    /// @notice start block to start counting the voting delay before votingPeriod
    uint256 public immutable startBlock;
    /// @notice Blocks between consecutive proposals by same proposer
    uint256 public immutable votingDelay;
    /// @notice Blocks duration of voting window
    uint256 public immutable votingPeriod;
    /// @notice Seconds until minted shares become redeemable
    uint256 public immutable timelockDelay;
    /// @notice Minimum net votes required to queue a proposal
    uint256 public immutable quorumShares;
    /// @notice Grace period after timelock expiry for state computation
    uint256 public constant GRACE_PERIOD = 14 days;

    /// @notice Becomes true once `finalizeVoteTally` is called post-voting
    bool public tallyFinalized;

    /// @notice Vote types: Against, For, Abstain
    enum VoteType {
        Against,
        For,
        Abstain
    }

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    struct Proposal {
        uint256 sharesRequested;
        uint256 eta;
        address proposer;
        address recipient;
        bool claimed;
        bool canceled;
    }

    /// @notice Data for each proposal
    struct ProposalVote {
        uint256 sharesFor;
        uint256 sharesAgainst;
        uint256 sharesAbstain;
    }

    /// @notice ERC20 asset used for the vault
    IERC20 public immutable asset;
    string public name;
    string public symbol;
    /// @dev Mapping of proposal ID to Proposal data
    mapping(uint256 => Proposal) public proposals;
    /// @dev Mapping of proposal ID to ProposalVote data
    mapping(uint256 => ProposalVote) public proposalVotes;
    /// @dev Counter for generating unique proposal IDs
    uint256 internal _proposalIdCounter;
    /// @dev Tracks addresses already used as recipients to avoid duplicates
    mapping(address => bool) private _recipientUsed;
    /// @dev Tracks which addresses have voted on which proposals
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    /// @dev Voting power of each address
    mapping(address => uint256) public votingPower;
    /// @dev Earliest timestamp at which shares can be redeemed for each recipient
    mapping(address => uint256) public redeemableAfter;
    /// @dev Shares allocated to each proposal, for record-keeping
    mapping(uint256 => uint256) public proposalShares;

    /// @notice Emitted when a user completes registration
    event UserRegistered(address indexed user, uint256 votingPower);
    /// @notice Emitted when a new proposal is created
    event ProposalCreated(uint256 indexed pid, address indexed proposer, address recipient);
    /// @notice Emitted when a vote is cast
    event VotesCast(address indexed voter, uint256 indexed pid, VoteType choice, uint256 weight);
    /// @notice Emitted when vote tally is finalized
    event VoteTallyFinalized();
    /// @notice Emitted when a proposal is queued and shares minted
    event ProposalQueued(uint256 indexed pid, uint256 eta, uint256 shareAmount);

    /// @param _asset Underlying ERC20 token used for vault
    /// @param _name ERC20 name for vault share token
    /// @param _symbol ERC20 symbol for vault share token
    /// @param _votingDelay Blocks required between proposals by same proposer
    /// @param _votingPeriod Blocks duration that voting remains open
    /// @param _quorumShares Minimum net votes for a proposal to pass
    /// @param _timelockDelay Seconds after queuing before redemption allowed
    /// @param _startBlock Block number when voting mechanism starts
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumShares,
        uint256 _timelockDelay,
        uint256 _startBlock
    ) {
        require(address(_asset) != address(0), "Invalid asset");
        require(_votingDelay > 0, "Invalid voting delay");
        require(_votingPeriod > 0, "Invalid voting period");
        require(_quorumShares > 0, "Invalid quorum");
        require(_timelockDelay > 0, "Invalid timelock");
        require(_startBlock > 0, "Invalid start block");

        asset = _asset;
        name = _name;
        symbol = _symbol;
        votingDelay = _votingDelay;
        votingPeriod = _votingPeriod;
        quorumShares = _quorumShares;
        timelockDelay = _timelockDelay;
        startBlock = _startBlock;
    }

    // ---------- Hooks (to implement) ----------

    /// @dev Hook to allow or block registration. **SECURITY CRITICAL**: ensure only authorized users can register if needed.
    /// @param user Address attempting to register
    /// @return allow True if registration should proceed
    function _beforeSignupHook(address user) internal view virtual returns (bool);

    /// @dev Hook to allow or block proposal creation. **SECURITY CRITICAL**: validate proposer identity or stake as needed.
    /// @param proposer Address proposing
    /// @return allow True if proposing allowed
    function _beforeProposeHook(address proposer) internal view virtual returns (bool);

    /// @dev Hook to calculate new voting power on registration. Can include stake decay, off-chain checks, etc.
    /// @param user Address registering
    /// @param deposit Amount of underlying tokens deposited
    /// @return power New voting power assigned
    function _getVotingPowerHook(address user, uint256 deposit) internal view virtual returns (uint256);

    /// @dev Hook to validate existence and integrity of a proposal ID. **SECURITY CRITICAL**: prevent invalid pids.
    /// @param pid Proposal ID to validate
    /// @return valid True if pid is valid and corresponds to a created proposal
    function _validateProposalHook(uint256 pid) internal view virtual returns (bool);

    /// @dev Hook to process a vote. Must update proposal shares (For/Against/Abstain) and optionally track total shares.
    /// @param pid Proposal ID being voted on
    /// @param voter Address casting the vote
    /// @param choice VoteType (Against/For/Abstain)
    /// @param weight Voting power weight to apply
    /// @param oldPower Voting power before vote
    /// @return newPower Voting power after vote (must be <= oldPower)
    function _processVoteHook(
        uint256 pid,
        address voter,
        VoteType choice,
        uint256 weight,
        uint256 oldPower
    ) internal virtual returns (uint256 newPower);

    /// @notice Check if proposal met quorum requirement.
    /// @param pid Proposal ID
    /// @return True if net For votes >= quorumShares
    function _hasQuorumHook(uint256 pid) internal view virtual returns (bool);

    /// @dev Hook to convert final vote tallies into vault shares to mint. Should use net For and totalShares ratio.
    /// @param pid Proposal ID being queued
    /// @return sharesToMint Number of vault shares to mint for the proposal
    function _convertVotesToShares(uint256 pid) internal view virtual returns (uint256 sharesToMint);

    /// @dev Hook to modify the behavior of finalizeVoteTally. Can be used to enforce additional checks or actions.
    /// @return allow True if finalization should proceed
    function _beforeFinalizeVoteTallyHook() internal view virtual returns (bool);

    /// @dev a hook to fetch the recipient address for a proposal. Can be used to enforce additional checks or actions.
    /// @param pid Proposal ID being redeemed
    /// @return recipient Address of the recipient for the proposal
    function _getRecipientAddressHook(uint256 pid) internal view virtual returns (address recipient);

    /// @dev Hook to request a redeem of shares for a proposal. Can be used to enforce additional checks or actions.
    /// @param recipient Address of the recipient for the proposal
    /// @param sharesToRedeem Number of shares to redeem
    /// @return allow True if redeem request should proceed
    function _requestDistributionHook(address recipient, uint256 sharesToRedeem) internal view virtual returns (bool);

    // ---------- Registration ----------

    /// @notice Register to gain voting power by depositing underlying tokens.
    /// @param deposit Amount of underlying to deposit (may be zero).
    function signup(uint256 deposit) external {
        address user = msg.sender;
        require(_beforeSignupHook(user), "Registration blocked");
        require(block.number < startBlock + votingDelay + votingPeriod, "Voting ended");
        require(votingPower[user] == 0, "Already registered");
        if (deposit > 0) asset.transferFrom(user, address(this), deposit);
        uint256 newPower = _getVotingPowerHook(user, deposit);
        votingPower[user] = newPower;
        emit UserRegistered(user, newPower);
    }

    // ---------- Proposal Creation ----------

    /// @notice Create a new proposal targeting `recipient`.
    /// @param recipient Address to receive allocated vault shares upon queue.
    /// @return pid Unique identifier for the new proposal.
    function propose(address recipient) external returns (uint256 pid) {
        address proposer = msg.sender;
        require(_beforeProposeHook(proposer), "Propose not allowed");
        require(recipient != address(0), "Invalid recipient");
        require(!_recipientUsed[recipient], "Recipient used");

        _proposalIdCounter++;
        pid = _proposalIdCounter;

        proposals[pid] = Proposal(0, 0, proposer, recipient, false, false);
        _recipientUsed[recipient] = true;

        emit ProposalCreated(pid, proposer, recipient);
    }

    // ---------- Vote Tally Finalization ----------

    /// @notice Finalize vote tally once voting period (from first proposal) has ended.
    /// @dev **SECURITY CRITICAL**: ensure this can only be called once and only after voting ends.
    function finalizeVoteTally() external {
        require(block.number >= startBlock + votingDelay + votingPeriod, "Voting not ended");
        require(_beforeFinalizeVoteTallyHook(), "Finalization blocked");
        tallyFinalized = true;
        emit VoteTallyFinalized();
    }

    // ---------- Queue Proposal & Mint Allocation ----------

    /// @notice Queue proposal and mint vault shares based on vote tallies.
    /// @dev Calls `_convertVotesToShares(pid)` to determine mint amount.
    /// @param pid Proposal ID to queue.
    function queueProposal(uint256 pid) external {
        require(tallyFinalized, "Tally not finalized");
        require(_validateProposalHook(pid), "Invalid proposal");
        Proposal storage p = proposals[pid];
        require(!p.canceled, "Canceled");
        require(tallyFinalized, "Voting not ended");
        require(_hasQuorumHook(pid), "No quorum");
        require(p.eta == 0, "Already queued");

        uint256 sharesToMint = _convertVotesToShares(pid);
        require(sharesToMint > 0, "No allocation");
        proposalShares[pid] = sharesToMint;

        _requestDistributionHook(_getRecipientAddressHook(pid), sharesToMint);
        //_mint(p.recipient, sharesToMint);

        uint256 eta = block.timestamp + timelockDelay;
        p.eta = eta;
        p.claimed = true;
        redeemableAfter[p.recipient] = eta;
        emit ProposalQueued(pid, eta, sharesToMint);
    }

    // ---------- Voting ----------

    /// @notice Cast a vote on a proposal.
    /// @param pid Proposal ID
    /// @param choice VoteType (Against, For, Abstain)
    /// @param weight Amount of voting power to apply
    function castVote(uint256 pid, VoteType choice, uint256 weight) external {
        require(_validateProposalHook(pid), "Invalid proposal");
        require(
            block.number >= startBlock + votingDelay && block.number <= startBlock + votingDelay + votingPeriod,
            "Voting closed"
        );
        require(!hasVoted[pid][msg.sender], "Already voted");

        uint256 oldPower = votingPower[msg.sender];
        require(weight > 0 && weight <= oldPower, "Invalid weight");

        uint256 newPower = _processVoteHook(pid, msg.sender, choice, weight, oldPower);
        require(newPower <= oldPower, "Power increased");

        votingPower[msg.sender] = newPower;
        hasVoted[pid][msg.sender] = true;
        emit VotesCast(msg.sender, pid, choice, weight);
    }

    // ---------- State Machine ----------

    /// @dev Internal state computation for a proposal
    function _state(uint256 pid) internal view returns (ProposalState) {
        Proposal storage p = proposals[pid];
        if (p.canceled) return ProposalState.Canceled;
        if (block.number < startBlock) return ProposalState.Pending;
        if (block.number <= startBlock + votingDelay + votingPeriod) return ProposalState.Active;
        if (!_hasQuorumHook(pid)) return ProposalState.Defeated;
        if (p.eta == 0) return ProposalState.Pending;
        if (p.claimed) return ProposalState.Succeeded;
        if (block.timestamp > p.eta + GRACE_PERIOD) return ProposalState.Expired;
        return ProposalState.Queued;
    }

    /// @notice Get the current state of a proposal
    /// @param pid Proposal ID
    /// @return Current state of the proposal
    function state(uint256 pid) external view returns (ProposalState) {
        require(_validateProposalHook(pid), "Invalid proposal");
        return _state(pid);
    }

    /// @notice Cancel a proposal
    /// @param pid Proposal ID to cancel
    function cancelProposal(uint256 pid) external {
        require(_validateProposalHook(pid), "Invalid proposal");
        Proposal storage p = proposals[pid];
        require(msg.sender == p.proposer, "Not proposer");
        require(!p.canceled, "Already canceled");
        require(p.eta == 0, "Already queued");

        p.canceled = true;
    }
}
