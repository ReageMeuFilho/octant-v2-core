// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

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
    error ZeroGracePeriod();
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

    /// @notice Grace period after timelock expiry for state computation
    /// @dev Configurable timeframe allowing state transitions after proposal expiry
    uint256 public immutable gracePeriod;

    /// EIP-1967 pattern for deterministic storage slot generation.
    bytes32 private constant STORAGE_SLOT = bytes32(uint256(keccak256("BaseAllocationMechanism.storage")) - 1);

    /// @notice Immutable configuration parameters
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
    /// @notice ERC20 asset used for the vault
    IERC20 public immutable asset;

    /// @notice Main storage struct containing all mutable state
    struct BaseAllocationStorage {
        // Basic token information
        string name;
        string symbol;
        // Voting state
        bool tallyFinalized;
        uint256 proposalIdCounter;
        // Mappings
        mapping(uint256 => Proposal) proposals;
        mapping(uint256 => ProposalVote) proposalVotes;
        mapping(address => bool) recipientUsed;
        mapping(uint256 => mapping(address => bool)) hasVoted;
        mapping(address => uint256) votingPower;
        mapping(address => uint256) redeemableAfter;
        mapping(uint256 => uint256) proposalShares;
    }

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

    /// @notice Get the storage struct from the predefined slot
    /// @return s The storage struct containing all mutable state
    function _getStorage() internal pure returns (BaseAllocationStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /// @notice Public getter for name (delegating to storage)
    function name() public view returns (string memory) {
        return _getStorage().name;
    }

    /// @notice Public getter for symbol (delegating to storage)
    function symbol() public view returns (string memory) {
        return _getStorage().symbol;
    }

    /// @notice Public getter for tallyFinalized (delegating to storage)
    function tallyFinalized() public view returns (bool) {
        return _getStorage().tallyFinalized;
    }

    /// @notice Public getter for proposals mapping (delegating to storage)
    function proposals(uint256 pid) public view returns (Proposal memory) {
        return _getStorage().proposals[pid];
    }

    /// @notice Public getter for proposalVotes mapping (delegating to storage)
    function proposalVotes(uint256 pid) public view returns (ProposalVote memory) {
        return _getStorage().proposalVotes[pid];
    }

    /// @notice Public getter for hasVoted mapping (delegating to storage)
    function hasVoted(uint256 pid, address voter) public view returns (bool) {
        return _getStorage().hasVoted[pid][voter];
    }

    /// @notice Public getter for votingPower mapping (delegating to storage)
    function votingPower(address user) public view returns (uint256) {
        return _getStorage().votingPower[user];
    }

    /// @notice Public getter for redeemableAfter mapping (delegating to storage)
    function redeemableAfter(address recipient) public view returns (uint256) {
        return _getStorage().redeemableAfter[recipient];
    }

    /// @notice Public getter for proposalShares mapping (delegating to storage)
    function proposalShares(uint256 pid) public view returns (uint256) {
        return _getStorage().proposalShares[pid];
    }

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
    /// @param _gracePeriod Seconds after timelock expiry for state computation
    /// @param _startBlock Block number when voting mechanism starts
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumShares,
        uint256 _timelockDelay,
        uint256 _gracePeriod,
        uint256 _startBlock
    ) Ownable(msg.sender) {
        if (address(_asset) == address(0)) revert ZeroAssetAddress();
        if (_votingDelay == 0) revert ZeroVotingDelay();
        if (_votingPeriod == 0) revert ZeroVotingPeriod();
        if (_quorumShares == 0) revert ZeroQuorumShares();
        if (_timelockDelay == 0) revert ZeroTimelockDelay();
        if (_gracePeriod == 0) revert ZeroGracePeriod();
        if (_startBlock == 0) revert ZeroStartBlock();
        if (bytes(_name).length == 0) revert EmptyName();
        if (bytes(_symbol).length == 0) revert EmptySymbol();

        // Set immutable values
        asset = _asset;
        votingDelay = _votingDelay;
        votingPeriod = _votingPeriod;
        quorumShares = _quorumShares;
        timelockDelay = _timelockDelay;
        gracePeriod = _gracePeriod;
        startBlock = _startBlock;

        // Initialize storage struct
        BaseAllocationStorage storage s = _getStorage();
        s.name = _name;
        s.symbol = _symbol;
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
    function _beforeFinalizeVoteTallyHook() internal virtual returns (bool);

    /// @dev a hook to fetch the recipient address for a proposal. Can be used to enforce additional checks or actions.
    /// @param pid Proposal ID being redeemed
    /// @return recipient Address of the recipient for the proposal
    function _getRecipientAddressHook(uint256 pid) internal view virtual returns (address recipient);

    /// @dev Hook to perform the actual distribution of shares when a proposal is queued.
    /// This is where the concrete implementation should mint shares, transfer tokens, or perform the actual distribution.
    /// For vault-based mechanisms, this is where shares would be minted to the recipient.
    /// @param recipient Address of the recipient for the proposal
    /// @param sharesToMint Number of shares to distribute/mint to the recipient
    /// @return success True if distribution was successful
    function _requestDistributionHook(address recipient, uint256 sharesToMint) internal virtual returns (bool);

    // ---------- Registration ----------

    /// @notice Register to gain voting power by depositing underlying tokens.
    /// @param deposit Amount of underlying to deposit (may be zero).
    function signup(uint256 deposit) external nonReentrant whenNotPaused {
        address user = msg.sender;
        if (!_beforeSignupHook(user)) revert RegistrationBlocked();
        if (block.number >= startBlock + votingDelay + votingPeriod) revert VotingEnded();
        BaseAllocationStorage storage s = _getStorage();
        if (s.votingPower[user] != 0) revert AlreadyRegistered();
        if (deposit > MAX_SAFE_VALUE) revert DepositTooLarge();
        if (deposit > 0) asset.safeTransferFrom(user, address(this), deposit);
        uint256 newPower = _getVotingPowerHook(user, deposit);
        if (newPower > MAX_SAFE_VALUE) revert VotingPowerTooLarge();
        s.votingPower[user] = newPower;
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
        BaseAllocationStorage storage s = _getStorage();
        if (s.recipientUsed[recipient]) revert RecipientUsed();
        if (bytes(description).length == 0) revert EmptyDescription();
        if (bytes(description).length > 1000) revert DescriptionTooLong();

        if (s.proposalIdCounter >= type(uint256).max) revert MaxProposalsReached();
        s.proposalIdCounter++;
        pid = s.proposalIdCounter;

        s.proposals[pid] = Proposal(0, 0, proposer, recipient, description, false, false);
        s.recipientUsed[recipient] = true;

        emit ProposalCreated(pid, proposer, recipient, description);
    }

    // ---------- Vote Tally Finalization ----------

    /// @notice Finalize vote tally once voting period (from first proposal) has ended.
    /// @dev **SECURITY CRITICAL**: ensure this can only be called once and only after voting ends.
    function finalizeVoteTally() external onlyOwner {
        if (block.number < startBlock + votingDelay + votingPeriod) revert VotingNotEnded();
        BaseAllocationStorage storage s = _getStorage();
        if (s.tallyFinalized) revert TallyAlreadyFinalized();
        if (!_beforeFinalizeVoteTallyHook()) revert FinalizationBlocked();
        s.tallyFinalized = true;
        emit VoteTallyFinalized();
    }

    // ---------- Queue Proposal & Mint Allocation ----------

    /// @notice Queue proposal and mint vault shares based on vote tallies.
    /// @dev Calls `_convertVotesToShares(pid)` to determine mint amount.
    /// @param pid Proposal ID to queue.
    function queueProposal(uint256 pid) external onlyOwner {
        BaseAllocationStorage storage s = _getStorage();
        if (!s.tallyFinalized) revert TallyNotFinalized();
        if (!_validateProposalHook(pid)) revert InvalidProposal();
        Proposal storage p = s.proposals[pid];
        if (p.canceled) revert ProposalCanceledError();
        if (!_hasQuorumHook(pid)) revert NoQuorum();
        if (p.eta != 0) revert AlreadyQueued();

        uint256 sharesToMint = _convertVotesToShares(pid);
        if (sharesToMint == 0) revert NoAllocation();
        s.proposalShares[pid] = sharesToMint;

        _requestDistributionHook(_getRecipientAddressHook(pid), sharesToMint);

        uint256 eta = block.timestamp + timelockDelay;
        p.eta = eta;
        p.claimed = true;
        s.redeemableAfter[p.recipient] = eta;
        emit ProposalQueued(pid, eta, sharesToMint);
    }

    // ---------- Voting ----------

    /// @notice Cast a vote on a proposal.
    /// @param pid Proposal ID
    /// @param choice VoteType (Against, For, Abstain)
    /// @param weight Amount of voting power to apply
    function castVote(uint256 pid, VoteType choice, uint256 weight) external nonReentrant whenNotPaused {
        if (!_validateProposalHook(pid)) revert InvalidProposal();
        if (block.number < startBlock + votingDelay || block.number > startBlock + votingDelay + votingPeriod)
            revert VotingClosed();
        BaseAllocationStorage storage s = _getStorage();
        if (s.hasVoted[pid][msg.sender]) revert AlreadyVoted();

        uint256 oldPower = s.votingPower[msg.sender];
        if (weight == 0 || weight > oldPower) revert InvalidWeight();
        if (weight > MAX_SAFE_VALUE) revert WeightTooLarge();

        uint256 newPower = _processVoteHook(pid, msg.sender, choice, weight, oldPower);
        if (newPower > oldPower) revert PowerIncreased();

        s.votingPower[msg.sender] = newPower;
        s.hasVoted[pid][msg.sender] = true;
        emit VotesCast(msg.sender, pid, choice, weight);
    }

    // ---------- State Machine ----------

    /// @dev Internal state computation for a proposal
    function _state(uint256 pid) internal view returns (ProposalState) {
        BaseAllocationStorage storage s = _getStorage();
        Proposal storage p = s.proposals[pid];
        if (p.canceled) return ProposalState.Canceled;
        if (block.number < startBlock) return ProposalState.Pending;
        if (block.number <= startBlock + votingDelay + votingPeriod) return ProposalState.Active;
        if (!_hasQuorumHook(pid)) return ProposalState.Defeated;
        if (p.eta == 0) return ProposalState.Pending;
        if (p.claimed) return ProposalState.Succeeded;
        if (block.timestamp > p.eta + gracePeriod) return ProposalState.Expired;
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
        BaseAllocationStorage storage s = _getStorage();
        if (!_validateProposalHook(pid)) revert InvalidProposal();
        Proposal storage p = s.proposals[pid];
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
    function getVoteTally(
        uint256 pid
    ) external view returns (uint256 sharesFor, uint256 sharesAgainst, uint256 sharesAbstain) {
        BaseAllocationStorage storage s = _getStorage();
        if (!_validateProposalHook(pid)) revert InvalidProposal();
        ProposalVote storage votes = s.proposalVotes[pid];
        return (votes.sharesFor, votes.sharesAgainst, votes.sharesAbstain);
    }

    /// @notice Get remaining voting power for an address
    /// @param voter Address to check voting power for
    /// @return Remaining voting power
    function getRemainingVotingPower(address voter) external view returns (uint256) {
        BaseAllocationStorage storage s = _getStorage();
        return s.votingPower[voter];
    }

    /// @notice Get total number of proposals created
    /// @return Total proposal count
    function getProposalCount() external view returns (uint256) {
        BaseAllocationStorage storage s = _getStorage();
        return s.proposalIdCounter;
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
