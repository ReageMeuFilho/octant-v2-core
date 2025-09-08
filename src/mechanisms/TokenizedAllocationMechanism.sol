// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Interface for base allocation mechanism strategy implementations
/// @dev Follows Yearn V3 pattern where shared implementation calls base strategy via interface
interface IBaseAllocationStrategy {
    /// @dev Hook to allow or block registration
    function beforeSignupHook(address user) external returns (bool);

    /// @dev Hook to allow or block proposal creation
    function beforeProposeHook(address proposer) external view returns (bool);

    /// @dev Hook to calculate new voting power on registration
    function getVotingPowerHook(address user, uint256 deposit) external view returns (uint256);

    /// @dev Hook to validate existence and integrity of a proposal ID
    function validateProposalHook(uint256 pid) external view returns (bool);

    /// @dev Hook to process a vote
    function processVoteHook(
        uint256 pid,
        address voter,
        uint8 choice,
        uint256 weight,
        uint256 oldPower
    ) external returns (uint256 newPower);

    /// @dev Check if proposal met quorum requirement
    function hasQuorumHook(uint256 pid) external view returns (bool);

    /// @dev Hook to convert final vote tallies into vault shares to mint
    function convertVotesToShares(uint256 pid) external view returns (uint256 sharesToMint);

    /// @dev Hook to modify the behavior of finalizeVoteTally
    function beforeFinalizeVoteTallyHook() external returns (bool);

    /// @dev Hook to fetch the recipient address for a proposal
    function getRecipientAddressHook(uint256 pid) external view returns (address recipient);

    /// @dev Hook to perform custom distribution of shares when a proposal is queued
    /// @dev If this returns (true, assetsTransferred), default share minting is skipped and totalAssets is updated
    /// @param recipient Address of the recipient for the proposal
    /// @param sharesToMint Number of shares to distribute/mint to the recipient
    /// @return handled True if custom distribution was handled, false to use default minting
    /// @return assetsTransferred Amount of assets transferred directly to recipient (to update totalAssets)
    function requestCustomDistributionHook(
        address recipient,
        uint256 sharesToMint
    ) external returns (bool handled, uint256 assetsTransferred);

    /// @dev Hook to get the available withdraw limit for a share owner
    function availableWithdrawLimit(address shareOwner) external view returns (uint256);

    /// @dev Hook to calculate total assets including any matching pools or custom logic
    function calculateTotalAssetsHook() external view returns (uint256);
}

