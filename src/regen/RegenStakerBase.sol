// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// OpenZeppelin Imports
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

// Staker Library Imports
import { Staker, DelegationSurrogate, SafeCast, SafeERC20, IERC20 } from "staker/Staker.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { StakerPermitAndStake } from "staker/extensions/StakerPermitAndStake.sol";

// Local Imports
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { OctantQFMechanism } from "src/mechanisms/mechanism/OctantQFMechanism.sol";
import { AccessMode } from "src/constants.sol";
import { NotInAllowset } from "src/errors.sol";

// === Contract Header ===
/// @title RegenStakerBase
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Base contract for RegenStaker variants, extending the Staker contract by [ScopeLift](https://scopelift.co).
/// @notice Provides shared functionality including:
///         - Variable reward duration (7-3000 days, configurable by admin)
///         - Earning power management with external bumping incentivized by tips (up to maxBumpTip)
///         - Adjustable minimum stake amount (existing deposits grandfathered with restrictions)
///         - Access control for stakers and allocation mechanisms
///         - Reward compounding (when REWARD_TOKEN == STAKE_TOKEN)
///         - Reward contribution to approved allocation mechanisms
///         - Admin controls (pause/unpause, config updates)
///
/// @dev CLAIMER PERMISSION MODEL:
///      Claimers are trusted entities designated by deposit owners with specific permissions:
///
///      Permission Matrix:
///      ┌─────────────────────────┬──────────┬─────────┐
///      │ Operation               │ Owner    │ Claimer │
///      ├─────────────────────────┼──────────┼─────────┤
///      │ Claim rewards           │ ✓        │ ✓       │
///      │ Compound rewards*†      │ ✓        │ ✓       │
///      │ Contribute to public‡   │ ✓        │ ✓       │
///      │ Stake more              │ ✓        │ ✗       │
///      │ Withdraw                │ ✓        │ ✗       │
///      │ Alter delegatee         │ ✓        │ ✗       │
///      │ Alter claimer           │ ✓        │ ✗       │
///      └─────────────────────────┴──────────┴─────────┘
///      * Compounding increases deposit stake (intended behavior)
///      † Compounding requires deposit owner to pass stakerAccessMode checks (allowset/blockset enforcement)
///      ‡ Mechanism must be on allocationMechanismAllowset; contributor checked via mechanism's contributionAllowset
///      § VOTING POWER: The contributor (msg.sender) receives voting power in the allocation mechanism,
///         NOT the deposit owner. When a claimer contributes, the claimer gets voting power.
///
///      When designating a claimer, owners explicitly trust them with:
///      1. Claiming accrued rewards on their behalf
///      2. Compounding rewards to increase stake position (when REWARD_TOKEN == STAKE_TOKEN)
///      3. Contributing unclaimed rewards to approved allocation mechanisms
///      4. Receiving voting power in allocation mechanisms when they contribute (claimer gets voting power, not owner)
///
///      Security boundaries are maintained:
///      - Claimers cannot withdraw principal or rewards to arbitrary addresses
///      - Claimers cannot modify deposit parameters
///      - Owners can revoke claimer designation at any time via alterClaimer()
///
/// @notice Token requirements: STAKE_TOKEN and REWARD_TOKEN must be standard ERC-20 tokens.
///         Unsupported token behaviors include fee-on-transfer/deflationary mechanisms, rebasing,
///         or non-standard return values. Accounting assumes transferred amount equals requested
///         amount; non-standard tokens can break deposits, withdrawals, or reward accounting.
/// @dev Integer division causes ~1 wei precision loss, negligible due to SCALE_FACTOR (1e36).
/// @dev This base is abstract, with variants implementing token-specific behaviors (e.g., delegation surrogates).
/// @dev Earning power updates are required after balance changes; some are automatic, others via bumpEarningPower.
abstract contract RegenStakerBase is Staker, Pausable, ReentrancyGuard, EIP712, StakerPermitAndStake, StakerOnBehalf {
    using SafeCast for uint256;

    // === Enums ===

    // === Structs ===
    /// @notice Struct to hold shared configuration state
    /// @dev Groups related configuration variables for better storage efficiency and easier inheritance.
    struct SharedState {
        uint128 rewardDuration;
        uint128 minimumStakeAmount;
        IAddressSet stakerAllowset;
        IAddressSet allocationMechanismAllowset;
        IAddressSet stakerBlockset;
        AccessMode stakerAccessMode;
    }

    // === Constants ===
    /// @notice Minimum allowed reward duration in seconds (7 days).
    uint256 public constant MIN_REWARD_DURATION = 7 days;

    /// @notice Maximum allowed reward duration to prevent excessively long reward periods.
    uint256 public constant MAX_REWARD_DURATION = 3000 days;

    // === Custom Errors ===
    /// @notice Error thrown when staker is not in allowset
    /// @param user The user address
    error StakerNotAllowed(address user);

    /// @notice Error thrown when staker is blocked
    /// @param user The user address
    error StakerBlocked(address user);

    /// @notice Error thrown when deposit owner is not eligible for the target mechanism
    /// @param mechanism The allocation mechanism address
    /// @param owner The deposit owner address
    error DepositOwnerNotEligibleForMechanism(address mechanism, address owner);

    /// @notice Error thrown when reward notification would corrupt user deposits (same-token scenario)
    /// @param currentBalance The actual token balance in the contract
    /// @param required The minimum balance needed (totalStaked + reward amount)
    error InsufficientRewardBalance(uint256 currentBalance, uint256 required);

    /// @notice Error thrown when requested amount exceeds available
    /// @param requested The requested amount
    /// @param available The available amount
    error CantAfford(uint256 requested, uint256 available);

    /// @notice Error thrown when stake amount is below minimum
    /// @param expected The minimum required
    /// @param actual The actual amount
    error MinimumStakeAmountNotMet(uint256 expected, uint256 actual);

    /// @notice Error thrown for invalid reward duration
    /// @param rewardDuration The invalid duration
    error InvalidRewardDuration(uint256 rewardDuration);

    /// @notice Error thrown when attempting to change duration during active reward
    error CannotChangeRewardDurationDuringActiveReward();

    /// @notice Error thrown when compounding is not supported
    error CompoundingNotSupported();

    /// @notice Error thrown when raising minimum stake amount during active reward
    error CannotRaiseMinimumStakeAmountDuringActiveReward();

    /// @notice Error thrown when attempting to increase max bump tip during active reward
    error CannotRaiseMaxBumpTipDuringActiveReward();

    /// @notice Error thrown for zero amount operations
    error ZeroOperation();

    /// @notice Error thrown when no change is made
    error NoOperation();

    /// @notice Error thrown when attempting to disable allocation mechanism allowset
    error DisablingAllocationMechanismWhitelistNotAllowed();

    /// @notice Error thrown when reward token doesn't match allocation mechanism's expected asset
    /// @param expected The expected token (REWARD_TOKEN)
    /// @param actual The actual token expected by the allocation mechanism
    error AssetMismatch(address expected, address actual);

    // === State Variables ===
    /// @notice Shared configuration state instance
    /// @dev Internal storage for shared configuration accessible via getters.
    SharedState internal sharedState;

    /// @notice Tracks the total amount of rewards that have been added via notifyRewardAmount
    /// @dev This accumulates all reward amounts ever added to the contract
    uint256 public totalRewards;

    /// @notice Tracks the total amount of rewards that have been consumed by users
    /// @dev This includes claims, compounding, contributions, and tips
    uint256 public totalClaimedRewards;

    /// @notice Summary of the most recently scheduled reward cycle.
    /// @dev Tracks both the new amount and any carried-over rewards for analytics and UX.
    struct RewardSchedule {
        uint256 addedAmount;
        uint256 carryOverAmount;
        uint256 totalScheduledAmount;
        uint256 requiredBalance;
        uint256 duration;
        uint256 endTime;
    }

    /// @notice Cached metadata for the most recent reward schedule.
    RewardSchedule public latestRewardSchedule;

    // === Events ===
    /// @notice Emitted when the staker allowset is updated
    /// @param allowset The new allowset contract address
    event StakerAllowsetAssigned(IAddressSet indexed allowset);

    /// @notice Emitted when the staker blockset is updated
    /// @param blockset The new blockset contract address
    event StakerBlocksetAssigned(IAddressSet indexed blockset);

    /// @notice Emitted when staker access mode is changed
    /// @param mode The new access mode
    event AccessModeSet(AccessMode indexed mode);

    /// @notice Emitted when the allocation mechanism allowset is updated
    /// @param allowset The new allowset contract address
    event AllocationMechanismAllowsetAssigned(IAddressSet indexed allowset);

    /// @notice Emitted when the reward duration is updated
    /// @param newDuration The new reward duration in seconds
    event RewardDurationSet(uint256 newDuration);

    /// @notice Emitted when a new reward schedule is created or updated.
    /// @param addedAmount Newly supplied reward amount for this cycle
    /// @param carryOverAmount Unclaimed rewards carried over into the new cycle
    /// @param totalScheduledAmount Total rewards scheduled for distribution this cycle
    /// @param requiredBalance Total balance the contract must hold after notification
    /// @param duration Duration over which the rewards will stream
    /// @param endTime Timestamp when the reward cycle is scheduled to end
    event RewardScheduleUpdated(
        uint256 addedAmount,
        uint256 carryOverAmount,
        uint256 totalScheduledAmount,
        uint256 requiredBalance,
        uint256 duration,
        uint256 endTime
    );

    /// @notice Emitted when rewards are contributed to an allocation mechanism
    /// @param depositId The deposit identifier
    /// @param contributor The contributor's address
    /// @param fundingRound The allocation mechanism address
    /// @param amount The amount contributed
    event RewardContributed(
        DepositIdentifier indexed depositId,
        address indexed contributor,
        address indexed fundingRound,
        uint256 amount
    );

    /// @notice Error thrown when a required surrogate is missing
    /// @param delegatee The delegatee for which a surrogate was expected
    error SurrogateNotFound(address delegatee);

    /// @notice Emitted when the minimum stake amount is updated
    /// @param newMinimumStakeAmount The new minimum stake amount
    event MinimumStakeAmountSet(uint256 newMinimumStakeAmount);

    // === Getters ===
    /// @notice Gets the current reward duration
    /// @return The reward duration in seconds
    function rewardDuration() external view returns (uint256) {
        return sharedState.rewardDuration;
    }

    /// @notice Gets the staker allowset
    /// @return The staker allowset contract
    function stakerAllowset() external view returns (IAddressSet) {
        return sharedState.stakerAllowset;
    }

    /// @notice Gets the staker blockset
    /// @return The staker blockset contract
    function stakerBlockset() external view returns (IAddressSet) {
        return sharedState.stakerBlockset;
    }

    /// @notice Gets the staker access mode
    /// @return The current access mode
    function stakerAccessMode() external view returns (AccessMode) {
        return sharedState.stakerAccessMode;
    }

    /// @notice Gets the allocation mechanism allowset
    /// @return The allocation mechanism allowset contract
    function allocationMechanismAllowset() external view returns (IAddressSet) {
        return sharedState.allocationMechanismAllowset;
    }

    /// @notice Gets the minimum stake amount
    /// @return The minimum stake amount in wei
    function minimumStakeAmount() external view returns (uint256) {
        return sharedState.minimumStakeAmount;
    }

    // === Constructor ===
    /// @notice Constructor for RegenStakerBase
    /// @dev Initializes Staker, extensions, and shared state
    /// @param _rewardsToken The rewards token
    /// @param _stakeToken The stake token (must support IERC20Permit)
    /// @param _earningPowerCalculator The earning power calculator
    /// @param _maxBumpTip The max bump tip
    /// @param _admin The admin address
    /// @param _rewardDuration The reward duration
    /// @param _minimumStakeAmount The min stake amount
    /// @param _stakerAllowset Staker allowset (for ALLOWSET mode)
    /// @param _stakerBlockset Staker blockset (for BLOCKSET mode)
    /// @param _stakerAccessMode Initial staker access mode
    /// @param _allocationMechanismAllowset Allocation mechanism allowset (cannot be address(0))
    /// @param _eip712Name The EIP712 domain name
    constructor(
        IERC20 _rewardsToken,
        IERC20 _stakeToken,
        IEarningPowerCalculator _earningPowerCalculator,
        uint256 _maxBumpTip,
        address _admin,
        uint128 _rewardDuration,
        uint128 _minimumStakeAmount,
        IAddressSet _stakerAllowset,
        IAddressSet _stakerBlockset,
        AccessMode _stakerAccessMode,
        IAddressSet _allocationMechanismAllowset,
        string memory _eip712Name
    )
        Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
        StakerPermitAndStake(IERC20Permit(address(_stakeToken)))
        EIP712(_eip712Name, "1")
    {
        // Fee collection has been eliminated - set MAX_CLAIM_FEE to 0 to disable fees permanently
        MAX_CLAIM_FEE = 0;
        // Explicitly initialize claimFeeParameters to zero state for clarity
        claimFeeParameters = ClaimFeeParameters({ feeAmount: 0, feeCollector: address(0) });

        // Enable self-transfers for compound operations when stake and reward tokens are the same
        // This allows compoundRewards to use _stakeTokenSafeTransferFrom with address(this) as source
        if (address(STAKE_TOKEN) == address(REWARD_TOKEN)) {
            SafeERC20.safeIncreaseAllowance(STAKE_TOKEN, address(this), type(uint256).max);
        }

        // Initialize shared state
        _initializeSharedState(
            _rewardDuration,
            _minimumStakeAmount,
            _stakerAllowset,
            _stakerBlockset,
            _stakerAccessMode,
            _allocationMechanismAllowset
        );
    }

    // === Internal Functions ===
    /// @notice Initialize shared state with validation
    /// @dev Called by child constructors to set up shared configuration
    /// @param _rewardDuration The duration over which rewards are distributed
    /// @param _minimumStakeAmount The minimum stake amount
    /// @param _stakerAllowset The allowset for stakers (ALLOWSET mode)
    /// @param _stakerBlockset The blockset for stakers (BLOCKSET mode)
    /// @param _stakerAccessMode The initial staker access mode
    /// @param _allocationMechanismAllowset The allowset for allocation mechanisms
    function _initializeSharedState(
        uint128 _rewardDuration,
        uint128 _minimumStakeAmount,
        IAddressSet _stakerAllowset,
        IAddressSet _stakerBlockset,
        AccessMode _stakerAccessMode,
        IAddressSet _allocationMechanismAllowset
    ) internal {
        require(
            _rewardDuration >= MIN_REWARD_DURATION && _rewardDuration <= MAX_REWARD_DURATION,
            InvalidRewardDuration(uint256(_rewardDuration))
        );
        // Align initialization invariants with setters: allocation mechanism allowset cannot be disabled
        require(address(_allocationMechanismAllowset) != address(0), DisablingAllocationMechanismWhitelistNotAllowed());
        // Sanity check: Allocation mechanism allowset must be distinct from staker address sets
        require(
            address(_allocationMechanismAllowset) != address(_stakerAllowset) &&
                address(_allocationMechanismAllowset) != address(_stakerBlockset),
            Staker__InvalidAddress()
        );

        // Emit events first to match setter ordering
        emit RewardDurationSet(_rewardDuration);
        emit MinimumStakeAmountSet(_minimumStakeAmount);
        emit StakerAllowsetAssigned(_stakerAllowset);
        emit StakerBlocksetAssigned(_stakerBlockset);
        emit AccessModeSet(_stakerAccessMode);
        emit AllocationMechanismAllowsetAssigned(_allocationMechanismAllowset);

        // Assign to storage after emits for consistency with setters
        sharedState.rewardDuration = _rewardDuration;
        sharedState.minimumStakeAmount = _minimumStakeAmount;
        sharedState.stakerAllowset = _stakerAllowset;
        sharedState.stakerBlockset = _stakerBlockset;
        sharedState.stakerAccessMode = _stakerAccessMode;
        sharedState.allocationMechanismAllowset = _allocationMechanismAllowset;
    }

    /// @notice Sets the reward duration for future reward notifications
    /// @dev GAS IMPLICATIONS: Shorter reward durations may result in higher gas costs for certain
    ///      operations due to more frequent reward rate calculations. Consider gas costs when
    ///      selecting reward durations.
    /// @dev Can only be called by admin and not during active reward period
    /// @param _rewardDuration New reward duration in seconds (7 days minimum, 3000 days maximum)
    function setRewardDuration(uint128 _rewardDuration) external {
        _revertIfNotAdmin();
        require(block.timestamp > rewardEndTime, CannotChangeRewardDurationDuringActiveReward());
        require(
            _rewardDuration >= MIN_REWARD_DURATION && _rewardDuration <= MAX_REWARD_DURATION,
            InvalidRewardDuration(uint256(_rewardDuration))
        );
        require(sharedState.rewardDuration != _rewardDuration, NoOperation());

        emit RewardDurationSet(_rewardDuration);
        sharedState.rewardDuration = _rewardDuration;
    }

    /// @notice Internal implementation of notifyRewardAmount using custom reward duration
    /// @dev Overrides the base Staker logic to use variable duration
    /// @dev Enforces monotonic reward property: totalRewards can only increase, never decrease.
    ///      Once rewards are notified and time has elapsed, those elapsed portions cannot be
    ///      clawed back. Admins can adjust future reward rates by notifying new amounts, but
    ///      the current schedule represents a commitment for its duration and typically won't
    ///      be changed mid-cycle.
    /// @param _amount The reward amount to notify
    /// @param _requiredBalance The required balance calculated by variant-specific validation
    function _notifyRewardAmountWithCustomDuration(uint256 _amount, uint256 _requiredBalance) internal {
        if (!isRewardNotifier[msg.sender]) revert Staker__Unauthorized("not notifier", msg.sender);

        rewardPerTokenAccumulatedCheckpoint = rewardPerTokenAccumulated();

        if (block.timestamp >= rewardEndTime) {
            // Scale to maintain precision across variable durations
            scaledRewardRate = (_amount * SCALE_FACTOR) / sharedState.rewardDuration;
        } else {
            uint256 _remainingReward = scaledRewardRate * (rewardEndTime - block.timestamp);
            // Scale to maintain precision across variable durations
            scaledRewardRate = (_remainingReward + _amount * SCALE_FACTOR) / sharedState.rewardDuration;
        }

        rewardEndTime = block.timestamp + sharedState.rewardDuration;
        lastCheckpointTime = block.timestamp;

        if (scaledRewardRate < SCALE_FACTOR) revert Staker__InvalidRewardRate();

        // Calculate reward schedule metadata before updating totalRewards
        uint256 carryOverAmount = totalRewards - totalClaimedRewards;
        uint256 totalScheduledAmount = carryOverAmount + _amount;

        // Track total rewards added
        totalRewards += _amount;

        emit RewardNotified(_amount, msg.sender);

        latestRewardSchedule = RewardSchedule({
            addedAmount: _amount,
            carryOverAmount: carryOverAmount,
            totalScheduledAmount: totalScheduledAmount,
            requiredBalance: _requiredBalance,
            duration: sharedState.rewardDuration,
            endTime: rewardEndTime
        });

        emit RewardScheduleUpdated(
            _amount,
            carryOverAmount,
            totalScheduledAmount,
            _requiredBalance,
            sharedState.rewardDuration,
            rewardEndTime
        );
    }

    /// @notice Sets the allowset for stakers (who can stake tokens)
    /// @dev OPERATIONAL IMPACT: Affects all stake and stakeMore operations immediately.
    /// @dev GRANDFATHERING: Existing stakers can continue operations regardless of new allowset.
    /// @dev Can only be called by admin
    /// @dev NOTE: Use setAccessMode(AccessMode.NONE) to disable access control, not address(0)
    /// @param _stakerAllowset New staker allowset contract
    function setStakerAllowset(IAddressSet _stakerAllowset) external {
        require(sharedState.stakerAllowset != _stakerAllowset, NoOperation());
        require(address(_stakerAllowset) != address(sharedState.allocationMechanismAllowset), Staker__InvalidAddress());
        _revertIfNotAdmin();
        emit StakerAllowsetAssigned(_stakerAllowset);
        sharedState.stakerAllowset = _stakerAllowset;
    }

    /// @notice Sets the staker blockset
    /// @dev OPERATIONAL IMPACT: Affects all stake operations immediately.
    /// @dev Can only be called by admin
    /// @dev NOTE: Use setAccessMode(AccessMode.NONE) to disable access control, not address(0)
    /// @param _stakerBlockset New staker blockset contract
    function setStakerBlockset(IAddressSet _stakerBlockset) external {
        _revertIfNotAdmin();
        require(sharedState.stakerBlockset != _stakerBlockset, NoOperation());
        require(address(_stakerBlockset) != address(sharedState.allocationMechanismAllowset), Staker__InvalidAddress());
        emit StakerBlocksetAssigned(_stakerBlockset);
        sharedState.stakerBlockset = _stakerBlockset;
    }

    /// @notice Sets the staker access mode
    /// @dev OPERATIONAL IMPACT: Changes which address set (allowset/blockset) is active
    /// @dev Can only be called by admin
    /// @param _mode New access mode (NONE, ALLOWSET, or BLOCKSET)
    function setAccessMode(AccessMode _mode) external {
        _revertIfNotAdmin();
        require(sharedState.stakerAccessMode != _mode, NoOperation());
        emit AccessModeSet(_mode);
        sharedState.stakerAccessMode = _mode;
    }

    /// @notice Sets the allowset for allocation mechanisms
    /// @dev SECURITY: Only add thoroughly audited allocation mechanisms to this allowset.
    ///      Users will contribute rewards to approved mechanisms and funds cannot be recovered
    ///      if sent to malicious or buggy implementations.
    /// @dev EVALUATION PROCESS: New mechanisms should undergo comprehensive security audit,
    ///      integration testing, and governance review before approval.
    /// @dev OPERATIONAL IMPACT: Changes affect all future contributions. Existing contributions
    ///      to previously approved mechanisms are not affected.
    /// @dev Can only be called by admin. Cannot set to address(0).
    /// @dev AUDIT NOTE: Changes require governance approval.
    /// @param _allocationMechanismAllowset New allowset contract (cannot be address(0))
    function setAllocationMechanismAllowset(IAddressSet _allocationMechanismAllowset) external {
        require(sharedState.allocationMechanismAllowset != _allocationMechanismAllowset, NoOperation());
        require(address(_allocationMechanismAllowset) != address(0), DisablingAllocationMechanismWhitelistNotAllowed());
        // Prevent footgun: allocation mechanism allowset must be distinct from staker address sets
        require(
            address(_allocationMechanismAllowset) != address(sharedState.stakerAllowset) &&
                address(_allocationMechanismAllowset) != address(sharedState.stakerBlockset),
            Staker__InvalidAddress()
        );
        _revertIfNotAdmin();
        emit AllocationMechanismAllowsetAssigned(_allocationMechanismAllowset);
        sharedState.allocationMechanismAllowset = _allocationMechanismAllowset;
    }

    /// @notice Sets the minimum stake amount
    /// @dev GRANDFATHERING: Existing deposits below new minimum remain valid but will be
    ///      restricted from partial withdrawals and stakeMore operations until brought above threshold.
    /// @dev TIMING RESTRICTION: Cannot raise minimum during active reward period for user protection.
    /// @dev OPERATIONAL IMPACT: Affects all new stakes immediately. Consider user communication before changes.
    /// @dev Can only be called by admin
    /// @param _minimumStakeAmount New minimum stake amount in wei (0 = no minimum)
    function setMinimumStakeAmount(uint128 _minimumStakeAmount) external {
        _revertIfNotAdmin();
        require(
            _minimumStakeAmount <= sharedState.minimumStakeAmount || block.timestamp > rewardEndTime,
            CannotRaiseMinimumStakeAmountDuringActiveReward()
        );
        emit MinimumStakeAmountSet(_minimumStakeAmount);
        sharedState.minimumStakeAmount = _minimumStakeAmount;
    }

    /// @notice Sets the maximum bump tip with governance protection
    /// @dev TIMING RESTRICTION: During active reward period only decreases are allowed; increases must wait until after rewardEndTime.
    /// @dev SECURITY: Prevents malicious admin from extracting unclaimed rewards via tip manipulation.
    /// @dev GOVERNANCE PROTECTION: Aligns with setMinimumStakeAmount protection for consistency.
    /// @dev Can only be called by admin and not during active reward period
    /// @param _newMaxBumpTip New maximum bump tip value in wei
    function setMaxBumpTip(uint256 _newMaxBumpTip) external virtual override {
        _revertIfNotAdmin();
        // Allow decreases anytime; increases only after reward period ends
        require(
            _newMaxBumpTip <= maxBumpTip || block.timestamp > rewardEndTime,
            CannotRaiseMaxBumpTipDuringActiveReward()
        );
        _setMaxBumpTip(_newMaxBumpTip);
    }

    /// @notice Pauses the contract, disabling all user operations except view functions
    /// @dev EMERGENCY USE: Intended for security incidents or critical maintenance.
    /// @dev SCOPE: Affects stake, withdraw, claim, contribute, and compound operations.
    /// @dev ADMIN ONLY: Only admin can pause. Use emergency procedures for urgent situations.
    function pause() external whenNotPaused {
        _revertIfNotAdmin();
        _pause();
    }

    /// @notice Unpauses the contract, re-enabling all user operations
    /// @dev RECOVERY: Use after resolving issues that required pause.
    /// @dev ADMIN ONLY: Only admin can unpause. Ensure all issues resolved before unpause.
    function unpause() external whenPaused {
        _revertIfNotAdmin();
        _unpause();
    }

    // === Public Functions ===
    /// @notice Contributes unclaimed rewards to a user-specified allocation mechanism
    /// @dev CONTRIBUTION RISK: Contributed funds are transferred to external allocation mechanisms
    ///      for public good causes. Malicious mechanisms may misappropriate funds for unintended
    ///      purposes rather than the stated public good cause.
    /// @dev TRUST MODEL: Allocation mechanisms must be approved by protocol governance.
    ///      Only contribute to mechanisms you trust, as the protocol cannot recover funds
    ///      sent to malicious or buggy allocation mechanisms.
    /// @dev VOTING POWER ASSIGNMENT: The contributor (msg.sender) receives voting power in the
    ///      allocation mechanism, NOT necessarily the deposit owner. When a claimer contributes
    ///      owner's rewards, the CLAIMER receives the voting power. This is intended behavior
    ///      as part of the claimer trust model.
    /// @dev SECURITY: This function first withdraws rewards to the contributor, then the contributor
    ///      must have pre-approved the allocation mechanism to pull the tokens.
    /// @dev SECURITY AUDIT: Ensure allocation mechanisms are immutable after approval.
    /// @dev AUTHZ: Authorized caller is the deposit owner or the designated claimer; the claimer acts
    ///      as the owner's agent for rewards. Contribution access control enforced by mechanism.
    /// @dev Requires contract not paused and uses reentrancy guard
    /// @param _depositId The deposit identifier to contribute from
    /// @param _allocationMechanismAddress Approved allocation mechanism to receive contribution
    /// @param _amount Amount of unclaimed rewards to contribute (must be <= available rewards)
    /// @param _deadline Signature expiration timestamp
    /// @param _v Signature component v
    /// @param _r Signature component r
    /// @param _s Signature component s
    /// @return amountContributedToAllocationMechanism Actual amount contributed
    function contribute(
        DepositIdentifier _depositId,
        address _allocationMechanismAddress,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public virtual whenNotPaused nonReentrant returns (uint256 amountContributedToAllocationMechanism) {
        _revertIfAddressZero(_allocationMechanismAddress);
        require(
            sharedState.allocationMechanismAllowset.contains(_allocationMechanismAddress),
            NotInAllowset(_allocationMechanismAddress)
        );

        // Validate asset compatibility to fail fast and provide clear error
        {
            address expectedAsset = address(TokenizedAllocationMechanism(_allocationMechanismAddress).asset());
            if (address(REWARD_TOKEN) != expectedAsset) {
                revert AssetMismatch(address(REWARD_TOKEN), expectedAsset);
            }
        }

        Deposit storage deposit = deposits[_depositId];
        if (deposit.claimer != msg.sender && deposit.owner != msg.sender) {
            revert Staker__Unauthorized("not claimer or owner", msg.sender);
        }

        // Defense-in-depth dual-check architecture (Cantina Finding #127 fix):
        // 1. TAM checks msg.sender (claimer/contributor) via beforeSignupHook - receives voting power
        // 2. RegenStaker checks deposit.owner (fund source) must also be eligible (defense-in-depth)
        // This prevents delisted owners from using allowlisted claimers as proxies
        //
        // IMPORTANT: Voting power goes to msg.sender (claimer), NOT deposit.owner
        // Per documented permission model (see lines 56-64), the contributor (msg.sender) receives
        // voting power, preserving claimer autonomy. The owner check here is an additional security
        // layer to ensure fund sources are also eligible, closing the bypass vector identified in
        // Cantina Finding #127 where delisted owners could use allowlisted claimers as proxies.

        // Explicit fund source check: Verify deposit owner is also eligible for this mechanism
        // Assumes mechanism implements canSignup() (OctantQFMechanism interface)
        bool ownerCanSignup = OctantQFMechanism(payable(_allocationMechanismAddress)).canSignup(deposit.owner);
        if (!ownerCanSignup) {
            revert DepositOwnerNotEligibleForMechanism(_allocationMechanismAddress, deposit.owner);
        }

        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 unclaimedAmount = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;
        require(_amount <= unclaimedAmount, CantAfford(_amount, unclaimedAmount));

        // Special case: Allow zero-amount contributions to enable users to register for voting
        // without contributing funds. This is useful for participation-only scenarios where
        // users want to signal support without financial commitment.
        if (_amount == 0) {
            emit RewardContributed(_depositId, msg.sender, _allocationMechanismAddress, 0);
            TokenizedAllocationMechanism(_allocationMechanismAddress).signupOnBehalfWithSignature(
                msg.sender, // Claimer/contributor receives voting power and provides signature
                0,
                _deadline,
                _v,
                _r,
                _s
            );
            return 0;
        }

        amountContributedToAllocationMechanism = _amount;
        _consumeRewards(deposit, _amount);

        // Defensive earning power update - maintaining consistency with base Staker pattern
        uint256 _oldEarningPower = deposit.earningPower;
        uint256 _newEarningPower = earningPowerCalculator.getEarningPower(
            deposit.balance,
            deposit.owner,
            deposit.delegatee
        );

        // Update earning power totals before modifying deposit state
        totalEarningPower = _calculateTotalEarningPower(_oldEarningPower, _newEarningPower, totalEarningPower);
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            _oldEarningPower,
            _newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );
        deposit.earningPower = _newEarningPower.toUint96();

        emit RewardClaimed(_depositId, msg.sender, amountContributedToAllocationMechanism, _newEarningPower);

        // approve the allocation mechanism to spend the rewards
        SafeERC20.safeIncreaseAllowance(
            REWARD_TOKEN,
            _allocationMechanismAddress,
            amountContributedToAllocationMechanism
        );

        emit RewardContributed(
            _depositId,
            msg.sender,
            _allocationMechanismAddress,
            amountContributedToAllocationMechanism
        );

        TokenizedAllocationMechanism(_allocationMechanismAddress).signupOnBehalfWithSignature(
            msg.sender, // Claimer/contributor receives voting power and provides signature
            amountContributedToAllocationMechanism,
            _deadline,
            _v,
            _r,
            _s
        );

        // check that allowance is zero
        require(REWARD_TOKEN.allowance(address(this), _allocationMechanismAddress) == 0, "allowance not zero");

        return amountContributedToAllocationMechanism;
    }

    /// @notice Compounds rewards by claiming them and immediately restaking them into the same deposit
    /// @dev REQUIREMENT: Only works when REWARD_TOKEN == STAKE_TOKEN, otherwise reverts.
    /// @dev EARNING POWER: Compounding updates earning power based on new total balance.
    /// @dev GAS OPTIMIZATION: More efficient than separate claim + stake operations.
    /// @dev CLAIMER PERMISSIONS: This function grants claimers the ability to increase deposit stakes
    ///      through compounding. This is INTENDED BEHAVIOR - when an owner designates a claimer, they
    ///      explicitly trust them with both reward claiming AND limited staking operations (compounding).
    ///      Claimers cannot withdraw funds or alter deposit parameters, maintaining security boundaries.
    /// @dev Requires contract not paused and uses reentrancy guard
    /// @param _depositId The deposit to compound rewards for
    /// @return compoundedAmount Amount of rewards compounded
    function compoundRewards(
        DepositIdentifier _depositId
    ) external virtual whenNotPaused nonReentrant returns (uint256 compoundedAmount) {
        if (address(REWARD_TOKEN) != address(STAKE_TOKEN)) {
            revert CompoundingNotSupported();
        }

        Deposit storage deposit = deposits[_depositId];
        address depositOwner = deposit.owner;

        if (deposit.claimer != msg.sender && depositOwner != msg.sender) {
            revert Staker__Unauthorized("not claimer or owner", msg.sender);
        }

        _checkStakerAccess(depositOwner);

        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 unclaimedAmount = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;
        if (unclaimedAmount == 0) {
            return 0;
        }

        compoundedAmount = unclaimedAmount;

        uint256 tempEarningPower = earningPowerCalculator.getEarningPower(
            deposit.balance,
            deposit.owner,
            deposit.delegatee
        );

        uint256 newBalance = deposit.balance + compoundedAmount;
        uint256 oldEarningPower = deposit.earningPower; // Save old earning power for event
        uint256 newEarningPower = earningPowerCalculator.getEarningPower(newBalance, deposit.owner, deposit.delegatee);

        totalEarningPower = _calculateTotalEarningPower(oldEarningPower, newEarningPower, totalEarningPower);
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            oldEarningPower,
            newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );

        totalStaked += compoundedAmount;
        depositorTotalStaked[depositOwner] += compoundedAmount;

        _consumeRewards(deposit, unclaimedAmount);

        deposit.balance = newBalance.toUint96();
        deposit.earningPower = newEarningPower.toUint96();

        // Transfer compounded rewards using the same pattern as _stakeMore for consistency
        // The surrogate must already exist since the deposit exists (created during initial stake)
        // This ensures child contracts can customize behavior through _stakeTokenSafeTransferFrom
        DelegationSurrogate _surrogate = surrogates(deposit.delegatee);
        if (address(_surrogate) == address(0)) {
            revert SurrogateNotFound(deposit.delegatee);
        }
        _stakeTokenSafeTransferFrom(address(this), address(_surrogate), compoundedAmount);

        emit RewardClaimed(_depositId, msg.sender, compoundedAmount, tempEarningPower);
        emit StakeDeposited(depositOwner, _depositId, compoundedAmount, newBalance, newEarningPower);

        _revertIfMinimumStakeAmountNotMet(_depositId);

        return compoundedAmount;
    }

    /// @notice Internal helper to check minimum stake amount
    /// @dev Reverts if balance is below minimum and not zero
    /// @param _depositId The deposit to check
    function _revertIfMinimumStakeAmountNotMet(DepositIdentifier _depositId) internal view {
        Deposit storage deposit = deposits[_depositId];
        if (deposit.balance < sharedState.minimumStakeAmount && deposit.balance > 0) {
            revert MinimumStakeAmountNotMet(sharedState.minimumStakeAmount, deposit.balance);
        }
    }

    function _checkStakerAccess(address user) internal view {
        if (sharedState.stakerAccessMode == AccessMode.ALLOWSET) {
            if (!sharedState.stakerAllowset.contains(user)) {
                revert StakerNotAllowed(user);
            }
        } else if (sharedState.stakerAccessMode == AccessMode.BLOCKSET) {
            if (sharedState.stakerBlockset.contains(user)) {
                revert StakerBlocked(user);
            }
        }
    }

    /// @notice Atomically updates deposit checkpoint and totalClaimedRewards
    /// @dev Ensures consistent state updates when rewards are consumed
    /// @param _deposit The deposit to update
    /// @param _amount The amount of rewards being claimed
    function _consumeRewards(Deposit storage _deposit, uint256 _amount) internal {
        if (_amount > 0) {
            uint256 scaledAmount = _amount * SCALE_FACTOR;
            _deposit.scaledUnclaimedRewardCheckpoint = _deposit.scaledUnclaimedRewardCheckpoint - scaledAmount;
            totalClaimedRewards = totalClaimedRewards + _amount;
        }
    }

    /// @inheritdoc Staker
    /// @notice Pauses reward streaming during idle windows (when `totalEarningPower == 0`) by
    ///         extending `rewardEndTime` by the idle duration; no rewards accrue while idle.
    /// @dev When earning power is non-zero, accrues `rewardPerTokenAccumulatedCheckpoint` as usual.
    function _checkpointGlobalReward() internal virtual override {
        uint256 lastDistributed = lastTimeRewardDistributed();
        uint256 elapsed = lastDistributed - lastCheckpointTime;

        if (elapsed > 0 && scaledRewardRate != 0) {
            if (totalEarningPower == 0) {
                rewardEndTime += elapsed;
            } else {
                rewardPerTokenAccumulatedCheckpoint += (scaledRewardRate * elapsed) / totalEarningPower;
            }
        }

        lastCheckpointTime = lastDistributed;
    }

    // === Overridden Functions ===

    /// @inheritdoc Staker
    /// @notice Prevents staking 0, staking below the minimum, staking when paused, and unauthorized staking.
    /// @dev Uses reentrancy guard
    /// @param _depositor The depositor address
    /// @param _amount The amount to stake
    /// @param _delegatee The delegatee address
    /// @param _claimer The claimer address
    /// @return _depositId The deposit identifier
    function _stake(
        address _depositor,
        uint256 _amount,
        address _delegatee,
        address _claimer
    ) internal virtual override whenNotPaused nonReentrant returns (DepositIdentifier _depositId) {
        require(_amount > 0, ZeroOperation());
        _checkStakerAccess(_depositor);
        _depositId = super._stake(_depositor, _amount, _delegatee, _claimer);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Prevents withdrawing 0; prevents withdrawals that drop balance below minimum; disabled when paused.
    /// @dev Uses reentrancy guard
    /// @param deposit The deposit storage
    /// @param _depositId The deposit identifier
    /// @param _amount The amount to withdraw
    function _withdraw(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        uint256 _amount
    ) internal virtual override whenNotPaused nonReentrant {
        require(_amount > 0, ZeroOperation());
        super._withdraw(deposit, _depositId, _amount);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to add reentrancy protection.
    /// @dev Uses reentrancy guard
    /// @param deposit The deposit storage
    /// @param _depositId The deposit identifier
    /// @param _newDelegatee The new delegatee
    function _alterDelegatee(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        address _newDelegatee
    ) internal virtual override whenNotPaused nonReentrant {
        super._alterDelegatee(deposit, _depositId, _newDelegatee);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to add reentrancy protection.
    /// @dev Uses reentrancy guard
    /// @param deposit The deposit storage
    /// @param _depositId The deposit identifier
    /// @param _newClaimer The new claimer
    function _alterClaimer(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        address _newClaimer
    ) internal virtual override whenNotPaused nonReentrant {
        super._alterClaimer(deposit, _depositId, _newClaimer);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to add pause protection and track totalClaimedRewards for balance validation
    /// @dev Reuses base Staker logic (with fee=0) and adds totalClaimedRewards tracking
    /// @dev nonReentrant protects against reentrancy despite updating totalClaimedRewards after transfer
    /// @param _depositId The deposit identifier
    /// @param deposit The deposit storage
    /// @param _claimer The claimer address
    /// @return The claimed amount
    function _claimReward(
        DepositIdentifier _depositId,
        Deposit storage deposit,
        address _claimer
    ) internal virtual override whenNotPaused nonReentrant returns (uint256) {
        uint256 _claimedAmount = super._claimReward(_depositId, deposit, _claimer);
        totalClaimedRewards += _claimedAmount;
        return _claimedAmount;
    }

    /// @notice Override notifyRewardAmount to use custom reward duration
    /// @dev nonReentrant as a belts-and-braces guard against exotic ERC20 callback reentry
    /// @param _amount The reward amount
    function notifyRewardAmount(uint256 _amount) external virtual override nonReentrant {
        uint256 requiredBalance = _validateAndGetRequiredBalance(_amount);
        _notifyRewardAmountWithCustomDuration(_amount, requiredBalance);
    }

    /// @notice Validates sufficient reward token balance and returns the required balance
    /// @dev Virtual function allowing variants to implement appropriate balance checks
    /// @param _amount The reward amount being added
    /// @return required The required balance for this variant
    function _validateAndGetRequiredBalance(uint256 _amount) internal view virtual returns (uint256 required) {
        uint256 currentBalance = REWARD_TOKEN.balanceOf(address(this));

        // For variants with surrogates: stakes are NOT in main contract
        // Only track rewards obligations: outstanding rewards + new amount
        uint256 carryOverAmount = totalRewards - totalClaimedRewards;
        required = carryOverAmount + _amount;

        if (currentBalance < required) {
            revert InsufficientRewardBalance(currentBalance, required);
        }

        return required;
    }

    /// @inheritdoc Staker
    /// @notice Prevents staking more when paused or by unauthorized owners; ensures non-zero amount and final balance meets minimum.
    /// @dev Uses reentrancy guard; validates deposit.owner against staker access control before proceeding
    /// @param deposit The deposit storage
    /// @param _depositId The deposit identifier
    /// @param _amount The additional amount to stake
    function _stakeMore(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        uint256 _amount
    ) internal virtual override whenNotPaused nonReentrant {
        require(_amount > 0, ZeroOperation());
        _checkStakerAccess(deposit.owner);
        super._stakeMore(deposit, _depositId, _amount);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Override to add nonReentrant modifier and fix checks-effects-interactions pattern
    /// @dev Adds reentrancy protection and corrects state update ordering
    /// @dev Updates state BEFORE external transfer to prevent reentrancy vulnerabilities
    /// @param _depositId The deposit identifier to bump earning power for
    /// @param _tipReceiver The receiver of the reward for updating a deposit's earning power
    /// @param _requestedTip The amount of tip requested by the third-party
    function bumpEarningPower(
        DepositIdentifier _depositId,
        address _tipReceiver,
        uint256 _requestedTip
    ) public virtual override whenNotPaused nonReentrant {
        if (_requestedTip > maxBumpTip) revert Staker__InvalidTip();

        Deposit storage deposit = deposits[_depositId];

        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 _unclaimedRewards = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;

        (uint256 _newEarningPower, bool _isQualifiedForBump) = earningPowerCalculator.getNewEarningPower(
            deposit.balance,
            deposit.owner,
            deposit.delegatee,
            deposit.earningPower
        );
        if (!_isQualifiedForBump || _newEarningPower == deposit.earningPower) {
            revert Staker__Unqualified(_newEarningPower);
        }

        if (_newEarningPower > deposit.earningPower && _unclaimedRewards < _requestedTip) {
            revert Staker__InsufficientUnclaimedRewards();
        }

        uint256 tipToPay = _requestedTip;
        if (_requestedTip > _unclaimedRewards) {
            tipToPay = _unclaimedRewards;
        }

        emit EarningPowerBumped(_depositId, deposit.earningPower, _newEarningPower, msg.sender, _tipReceiver, tipToPay);

        // Update global earning power & deposit earning power based on this bump
        totalEarningPower = _calculateTotalEarningPower(deposit.earningPower, _newEarningPower, totalEarningPower);
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            _newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );
        deposit.earningPower = _newEarningPower.toUint96();

        // CRITICAL: Update state BEFORE external call (checks-effects-interactions pattern)
        // This prevents reentrancy attacks via malicious reward tokens with callbacks
        _consumeRewards(deposit, tipToPay);

        // External call AFTER all state updates. Some ERC20 tokens revert on zero-value transfers,
        // so skip the call entirely when no tip is due. This also prevents unnecessary gas consumption for zero-value transfers.
        if (tipToPay > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, _tipReceiver, tipToPay);
        }
    }
}
