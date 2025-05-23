// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Abstract Allocation Mechanism for ERC4626 Vault-Based Voting
/// @notice Provides the core structure for on-chain voting mechanisms that mint ERC4626 shares to proposal recipients based on vote tallies.
/// @dev Use by inheriting and implementing the five key hooks and the conversion hook `_convertVotesToShares`.
abstract contract BaseAllocationMechanism is ReentrancyGuard, Ownable, Pausable {
    // Custom Errors
    error ZeroAssetAddress();
    error ZeroVotingDelay();
    error ZeroVotingPeriod();
    error ZeroQuorumShares();
    error ZeroTimelockDelay();
    error ZeroStartBlock();
    error EmptyName();
    error EmptySymbol();
    error RegistrationBlocked();
    error VotingEnded();
    error AlreadyRegistered();
    error DepositTooLarge();
    error VotingPowerTooLarge();
    error ProposeNotAllowed();
    error InvalidRecipient();
    error RecipientUsed();
    error EmptyDescription();
    error DescriptionTooLong();
    error MaxProposalsReached();
    error VotingNotEnded();
    error TallyAlreadyFinalized();
    error FinalizationBlocked();
    error TallyNotFinalized();
    error InvalidProposal();
    error ProposalCanceledError();
    error NoQuorum();
    error AlreadyQueued();
    error NoAllocation();
    error VotingClosed();
    error AlreadyVoted();
    error InvalidWeight();
    error WeightTooLarge();
    error PowerIncreased();
    error NotProposer();
    error AlreadyCanceled();
    error InvalidRecipientAddress();
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Maximum safe value for mathematical operations
    uint256 public constant MAX_SAFE_VALUE = type(uint128).max;
    
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
        string description;
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
    event ProposalCreated(uint256 indexed pid, address indexed proposer, address indexed recipient, string description);
    /// @notice Emitted when a vote is cast
    event VotesCast(address indexed voter, uint256 indexed pid, VoteType indexed choice, uint256 weight);
    /// @notice Emitted when vote tally is finalized
    event VoteTallyFinalized();
    /// @notice Emitted when a proposal is queued and shares minted
    event ProposalQueued(uint256 indexed pid, uint256 eta, uint256 shareAmount);
    /// @notice Emitted when a proposal is canceled
    event ProposalCanceled(uint256 indexed pid, address indexed proposer);

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
    ) Ownable(msg.sender) {
        if (address(_asset) == address(0)) revert ZeroAssetAddress();
        if (_votingDelay == 0) revert ZeroVotingDelay();
        if (_votingPeriod == 0) revert ZeroVotingPeriod();
        if (_quorumShares == 0) revert ZeroQuorumShares();
        if (_timelockDelay == 0) revert ZeroTimelockDelay();
        if (_startBlock == 0) revert ZeroStartBlock();
        if (bytes(_name).length == 0) revert EmptyName();
        if (bytes(_symbol).length == 0) revert EmptySymbol();

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
    function _processVoteHook(uint256 pid, address voter, VoteType choice, uint256 weight, uint256 oldPower)
        internal
        virtual
        returns (uint256 newPower);

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
    function signup(uint256 deposit) external nonReentrant whenNotPaused {
        address user = msg.sender;
        if (!_beforeSignupHook(user)) revert RegistrationBlocked();
        if (block.number >= startBlock + votingDelay + votingPeriod) revert VotingEnded();
        if (votingPower[user] != 0) revert AlreadyRegistered();
        if (deposit > MAX_SAFE_VALUE) revert DepositTooLarge();
        if (deposit > 0) asset.safeTransferFrom(user, address(this), deposit);
        uint256 newPower = _getVotingPowerHook(user, deposit);
        if (newPower > MAX_SAFE_VALUE) revert VotingPowerTooLarge();
        votingPower[user] = newPower;
        emit UserRegistered(user, newPower);
    }

    // ---------- Proposal Creation ----------

    /// @notice Create a new proposal targeting `recipient`.
    /// @param recipient Address to receive allocated vault shares upon queue.
    /// @param description Description or rationale for the proposal
    /// @return pid Unique identifier for the new proposal.
    function propose(address recipient, string calldata description) external whenNotPaused returns (uint256 pid) {
        address proposer = msg.sender;
        if (!_beforeProposeHook(proposer)) revert ProposeNotAllowed();
        if (recipient == address(0)) revert InvalidRecipient();
        if (_recipientUsed[recipient]) revert RecipientUsed();
        if (bytes(description).length == 0) revert EmptyDescription();
        if (bytes(description).length > 1000) revert DescriptionTooLong();

        if (_proposalIdCounter >= type(uint256).max) revert MaxProposalsReached();
        _proposalIdCounter++;
        pid = _proposalIdCounter;

        proposals[pid] = Proposal(0, 0, proposer, recipient, description, false, false);
        _recipientUsed[recipient] = true;

        emit ProposalCreated(pid, proposer, recipient, description);
    }

    // ---------- Vote Tally Finalization ----------

    /// @notice Finalize vote tally once voting period (from first proposal) has ended.
    /// @dev **SECURITY CRITICAL**: ensure this can only be called once and only after voting ends.
    function finalizeVoteTally() external onlyOwner {
        if (block.number < startBlock + votingDelay + votingPeriod) revert VotingNotEnded();
        if (tallyFinalized) revert TallyAlreadyFinalized();
        if (!_beforeFinalizeVoteTallyHook()) revert FinalizationBlocked();
        tallyFinalized = true;
        emit VoteTallyFinalized();
    }

    // ---------- Queue Proposal & Mint Allocation ----------

    /// @notice Queue proposal and mint vault shares based on vote tallies.
    /// @dev Calls `_convertVotesToShares(pid)` to determine mint amount.
    /// @param pid Proposal ID to queue.
    function queueProposal(uint256 pid) external onlyOwner {
        if (!tallyFinalized) revert TallyNotFinalized();
        if (!_validateProposalHook(pid)) revert InvalidProposal();
        Proposal storage p = proposals[pid];
        if (p.canceled) revert ProposalCanceledError();
        if (!_hasQuorumHook(pid)) revert NoQuorum();
        if (p.eta != 0) revert AlreadyQueued();

        uint256 sharesToMint = _convertVotesToShares(pid);
        if (sharesToMint == 0) revert NoAllocation();
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
    function castVote(uint256 pid, VoteType choice, uint256 weight) external nonReentrant whenNotPaused {
        if (!_validateProposalHook(pid)) revert InvalidProposal();
        if (
            block.number < startBlock + votingDelay || block.number > startBlock + votingDelay + votingPeriod
        ) revert VotingClosed();
        if (hasVoted[pid][msg.sender]) revert AlreadyVoted();

        uint256 oldPower = votingPower[msg.sender];
        if (weight == 0 || weight > oldPower) revert InvalidWeight();
        if (weight > MAX_SAFE_VALUE) revert WeightTooLarge();

        uint256 newPower = _processVoteHook(pid, msg.sender, choice, weight, oldPower);
        if (newPower > oldPower) revert PowerIncreased();

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
        if (!_validateProposalHook(pid)) revert InvalidProposal();
        return _state(pid);
    }

    /// @notice Cancel a proposal
    /// @param pid Proposal ID to cancel
    function cancelProposal(uint256 pid) external {
        if (!_validateProposalHook(pid)) revert InvalidProposal();
        Proposal storage p = proposals[pid];
        if (msg.sender != p.proposer) revert NotProposer();
        if (p.canceled) revert AlreadyCanceled();
        if (p.eta != 0) revert AlreadyQueued();

        p.canceled = true;
        emit ProposalCanceled(pid, p.proposer);
    }

    /// @notice Get current vote tallies for a proposal
    /// @param pid Proposal ID
    /// @return sharesFor Number of shares voted for
    /// @return sharesAgainst Number of shares voted against
    /// @return sharesAbstain Number of shares abstained
    function getVoteTally(uint256 pid)
        external
        view
        returns (uint256 sharesFor, uint256 sharesAgainst, uint256 sharesAbstain)
    {
        if (!_validateProposalHook(pid)) revert InvalidProposal();
        ProposalVote storage votes = proposalVotes[pid];
        return (votes.sharesFor, votes.sharesAgainst, votes.sharesAbstain);
    }

    /// @notice Get remaining voting power for an address
    /// @param voter Address to check voting power for
    /// @return Remaining voting power
    function getRemainingVotingPower(address voter) external view returns (uint256) {
        return votingPower[voter];
    }

    /// @notice Get total number of proposals created
    /// @return Total proposal count
    function getProposalCount() external view returns (uint256) {
        return _proposalIdCounter;
    }

    // ---------- Emergency Functions ----------

    /// @notice Emergency pause all operations
    /// @dev Only owner can pause the contract. Prevents all user interactions until unpaused.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume operations after pause
    /// @dev Only owner can unpause the contract. Restores normal operation after emergency pause.
    function unpause() external onlyOwner {
        _unpause();
    }
}