/// @title Tokenized Allocation Mechanism - Shared Implementation
/// @notice Provides the shared implementation for all allocation mechanisms following the Yearn V3 pattern
/// @dev This contract handles all standard allocation logic, storage, and state management
contract TokenizedAllocationMechanism is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;
    using Math for uint256;

    // Custom Errors
    error ZeroAssetAddress();
    error ZeroVotingDelay();
    error ZeroVotingPeriod();
    error ZeroQuorumShares();
    error ZeroTimelockDelay();
    error ZeroGracePeriod();
    error ZeroStartBlock();
    error InvalidStartTime(uint256 startTime, uint256 currentTime);
    error EmptyName();
    error EmptySymbol();
    error RegistrationBlocked(address user);
    error VotingEnded(uint256 currentTime, uint256 endTime);
    error AlreadyRegistered(address user);
    error DepositTooLarge(uint256 deposit, uint256 maxAllowed);
    error VotingPowerTooLarge(uint256 votingPower, uint256 maxAllowed);
    error InsufficientDeposit(uint256 deposit);
    error ProposeNotAllowed(address proposer);
    error InvalidRecipient(address recipient);
    error InvalidUser(address user);
    error RecipientUsed(address recipient);
    error RecipientMismatch(uint256 pid, address expected, address actual);
    error DescriptionMismatch(uint256 pid);
    error EmptyDescription();
    error DescriptionTooLong(uint256 length, uint256 maxLength);
    error VotingNotEnded(uint256 currentTime, uint256 endTime);
    error TallyAlreadyFinalized();
    error FinalizationBlocked();
    error TallyNotFinalized();
    error InvalidProposal(uint256 pid);
    error ProposalCanceledError(uint256 pid);
    error NoQuorum(uint256 pid, uint256 forVotes, uint256 againstVotes, uint256 required);
    error AlreadyQueued(uint256 pid);
    error QueueingClosedAfterRedemption();
    error NoAllocation(uint256 pid, uint256 sharesToMint);
    error InsufficientAssets(uint256 requested, uint256 available);
    error VotingClosed(uint256 currentTime, uint256 startTime, uint256 endTime);
    error InvalidWeight(uint256 weight, uint256 votingPower);
    error WeightTooLarge(uint256 weight, uint256 maxAllowed);
    error PowerIncreased(uint256 oldPower, uint256 newPower);
    error NotProposer(address caller, address proposer);
    error AlreadyCanceled(uint256 pid);
    error Unauthorized();
    error AlreadyInitialized();
    error PausedError();
    error ExpiredSignature(uint256 deadline, uint256 currentTime);
    error InvalidSignature();
    error InvalidSigner(address recovered, address expected);

    /// @notice Maximum safe value for mathematical operations
    uint256 public constant MAX_SAFE_VALUE = type(uint128).max;

    /// @notice Storage slot for allocation mechanism data (EIP-1967 pattern)
    bytes32 private constant ALLOCATION_STORAGE_SLOT = bytes32(uint256(keccak256("tokenized.allocation.storage")) - 1);

    /// @notice EIP712 Domain separator typehash per EIP-2612
    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Signup typehash for EIP712 structured data
    bytes32 private constant SIGNUP_TYPEHASH =
        keccak256("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)");

    /// @notice CastVote typehash for EIP712 structured data
    bytes32 private constant CAST_VOTE_TYPEHASH =
        keccak256(
            "CastVote(address voter,uint256 proposalId,uint8 choice,uint256 weight,address expectedRecipient,uint256 nonce,uint256 deadline)"
        );

    /// @notice EIP712 version for domain separator
    string private constant EIP712_VERSION = "1";

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
        Tallying,
        Defeated,
        Succeeded,
        Queued,
        Redeemable,
        Expired
    }

    struct Proposal {
        uint256 sharesRequested;
        address proposer;
        address recipient;
        string description;
        bool canceled;
    }

    /// @notice Main storage struct containing all allocation mechanism state
    struct AllocationStorage {
        // Basic information
        string name;
        string symbol;
        IERC20 asset;
        // Configuration (immutable after initialization)
        uint256 startBlock;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 timelockDelay;
        uint256 gracePeriod;
        uint256 quorumShares;
        uint256 startTime; // Start timestamp for the mechanism
        uint256 votingStartTime; // startTime + votingDelay (when voting can begin)
        uint256 votingEndTime; // startTime + votingDelay + votingPeriod (when voting ends)
        uint256 tallyFinalizedTime; // when finalizeVoteTally() was called
        // Access control
        address owner;
        address pendingOwner;
        bool paused;
        bool initialized;
        // Voting state
        bool tallyFinalized;
        uint256 proposalIdCounter;
        uint256 globalRedemptionStart; // Global timestamp when all redemptions and transfers can begin
        uint256 globalRedemptionEndTime; // Global timestamp when redemption period ends
        // Allocation Mechanism Vault Storage (merged from DistributionMechanism)
        mapping(address => uint256) nonces; // Mapping of nonces used for permit functions
        mapping(address => uint256) balances; // Mapping to track current balances for each account that holds shares
        mapping(address => mapping(address => uint256)) allowances; // Mapping to track the allowances for the strategies shares
        uint256 totalSupply; // The total amount of shares currently issued
        uint256 totalAssets; // We manually track `totalAssets` to prevent PPS manipulation through airdrops
        // Strategy Management
        address keeper; // Address given permission to call {report} and {tend}
        address management; // Main address that can set all configurable variables
        address emergencyAdmin; // Address to act in emergencies as well as `management`
        uint8 decimals; // The amount of decimals that `asset` and strategy use
        // Mappings
        mapping(uint256 => Proposal) proposals;
        mapping(address => bool) recipientUsed;
        mapping(address => uint256) votingPower;
        mapping(uint256 => uint256) proposalShares;
        // EIP712 storage
        bytes32 domainSeparator; // Cached domain separator
        uint256 initialChainId; // Chain ID at deployment for fork protection
    }

    // ---------- Storage Access for Hooks ----------

    /// @notice Emitted when a user completes registration
    event UserRegistered(address indexed user, uint256 votingPower);
    /// @notice Emitted when a new proposal is created
    event ProposalCreated(uint256 indexed pid, address indexed proposer, address indexed recipient, string description);
    /// @notice Emitted when a vote is cast
    event VotesCast(address indexed voter, uint256 indexed pid, uint256 weight);
    /// @notice Emitted when vote tally is finalized
    event VoteTallyFinalized();
    /// @notice Emitted when a proposal is queued and shares minted
    event ProposalQueued(uint256 indexed pid, uint256 eta, uint256 shareAmount);
    /// @notice Emitted when a proposal is canceled
    event ProposalCanceled(uint256 indexed pid, address indexed proposer);
    /// @notice Emitted when ownership transfer is initiated
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);
    /// @notice Emitted when ownership transfer is canceled
    event OwnershipTransferCanceled(address indexed currentOwner, address indexed canceledPendingOwner);
    /// @notice Emitted when ownership is transferred
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when keeper is updated
    event KeeperUpdated(address indexed previousKeeper, address indexed newKeeper);
    /// @notice Emitted when management is updated
    event ManagementUpdated(address indexed previousManagement, address indexed newManagement);
    /// @notice Emitted when emergency admin is updated
    event EmergencyAdminUpdated(address indexed previousEmergencyAdmin, address indexed newEmergencyAdmin);
    /// @notice Emitted when contract is paused/unpaused
    event PausedStatusChanged(bool paused);
    /// @notice Emitted when global redemption period is set
    event GlobalRedemptionPeriodSet(uint256 redemptionStart, uint256 redemptionEnd);
    /// @notice Emitted when tokens are swept after grace period
    event Swept(address indexed token, address indexed receiver, uint256 amount);

    // Additional events from DistributionMechanism
    /// @notice Emitted when the allowance of a `spender` for an `owner` is set by a call to {approve}. `value` is the new allowance.
    event Approval(address indexed owner, address indexed spender, uint256 value);
    /// @notice Emitted when `value` tokens are moved from one account (`from`) to another (`to`).
    event Transfer(address indexed from, address indexed to, uint256 value);
    /// @notice Emitted when the `caller` has exchanged `owner`s `shares` for `assets`, and transferred those `assets` to `receiver`.
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    // ---------- Storage Access ----------

    /// @notice Get the storage struct from the predefined slot
    /// @return s The storage struct containing all mutable state
    function _getStorage() internal pure returns (AllocationStorage storage s) {
        bytes32 slot = ALLOCATION_STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /// @notice Constructor to prevent initialization of the library implementation
    constructor() {
        AllocationStorage storage s = _getStorage();
        s.initialized = true; // Prevent initialization on the library contract
    }

    /// @notice Returns the domain separator, updating it if chain ID changed (fork protection)
    function DOMAIN_SEPARATOR() public returns (bytes32) {
        AllocationStorage storage s = _getStorage();
        if (block.chainid == s.initialChainId) {
            return s.domainSeparator;
        } else {
            s.initialChainId = block.chainid;

            bytes32 domainSeparator = _computeDomainSeparator(s);
            s.domainSeparator = domainSeparator;
            return domainSeparator;
        }
    }

    /// @dev Computes the domain separator
    function _computeDomainSeparator(AllocationStorage storage s) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TYPE_HASH,
                    keccak256(bytes(s.name)),
                    keccak256(bytes(EIP712_VERSION)),
                    block.chainid,
                    address(this)
                )
            );
    }

    // ---------- Modifiers ----------

    modifier onlyOwner() {
        AllocationStorage storage s = _getStorage();
        if (msg.sender != s.owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (_getStorage().paused) revert PausedError();
        _;
    }

    // ---------- Initialization ----------

    /// @notice Initialize the allocation mechanism with configuration
    /// @dev Can only be called once by the strategy contract
    function initialize(
        address _owner,
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumShares,
        uint256 _timelockDelay,
        uint256 _gracePeriod
    ) external {
        _initializeAllocation(
            _owner,
            _asset,
            _name,
            _symbol,
            _votingDelay,
            _votingPeriod,
            _quorumShares,
            _timelockDelay,
            _gracePeriod
        );
    }

    /// @notice Internal allocation mechanism initialization
    function _initializeAllocation(
        address _owner,
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumShares,
        uint256 _timelockDelay,
        uint256 _gracePeriod
    ) internal {
        AllocationStorage storage s = _getStorage();

        // Validate inputs
        if (_owner == address(0)) revert Unauthorized();
        if (address(_asset) == address(0)) revert ZeroAssetAddress();
        if (_votingDelay == 0) revert ZeroVotingDelay();
        if (_votingPeriod == 0) revert ZeroVotingPeriod();
        if (_quorumShares == 0) revert ZeroQuorumShares();
        if (_timelockDelay == 0) revert ZeroTimelockDelay();
        if (_gracePeriod == 0) revert ZeroGracePeriod();
        if (bytes(_name).length == 0) revert EmptyName();
        if (bytes(_symbol).length == 0) revert EmptySymbol();
        if (s.initialized == true) revert AlreadyInitialized();

        // Set configuration
        s.owner = _owner;
        s.asset = _asset;
        s.name = _name;
        s.symbol = _symbol;
        s.votingDelay = _votingDelay;
        s.votingPeriod = _votingPeriod;
        s.quorumShares = _quorumShares;
        s.timelockDelay = _timelockDelay;
        s.gracePeriod = _gracePeriod;
        s.startBlock = block.number; // Keep for legacy getter compatibility
        s.initialized = true;

        // Set timestamp-based timeline starting from deployment time
        s.startTime = block.timestamp;
        s.votingStartTime = s.startTime + _votingDelay;
        s.votingEndTime = s.votingStartTime + _votingPeriod;

        // Set management roles to owner
        s.management = _owner;
        s.keeper = _owner;
        s.emergencyAdmin = _owner;
        s.decimals = ERC20(address(_asset)).decimals();

        // Initialize EIP712 domain separator
        s.initialChainId = block.chainid;
        s.domainSeparator = _computeDomainSeparator(s);

        emit OwnershipTransferred(address(0), _owner);
    }

    // ---------- Registration ----------

    /// @notice Register to gain voting power by depositing underlying tokens
    /// @param deposit Amount of underlying to deposit (may be zero)
    function signup(uint256 deposit) external nonReentrant whenNotPaused {
        _executeSignup(msg.sender, deposit, msg.sender);
    }

    /// @notice Register on behalf of another user using EIP-2612 style signature
    /// @param user Address of the user signing up
    /// @param deposit Amount of underlying to deposit
    /// @param deadline Expiration timestamp for the signature
    /// @param v Signature parameter
    /// @param r Signature parameter
    /// @param s Signature parameter
    /// @dev The deposit will be taken from msg.sender, not the user
    function signupOnBehalfWithSignature(
        address user,
        uint256 deposit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        _validateSignature(
            user,
            keccak256(abi.encode(SIGNUP_TYPEHASH, user, msg.sender, deposit, _getStorage().nonces[user]++, deadline)),
            deadline,
            v,
            r,
            s
        );
        _executeSignup(user, deposit, msg.sender);
    }

    /// @notice Register with voting power using EIP-2612 style signature
    /// @param user Address of the user signing up
    /// @param deposit Amount of underlying to deposit
    /// @param deadline Expiration timestamp for the signature
    /// @param v Signature parameter
    /// @param r Signature parameter
    /// @param s Signature parameter
    /// @dev The deposit will be taken from the user themselves
    function signupWithSignature(
        address user,
        uint256 deposit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        _validateSignature(
            user,
            keccak256(abi.encode(SIGNUP_TYPEHASH, user, user, deposit, _getStorage().nonces[user]++, deadline)),
            deadline,
            v,
            r,
            s
        );
        _executeSignup(user, deposit, user);
    }

    /// @dev Validates signature parameters
    function _validateSignature(
        address expectedSigner,
        bytes32 structHash,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        // Check deadline
        if (block.timestamp > deadline) revert ExpiredSignature(deadline, block.timestamp);

        // Recover signer
        address recoveredAddress = _recover(structHash, v, r, s);
        if (recoveredAddress == address(0)) revert InvalidSignature();
        if (recoveredAddress != expectedSigner) revert InvalidSigner(recoveredAddress, expectedSigner);
    }

    /// @dev Internal signup execution logic
    function _executeSignup(address user, uint256 deposit, address payer) private {
        AllocationStorage storage s = _getStorage();

        // Prevent zero address registration
        if (user == address(0)) revert InvalidUser(user);

        // Call hook for validation via interface (Yearn V3 pattern)
        if (!IBaseAllocationStrategy(address(this)).beforeSignupHook(user)) {
            revert RegistrationBlocked(user);
        }

        if (block.timestamp > s.votingEndTime) revert VotingEnded(block.timestamp, s.votingEndTime);

        if (deposit > MAX_SAFE_VALUE) revert DepositTooLarge(deposit, MAX_SAFE_VALUE);

        if (deposit > 0) s.asset.safeTransferFrom(payer, address(this), deposit);

        uint256 newPower = IBaseAllocationStrategy(address(this)).getVotingPowerHook(user, deposit);
        if (newPower > MAX_SAFE_VALUE) revert VotingPowerTooLarge(newPower, MAX_SAFE_VALUE);

        // Prevent registration with zero voting power when deposit is non-zero
        if (newPower == 0 && deposit > 0) revert InsufficientDeposit(deposit);

        // Add to existing voting power to support multiple signups
        uint256 totalPower = s.votingPower[user] + newPower;
        if (totalPower > MAX_SAFE_VALUE) revert VotingPowerTooLarge(totalPower, MAX_SAFE_VALUE);

        s.votingPower[user] = totalPower;
        emit UserRegistered(user, newPower);
    }

    /// @dev Recovers signer address from signature
    function _recover(bytes32 structHash, uint8 v, bytes32 r, bytes32 s) private returns (address) {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        return ecrecover(digest, v, r, s);
    }

    // ---------- Proposal Creation ----------

    /// @notice Create a new proposal targeting `recipient`
    /// @param recipient Address to receive allocated vault shares upon queue
    /// @param description Description or rationale for the proposal
    /// @return pid Unique identifier for the new proposal
    function propose(
        address recipient,
        string calldata description
    ) external whenNotPaused nonReentrant returns (uint256 pid) {
        address proposer = msg.sender;

        // Call hook for validation - Potential DoS risk - malicious keeper/management contracts could revert these calls
        if (!IBaseAllocationStrategy(address(this)).beforeProposeHook(proposer)) revert ProposeNotAllowed(proposer);

        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient(recipient);

        AllocationStorage storage s = _getStorage();

        // Proposing only allowed before voting period ends
        if (block.timestamp > s.votingEndTime) {
            revert VotingEnded(block.timestamp, s.votingEndTime);
        }

        if (s.recipientUsed[recipient]) revert RecipientUsed(recipient);
        if (bytes(description).length == 0) revert EmptyDescription();
        if (bytes(description).length > 1000) revert DescriptionTooLong(bytes(description).length, 1000);

        pid = ++s.proposalIdCounter;

        s.proposals[pid] = Proposal(0, proposer, recipient, description, false);
        s.recipientUsed[recipient] = true;

        emit ProposalCreated(pid, proposer, recipient, description);
    }

    // ---------- Voting ----------

    /// @notice Cast a vote on a proposal
    /// @param pid Proposal ID
    /// @param choice VoteType (Against, For, Abstain)
    /// @param weight Amount of voting power to apply
    /// @param expectedRecipient Expected recipient address to prevent reorganization attacks
    function castVote(
        uint256 pid,
        VoteType choice,
        uint256 weight,
        address expectedRecipient
    ) external nonReentrant whenNotPaused {
        _executeCastVote(msg.sender, pid, choice, weight, expectedRecipient);
    }

    /// @notice Cast vote using EIP-2612 style signature
    /// @param voter Address of the voter
    /// @param pid Proposal ID
    /// @param choice Vote choice (Against, For, Abstain)
    /// @param weight Voting weight to use
    /// @param expectedRecipient Expected recipient address for the proposal
    /// @param deadline Expiration timestamp for the signature
    /// @param v Signature parameter
    /// @param r Signature parameter
    /// @param s Signature parameter
    function castVoteWithSignature(
        address voter,
        uint256 pid,
        VoteType choice,
        uint256 weight,
        address expectedRecipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        uint256 nonce = _getStorage().nonces[voter]++;
        _validateSignature(
            voter,
            keccak256(
                abi.encode(CAST_VOTE_TYPEHASH, voter, pid, uint8(choice), weight, expectedRecipient, nonce, deadline)
            ),
            deadline,
            v,
            r,
            s
        );
        _executeCastVote(voter, pid, choice, weight, expectedRecipient);
    }

    /// @dev Internal vote execution logic
    function _executeCastVote(
        address voter,
        uint256 pid,
        VoteType choice,
        uint256 weight,
        address expectedRecipient
    ) private {
        AllocationStorage storage s = _getStorage();

        // Validate proposal
        if (!IBaseAllocationStrategy(address(this)).validateProposalHook(pid)) revert InvalidProposal(pid);

        // Check if proposal is canceled
        Proposal storage p = s.proposals[pid];
        if (p.canceled) revert ProposalCanceledError(pid);

        // Verify recipient matches voter's expectation to prevent reorganization attacks
        if (p.recipient != expectedRecipient) revert RecipientMismatch(pid, expectedRecipient, p.recipient);

        // Cache storage timestamps to avoid multiple reads in error message
        uint256 votingStart = s.votingStartTime;
        uint256 votingEnd = s.votingEndTime;

        // Check voting window
        if (block.timestamp < votingStart || block.timestamp > votingEnd)
            revert VotingClosed(block.timestamp, votingStart, votingEnd);

        uint256 oldPower = s.votingPower[voter];
        if (weight == 0) revert InvalidWeight(weight, oldPower);
        if (weight > MAX_SAFE_VALUE) revert WeightTooLarge(weight, MAX_SAFE_VALUE);

        // Note: weight > oldPower check is redundant with processVoteHook's quadratic cost validation
        // The hook will revert with InsufficientVotingPowerForQuadraticCost if weight^2 > oldPower
        uint256 newPower = IBaseAllocationStrategy(address(this)).processVoteHook(
            pid,
            voter,
            uint8(choice),
            weight,
            oldPower
        );
        if (newPower > oldPower) revert PowerIncreased(oldPower, newPower);

        s.votingPower[voter] = newPower;
        emit VotesCast(voter, pid, weight);
    }

    // ---------- Vote Tally Finalization ----------

    /// @notice Finalize vote tally once voting period has ended
    function finalizeVoteTally() external onlyOwner nonReentrant {
        AllocationStorage storage s = _getStorage();

        if (block.timestamp <= s.votingEndTime) revert VotingNotEnded(block.timestamp, s.votingEndTime);

        if (s.tallyFinalized) revert TallyAlreadyFinalized();

        if (!IBaseAllocationStrategy(address(this)).beforeFinalizeVoteTallyHook()) revert FinalizationBlocked();

        // Set total assets using strategy-specific calculation
        // This allows for custom logic like matching pools in quadratic funding
        s.totalAssets = IBaseAllocationStrategy(address(this)).calculateTotalAssetsHook();

        // Set global redemption start time for all proposals
        s.globalRedemptionStart = block.timestamp + s.timelockDelay;
        s.globalRedemptionEndTime = s.globalRedemptionStart + s.gracePeriod;
        s.tallyFinalizedTime = block.timestamp;

        s.tallyFinalized = true;
        emit VoteTallyFinalized();
        emit GlobalRedemptionPeriodSet(s.globalRedemptionStart, s.globalRedemptionEndTime);
    }

    // ---------- Queue Proposal ----------

    /// @notice Queue proposal and trigger share distribution
    /// @param pid Proposal ID to queue
    function queueProposal(uint256 pid) external nonReentrant {
        AllocationStorage storage s = _getStorage();

        if (!s.tallyFinalized) revert TallyNotFinalized();
        // Check if redemption period has started - no new queuing after redemption begins
        if (s.globalRedemptionStart != 0 && block.timestamp >= s.globalRedemptionStart) {
            revert QueueingClosedAfterRedemption();
        }
        if (!IBaseAllocationStrategy(address(this)).validateProposalHook(pid)) revert InvalidProposal(pid);

        Proposal storage p = s.proposals[pid];
        if (p.canceled) revert ProposalCanceledError(pid);

        if (!IBaseAllocationStrategy(address(this)).hasQuorumHook(pid)) revert NoQuorum(pid, 0, 0, s.quorumShares);

        if (s.proposalShares[pid] != 0) revert AlreadyQueued(pid);

        uint256 sharesToMint = IBaseAllocationStrategy(address(this)).convertVotesToShares(pid);
        if (sharesToMint == 0) revert NoAllocation(pid, sharesToMint);

        s.proposalShares[pid] = sharesToMint;

        address recipient = IBaseAllocationStrategy(address(this)).getRecipientAddressHook(pid);

        // Try custom distribution hook first
        (bool customDistributionHandled, uint256 assetsTransferred) = IBaseAllocationStrategy(address(this))
            .requestCustomDistributionHook(recipient, sharesToMint);

        // If custom distribution was handled, update totalAssets to reflect assets transferred out
        if (customDistributionHandled) {
            if (assetsTransferred > s.totalAssets) revert InsufficientAssets(assetsTransferred, s.totalAssets);
            s.totalAssets -= assetsTransferred;
        } else {
            // If custom distribution wasn't handled, mint shares by default
            _mint(s, recipient, sharesToMint);
        }

        emit ProposalQueued(pid, s.globalRedemptionStart, sharesToMint);
    }

    // ---------- State Machine ----------

    /// @notice Get the current state of a proposal
    /// @param pid Proposal ID
    /// @return Current state of the proposal
    function state(uint256 pid) external view returns (ProposalState) {
        if (!IBaseAllocationStrategy(address(this)).validateProposalHook(pid)) revert InvalidProposal(pid);
        return _state(pid);
    }

    /// @dev Internal state computation for a proposal with direct time range checks
    function _state(uint256 pid) internal view returns (ProposalState) {
        AllocationStorage storage s = _getStorage();
        Proposal storage p = s.proposals[pid];

        if (p.canceled) return ProposalState.Canceled;

        // Check if proposal failed quorum (defeated proposals never change state)
        if (s.tallyFinalized && !IBaseAllocationStrategy(address(this)).hasQuorumHook(pid)) {
            return ProposalState.Defeated;
        }

        // Before voting starts (Pending or Delay phases)
        if (block.timestamp < s.votingStartTime) {
            return ProposalState.Pending;
        }
        // During voting period or before tally finalized
        else if (block.timestamp <= s.votingEndTime) {
            return ProposalState.Active;
        }
        // After voting ends but before tally finalized
        else if (!s.tallyFinalized) {
            return ProposalState.Tallying;
        }

        uint256 shares = s.proposalShares[pid];

        // After tally finalized - check if queued or succeeded
        if (s.globalRedemptionStart != 0 && block.timestamp < s.globalRedemptionStart) {
            return shares == 0 ? ProposalState.Succeeded : ProposalState.Queued;
        }
        // During redemption period
        else if (s.globalRedemptionEndTime != 0 && block.timestamp <= s.globalRedemptionEndTime) {
            return shares == 0 ? ProposalState.Succeeded : ProposalState.Redeemable;
        }
        // After redemption period (grace period expired)
        else {
            return ProposalState.Expired;
        }
    }

    // ---------- Proposal Management ----------

    /// @notice Cancel a proposal
    /// @dev Can only be called before vote tally is finalized. After finalization, all proposals are immutable.
    /// @dev This prevents race conditions and ensures coordinators can verify all proposals before committing.
    /// @param pid Proposal ID to cancel
    function cancelProposal(uint256 pid) external nonReentrant {
        AllocationStorage storage s = _getStorage();

        // Prevent cancellation after finalization - proposals become immutable
        if (s.tallyFinalized) revert TallyAlreadyFinalized();

        if (!IBaseAllocationStrategy(address(this)).validateProposalHook(pid)) revert InvalidProposal(pid);

        Proposal storage p = s.proposals[pid];
        if (msg.sender != p.proposer) revert NotProposer(msg.sender, p.proposer);
        if (p.canceled) revert AlreadyCanceled(pid);

        p.canceled = true;
        emit ProposalCanceled(pid, p.proposer);
    }

    // ---------- View Functions ----------

    /// @notice Get remaining voting power for an address
    function getRemainingVotingPower(address voter) external view returns (uint256) {
        return _getStorage().votingPower[voter];
    }

    /// @notice Get total number of proposals created
    function getProposalCount() external view returns (uint256) {
        return _getStorage().proposalIdCounter;
    }

    // Public getters for storage access
    function name() external view returns (string memory) {
        return _getStorage().name;
    }

    function symbol() external view returns (string memory) {
        return _getStorage().symbol;
    }

    function asset() external view returns (IERC20) {
        return _getStorage().asset;
    }

    function owner() external view returns (address) {
        return _getStorage().owner;
    }

    function pendingOwner() external view returns (address) {
        return _getStorage().pendingOwner;
    }

    function tallyFinalized() external view returns (bool) {
        return _getStorage().tallyFinalized;
    }

    function proposals(uint256 pid) external view returns (Proposal memory) {
        return _getStorage().proposals[pid];
    }

    function votingPower(address user) external view returns (uint256) {
        return _getStorage().votingPower[user];
    }

    function proposalShares(uint256 pid) external view returns (uint256) {
        return _getStorage().proposalShares[pid];
    }

    // Configuration getters
    function startBlock() external view returns (uint256) {
        return _getStorage().startBlock;
    }

    function votingDelay() external view returns (uint256) {
        return _getStorage().votingDelay;
    }

    function votingPeriod() external view returns (uint256) {
        return _getStorage().votingPeriod;
    }

    function quorumShares() external view returns (uint256) {
        return _getStorage().quorumShares;
    }

    function timelockDelay() external view returns (uint256) {
        return _getStorage().timelockDelay;
    }

    function gracePeriod() external view returns (uint256) {
        return _getStorage().gracePeriod;
    }

    function globalRedemptionStart() external view returns (uint256) {
        return _getStorage().globalRedemptionStart;
    }

    /// @notice Returns the current nonce for an address
    /// @param account The address to check
    /// @return The current nonce
    function nonces(address account) external view returns (uint256) {
        return _getStorage().nonces[account];
    }

    // ---------- Emergency Functions ----------

    /// @notice Initiate ownership transfer to a new address (step 1 of 2)
    /// @param newOwner The address to transfer ownership to
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert Unauthorized();
        AllocationStorage storage s = _getStorage();
        s.pendingOwner = newOwner;
        emit OwnershipTransferInitiated(s.owner, newOwner);
    }

    /// @notice Accept ownership transfer (step 2 of 2)
    /// @dev Must be called by the pending owner to complete the transfer
    function acceptOwnership() external {
        AllocationStorage storage s = _getStorage();
        address pending = s.pendingOwner;
        if (msg.sender != pending) revert Unauthorized();

        address oldOwner = s.owner;
        s.owner = pending;
        s.pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, pending);
    }

    /// @notice Cancel pending ownership transfer
    /// @dev Can only be called by current owner
    function cancelOwnershipTransfer() external onlyOwner {
        AllocationStorage storage s = _getStorage();
        if (s.pendingOwner == address(0)) revert Unauthorized();

        address canceledPendingOwner = s.pendingOwner;
        s.pendingOwner = address(0);
        emit OwnershipTransferCanceled(s.owner, canceledPendingOwner);
    }

    /// @notice Update keeper address
    function setKeeper(address newKeeper) external onlyOwner {
        if (newKeeper == address(0)) revert Unauthorized();
        AllocationStorage storage s = _getStorage();
        address oldKeeper = s.keeper;
        s.keeper = newKeeper;
        emit KeeperUpdated(oldKeeper, newKeeper);
    }

    /// @notice Update management address
    function setManagement(address newManagement) external onlyOwner {
        if (newManagement == address(0)) revert Unauthorized();
        AllocationStorage storage s = _getStorage();
        address oldManagement = s.management;
        s.management = newManagement;
        emit ManagementUpdated(oldManagement, newManagement);
    }

    /// @notice Update emergency admin address
    function setEmergencyAdmin(address newEmergencyAdmin) external onlyOwner {
        if (newEmergencyAdmin == address(0)) revert Unauthorized();
        AllocationStorage storage s = _getStorage();
        address oldEmergencyAdmin = s.emergencyAdmin;
        s.emergencyAdmin = newEmergencyAdmin;
        emit EmergencyAdminUpdated(oldEmergencyAdmin, newEmergencyAdmin);
    }

    /// @notice Emergency pause all operations
    function pause() external onlyOwner {
        AllocationStorage storage s = _getStorage();
        s.paused = true;
        emit PausedStatusChanged(true);
    }

    /// @notice Resume operations after pause
    function unpause() external onlyOwner {
        AllocationStorage storage s = _getStorage();
        s.paused = false;
        emit PausedStatusChanged(false);
    }

    /// @notice Check if contract is paused
    function paused() external view returns (bool) {
        return _getStorage().paused;
    }

    /// @notice Sweep remaining tokens after grace period expires
    /// @dev Can only be called by owner after global grace period ends
    /// @param token The token to sweep (use address(0) for ETH)
    /// @param receiver The address to receive the swept tokens
    function sweep(address token, address receiver) external onlyOwner nonReentrant {
        AllocationStorage storage s = _getStorage();

        // Ensure grace period has expired for everyone
        require(s.globalRedemptionStart != 0, "Redemption period not started");
        require(block.timestamp > s.globalRedemptionEndTime, "Grace period not expired");
        require(receiver != address(0), "Invalid receiver");

        if (token == address(0)) {
            // Sweep ETH
            uint256 balance = address(this).balance;
            require(balance > 0, "No ETH to sweep");
            (bool success, ) = receiver.call{ value: balance }("");
            require(success, "ETH transfer failed");
            emit Swept(token, receiver, balance);
        } else {
            // Sweep any ERC20 token
            IERC20 tokenContract = IERC20(token);
            uint256 balance = tokenContract.balanceOf(address(this));
            require(balance > 0, "No tokens to sweep");
            tokenContract.safeTransfer(receiver, balance);
            emit Swept(token, receiver, balance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ALLOCATION VAULT FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Redeems exactly `shares` from `shareOwner` and
     * sends `assets` of underlying tokens to `receiver`.
     * @param shares The amount of shares burnt.
     * @param receiver The address to receive `assets`.
     * @param shareOwner The address whose shares are burnt.
     * @return . The actual amount of underlying withdrawn.
     */
    function redeem(uint256 shares, address receiver, address shareOwner) external nonReentrant returns (uint256) {
        // Get the storage slot for all following calls.
        AllocationStorage storage S = _getStorage();
        require(shares <= _maxRedeem(S, shareOwner), "Allocation: redeem more than max");
        // slither-disable-next-line uninitialized-local
        uint256 assets;
        // Check for rounding error or 0 value.
        require((assets = _convertToAssets(S, shares, Math.Rounding.Floor)) != 0, "ZERO_ASSETS");

        // We need to return the actual amount withdrawn.
        return _withdraw(S, receiver, shareOwner, assets, shares);
    }

    /**
     * @notice Get the total amount of assets this strategy holds
     * as of the last report.
     *
     * We manually track `totalAssets` to avoid any PPS manipulation.
     *
     * @return . Total assets the strategy holds.
     */
    function totalAssets() external view returns (uint256) {
        return _totalAssets(_getStorage());
    }

    /**
     * @notice Get the current supply of the strategies shares.
     *
     * Locked shares issued to the strategy from profits are not
     * counted towards the full supply until they are unlocked.
     *
     * As more shares slowly unlock the totalSupply will decrease
     * causing the PPS of the strategy to increase.
     *
     * @return . Total amount of shares outstanding.
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply(_getStorage());
    }

    /**
     * @notice The amount of shares that the strategy would
     *  exchange for the amount of assets provided, in an
     * ideal scenario where all the conditions are met.
     *
     * @param assets The amount of underlying.
     * @return . Expected shares that `assets` represents.
     */
    function convertToShares(uint256 assets) external view returns (uint256) {
        return _convertToShares(_getStorage(), assets, Math.Rounding.Floor);
    }

    /**
     * @notice The amount of assets that the strategy would
     * exchange for the amount of shares provided, in an
     * ideal scenario where all the conditions are met.
     *
     * @param shares The amount of the strategies shares.
     * @return . Expected amount of `asset` the shares represents.
     */
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _convertToAssets(_getStorage(), shares, Math.Rounding.Floor);
    }

    /**
     * @notice Allows an on-chain or off-chain user to simulate
     * the effects of their redemption at the current block,
     * given current on-chain conditions.
     * @dev This will round down.
     *
     * @param shares The amount of shares that would be redeemed.
     * @return . The amount of `asset` that would be returned.
     */
    function previewRedeem(uint256 shares) external view returns (uint256) {
        AllocationStorage storage s = _getStorage();

        // Return 0 if outside redemption period [t_r_start, t_r_end]
        if (s.globalRedemptionStart == 0 || block.timestamp < s.globalRedemptionStart) {
            return 0; // Before redemption period starts
        }

        if (s.globalRedemptionEndTime != 0 && block.timestamp > s.globalRedemptionEndTime) {
            return 0; // After redemption period ends
        }

        return _convertToAssets(s, shares, Math.Rounding.Floor);
    }

    /**
     * @notice Total number of strategy shares that can be
     * redeemed from the strategy by `shareOwner`, where `shareOwner`
     * corresponds to the msg.sender of a {redeem} call.
     *
     * @param shareOwner The owner of the shares.
     * @return _maxRedeem Max amount of shares that can be redeemed.
     */
    function maxRedeem(address shareOwner) external view returns (uint256) {
        return _maxRedeem(_getStorage(), shareOwner);
    }

    // Additional getters for vault functionality
    function management() external view returns (address) {
        return _getStorage().management;
    }

    function keeper() external view returns (address) {
        return _getStorage().keeper;
    }

    function emergencyAdmin() external view returns (address) {
        return _getStorage().emergencyAdmin;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf(_getStorage(), account);
    }

    function allowance(address tokenOwner, address spender) external view returns (uint256) {
        return _allowance(_getStorage(), tokenOwner, spender);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL VAULT VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal implementation of {totalAssets}.
    function _totalAssets(AllocationStorage storage S) internal view returns (uint256) {
        return S.totalAssets;
    }

    /// @dev Internal implementation of {totalSupply}.
    function _totalSupply(AllocationStorage storage S) internal view returns (uint256) {
        return S.totalSupply;
    }

    /// @dev Internal implementation of {convertToShares}.
    function _convertToShares(
        AllocationStorage storage S,
        uint256 assets,
        Math.Rounding _rounding
    ) internal view returns (uint256) {
        // Saves an extra SLOAD if values are non-zero.
        uint256 totalSupply_ = _totalSupply(S);
        // If supply is 0, convert assets from asset decimals to 18 decimals (share decimals)
        if (totalSupply_ == 0) {
            uint8 assetDecimals = S.decimals;
            if (assetDecimals == 18) {
                return assets;
            } else if (assetDecimals < 18) {
                // Scale up: multiply by 10^(18 - assetDecimals)
                uint256 scaleFactor = 10 ** (18 - assetDecimals);
                return assets * scaleFactor;
            } else {
                // Scale down: divide by 10^(assetDecimals - 18)
                uint256 scaleFactor = 10 ** (assetDecimals - 18);
                return assets / scaleFactor;
            }
        }

        uint256 totalAssets_ = _totalAssets(S);
        // If assets are 0 but supply is not PPS = 0.
        if (totalAssets_ == 0) return 0;

        return assets.mulDiv(totalSupply_, totalAssets_, _rounding);
    }

    /// @dev Internal implementation of {convertToAssets}.
    function _convertToAssets(
        AllocationStorage storage S,
        uint256 shares,
        Math.Rounding _rounding
    ) internal view returns (uint256) {
        // Saves an extra SLOAD if totalSupply() is non-zero.
        uint256 supply = _totalSupply(S);

        if (supply == 0) {
            // Convert shares from 18 decimals to asset decimals
            uint8 assetDecimals = S.decimals;
            if (assetDecimals == 18) {
                return shares;
            } else if (assetDecimals < 18) {
                // Scale down: divide by 10^(18 - assetDecimals)
                uint256 scaleFactor = 10 ** (18 - assetDecimals);
                return shares / scaleFactor;
            } else {
                // Scale up: multiply by 10^(assetDecimals - 18)
                uint256 scaleFactor = 10 ** (assetDecimals - 18);
                return shares * scaleFactor;
            }
        }

        return shares.mulDiv(_totalAssets(S), supply, _rounding);
    }

    /// @dev Internal implementation of {maxRedeem}.
    function _maxRedeem(AllocationStorage storage S, address shareOwner) internal view returns (uint256 maxRedeem_) {
        // Get the max the owner could withdraw currently.
        maxRedeem_ = IBaseAllocationStrategy(address(this)).availableWithdrawLimit(shareOwner);

        // Conversion would overflow and saves a min check if there is no withdrawal limit.
        if (maxRedeem_ == type(uint256).max) {
            maxRedeem_ = _balanceOf(S, shareOwner);
        } else {
            maxRedeem_ = Math.min(
                // Can't redeem more than the balance.
                _convertToShares(S, maxRedeem_, Math.Rounding.Floor),
                _balanceOf(S, shareOwner)
            );
        }
    }

    /// @dev Internal implementation of {balanceOf}.
    function _balanceOf(AllocationStorage storage S, address account) internal view returns (uint256) {
        return S.balances[account];
    }

    /// @dev Internal implementation of {allowance}.
    function _allowance(
        AllocationStorage storage S,
        address tokenOwner,
        address spender
    ) internal view returns (uint256) {
        return S.allowances[tokenOwner][spender];
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL VAULT WRITE METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev To be called during {redeem} and {withdraw}.
     *
     * This will handle all logic, transfers and accounting
     * in order to service the withdraw request.
     */
    function _withdraw(
        AllocationStorage storage S,
        address receiver,
        address shareOwner,
        uint256 assets,
        uint256 shares
    ) internal returns (uint256) {
        require(receiver != address(0), "ZERO ADDRESS");

        // Spend allowance if applicable.
        if (msg.sender != shareOwner) {
            _spendAllowance(S, shareOwner, msg.sender, shares);
        }

        // Cache `asset` since it is used multiple times..
        ERC20 _asset = ERC20(address(S.asset));

        // Ensure sufficient balance for withdrawal
        uint256 idle = _asset.balanceOf(address(this));
        require(idle >= assets, "Insufficient balance for withdrawal");

        // Update assets based on how much we took.
        S.totalAssets -= assets;

        _burn(S, shareOwner, shares);

        // Transfer the amount of underlying to the receiver.
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, shareOwner, assets, shares);

        // Return the actual amount of assets withdrawn.
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer '_amount` of shares from `msg.sender` to `to`.
     * @dev
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `to` cannot be the address of the strategy.
     * - the caller must have a balance of at least `_amount`.
     *
     * @param to The address shares will be transferred to.
     * @param amount The amount of shares to be transferred from sender.
     * @return . a boolean value indicating whether the operation succeeded.
     */
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(_getStorage(), msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Sets `amount` as the allowance of `spender` over the caller's tokens.
     * @dev
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     *
     * @param spender the address to allow the shares to be moved by.
     * @param amount the amount of shares to allow `spender` to move.
     * @return . a boolean value indicating whether the operation succeeded.
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_getStorage(), msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * @dev
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `to` cannot be the address of the strategy.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     *
     * Emits a {Transfer} event.
     *
     * @param from the address to be moving shares from.
     * @param to the address to be moving shares to.
     * @param amount the quantity of shares to move.
     * @return . a boolean value indicating whether the operation succeeded.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        AllocationStorage storage S = _getStorage();
        _spendAllowance(S, from, msg.sender, amount);
        _transfer(S, from, to, amount);
        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `to` cannot be the strategies address
     * - `from` must have a balance of at least `amount`.
     *
     */
    function _transfer(AllocationStorage storage S, address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(to != address(this), "ERC20 transfer to strategy");

        // Only allow transfers during redemption period [globalRedemptionStart, globalRedemptionEndTime]
        // Before finalization: globalRedemptionEndTime is 0, so block.timestamp > 0 blocks transfers
        // After finalization: both timestamps are set, creating the valid redemption window
        if (block.timestamp < S.globalRedemptionStart || block.timestamp > S.globalRedemptionEndTime) {
            revert("Transfers only allowed during redemption period");
        }

        S.balances[from] -= amount;
        unchecked {
            S.balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     *
     */
    function _mint(AllocationStorage storage S, address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        S.totalSupply += amount;
        unchecked {
            S.balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(AllocationStorage storage S, address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        S.balances[account] -= amount;
        unchecked {
            S.totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(AllocationStorage storage S, address tokenOwner, address spender, uint256 amount) internal {
        require(tokenOwner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        S.allowances[tokenOwner][spender] = amount;
        emit Approval(tokenOwner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        AllocationStorage storage S,
        address tokenOwner,
        address spender,
        uint256 amount
    ) internal {
        uint256 currentAllowance = _allowance(S, tokenOwner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(S, tokenOwner, spender, currentAllowance - amount);
            }
        }
    }
}
