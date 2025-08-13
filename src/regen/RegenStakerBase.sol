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
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";

// === Contract Header ===
/// @title RegenStakerBase
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Base contract for RegenStaker variants, extending the Staker contract by [ScopeLift](https://scopelift.co).
/// @notice This contract provides shared functionality including:
///         - Variable reward duration (7-3000 days, configurable by admin)
///         - Optional reward taxation via claim fees (0 to MAX_CLAIM_FEE)
///         - Earning power management with external bumping incentivized by tips (up to maxBumpTip)
///         - Adjustable minimum stake amount (existing deposits grandfathered with restrictions)
///         - Whitelist support for stakers, contributors, and allocation mechanisms
///         - Reward compounding (when REWARD_TOKEN == STAKE_TOKEN)
///         - Reward contribution to whitelisted allocation mechanisms
///         - Admin controls (pause/unpause, config updates)
/// @dev PRECISION IMPLICATIONS: Variable reward durations affect calculation precision. The original Staker contract assumed a fixed
///      30-day duration for optimal precision. This contract allows 7-3000 days, providing flexibility with excellent precision.
///      The SCALE_FACTOR (1e36) ensures minimal precision loss consistently ~1 wei across all reward durations (7-3000 days),
///      representing negligible error (< 0.0001%) for typical reward amounts. Duration does not significantly affect precision
///      due to the robust scaling factor design.
/// @dev This base is abstract, with variants implementing token-specific behaviors (e.g., delegation surrogates).
/// @dev Earning power updates are required after balance changes; some are automatic, others via bumpEarningPower.
/// @dev If rewards should not be taxable, set MAX_CLAIM_FEE to 0 in deployment.
abstract contract RegenStakerBase is Staker, Pausable, ReentrancyGuard, EIP712, StakerPermitAndStake, StakerOnBehalf {
    using SafeCast for uint256;

    // === Structs ===
    /// @notice Struct to hold shared configuration state
    /// @dev Groups related configuration variables for better storage efficiency and easier inheritance.
    struct SharedState {
        uint128 rewardDuration;
        uint128 minimumStakeAmount;
        IWhitelist stakerWhitelist;
        IWhitelist contributionWhitelist;
        IWhitelist allocationMechanismWhitelist;
    }

    // === Constants ===
    /// @notice Minimum allowed reward duration in seconds (7 days).
    uint256 public constant MIN_REWARD_DURATION = 7 days;

    /// @notice Maximum allowed reward duration to prevent excessively long reward periods.
    uint256 public constant MAX_REWARD_DURATION = 3000 days;

    // === Custom Errors ===
    /// @notice Error thrown when an address is not whitelisted
    /// @param whitelist The whitelist contract
    /// @param user The user address
    error NotWhitelisted(IWhitelist whitelist, address user);

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

    /// @notice Error thrown when attempting to disable allocation whitelist
    error DisablingAllocationMechanismWhitelistNotAllowed();

    // === State Variables ===
    /// @notice Shared configuration state instance
    /// @dev Internal storage for shared configuration accessible via getters.
    SharedState internal sharedState;

    // === Events ===
    /// @notice Emitted when the staker whitelist is updated
    /// @param whitelist The new whitelist contract address
    event StakerWhitelistSet(IWhitelist indexed whitelist);

    /// @notice Emitted when the contribution whitelist is updated
    /// @param whitelist The new whitelist contract address
    event ContributionWhitelistSet(IWhitelist indexed whitelist);

    /// @notice Emitted when the allocation mechanism whitelist is updated
    /// @param whitelist The new whitelist contract address
    event AllocationMechanismWhitelistSet(IWhitelist indexed whitelist);

    /// @notice Emitted when the reward duration is updated
    /// @param newDuration The new reward duration in seconds
    event RewardDurationSet(uint256 newDuration);

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

    /// @notice Emitted when rewards are compounded
    /// @param depositId The deposit identifier
    /// @param user The user's address
    /// @param rewardAmount The reward amount compounded
    /// @param newBalance The new deposit balance
    /// @param newEarningPower The new earning power
    event RewardCompounded(
        DepositIdentifier indexed depositId,
        address indexed user,
        uint256 rewardAmount,
        uint256 newBalance,
        uint256 newEarningPower
    );

    /// @notice Error thrown when a required surrogate is missing
    /// @param delegatee The delegatee for which a surrogate was expected
    error SurrogateNotFound(address delegatee);

    /// @notice Emitted when the minimum stake amount is updated
    /// @param newMinimumStakeAmount The new minimum stake amount
    event MinimumStakeAmountSet(uint256 newMinimumStakeAmount);

    /// @notice Emitted when a whitelist is disabled (set to address(0))
    event StakerWhitelistDisabled();
    event ContributionWhitelistDisabled();

    // === Getters ===
    /// @notice Gets the current reward duration
    /// @return The reward duration in seconds
    function rewardDuration() external view returns (uint256) {
        return sharedState.rewardDuration;
    }

    /// @notice Gets the staker whitelist
    /// @return The staker whitelist contract
    function stakerWhitelist() external view returns (IWhitelist) {
        return sharedState.stakerWhitelist;
    }

    /// @notice Gets the contribution whitelist
    /// @return The contribution whitelist contract
    function contributionWhitelist() external view returns (IWhitelist) {
        return sharedState.contributionWhitelist;
    }

    /// @notice Gets the allocation mechanism whitelist
    /// @return The allocation mechanism whitelist contract
    function allocationMechanismWhitelist() external view returns (IWhitelist) {
        return sharedState.allocationMechanismWhitelist;
    }

    /// @notice Gets the minimum stake amount
    /// @return The minimum stake amount in wei
    function minimumStakeAmount() external view returns (uint256) {
        return sharedState.minimumStakeAmount;
    }

    // === Modifiers ===
    /// @notice Modifier to check whitelist if set
    /// @dev Reverts if whitelist is set and user is not whitelisted
    /// @param _whitelist The whitelist to check
    /// @param _user The user to check
    modifier onlyWhitelistedIfWhitelistIsSet(IWhitelist _whitelist, address _user) {
        _checkWhitelisted(_whitelist, _user);
        _;
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
    /// @param _maxClaimFee The max claim fee
    /// @param _minimumStakeAmount The min stake amount
    /// @param _stakerWhitelist Staker whitelist
    /// @param _contributionWhitelist Contribution whitelist
    /// @param _allocationMechanismWhitelist Allocation mechanism whitelist (cannot be address(0))
    /// @param _eip712Name The EIP712 domain name
    constructor(
        IERC20 _rewardsToken,
        IERC20 _stakeToken,
        IEarningPowerCalculator _earningPowerCalculator,
        uint256 _maxBumpTip,
        address _admin,
        uint128 _rewardDuration,
        uint256 _maxClaimFee,
        uint128 _minimumStakeAmount,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IWhitelist _allocationMechanismWhitelist,
        string memory _eip712Name
    )
        Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
        StakerPermitAndStake(IERC20Permit(address(_stakeToken)))
        EIP712(_eip712Name, "1")
    {
        MAX_CLAIM_FEE = _maxClaimFee;
        _setClaimFeeParameters(ClaimFeeParameters({ feeAmount: 0, feeCollector: address(0) }));

        // Enable self-transfers for compound operations when stake and reward tokens are the same
        // This allows compoundRewards to use _stakeTokenSafeTransferFrom with address(this) as source
        if (address(STAKE_TOKEN) == address(REWARD_TOKEN)) {
            SafeERC20.safeIncreaseAllowance(STAKE_TOKEN, address(this), type(uint256).max);
        }

        // Initialize shared state
        _initializeSharedState(
            _rewardDuration,
            _minimumStakeAmount,
            _stakerWhitelist,
            _contributionWhitelist,
            _allocationMechanismWhitelist
        );
    }

    // === Internal Functions ===
    /// @notice Initialize shared state with validation
    /// @dev Called by child constructors to set up shared configuration
    /// @param _rewardDuration The duration over which rewards are distributed
    /// @param _minimumStakeAmount The minimum stake amount
    /// @param _stakerWhitelist The whitelist for stakers
    /// @param _contributionWhitelist The whitelist for contributors
    /// @param _allocationMechanismWhitelist The whitelist for allocation mechanisms
    function _initializeSharedState(
        uint128 _rewardDuration,
        uint128 _minimumStakeAmount,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IWhitelist _allocationMechanismWhitelist
    ) internal {
        require(
            _rewardDuration >= MIN_REWARD_DURATION && _rewardDuration <= MAX_REWARD_DURATION,
            InvalidRewardDuration(uint256(_rewardDuration))
        );
        // Align initialization invariants with setters: allocation mechanism whitelist cannot be disabled
        require(
            address(_allocationMechanismWhitelist) != address(0),
            DisablingAllocationMechanismWhitelistNotAllowed()
        );
        // Sanity check: Allocation mechanism whitelist must be distinct from other whitelists
        require(
            address(_allocationMechanismWhitelist) != address(_stakerWhitelist) &&
                address(_allocationMechanismWhitelist) != address(_contributionWhitelist),
            Staker__InvalidAddress()
        );

        // Emit events first to match setter ordering
        emit RewardDurationSet(_rewardDuration);
        emit MinimumStakeAmountSet(_minimumStakeAmount);

        if (address(_stakerWhitelist) == address(0)) {
            emit StakerWhitelistDisabled();
        } else {
            emit StakerWhitelistSet(_stakerWhitelist);
        }

        if (address(_contributionWhitelist) == address(0)) {
            emit ContributionWhitelistDisabled();
        } else {
            emit ContributionWhitelistSet(_contributionWhitelist);
        }

        emit AllocationMechanismWhitelistSet(_allocationMechanismWhitelist);

        // Assign to storage after emits for consistency with setters
        sharedState.rewardDuration = _rewardDuration;
        sharedState.minimumStakeAmount = _minimumStakeAmount;
        sharedState.stakerWhitelist = _stakerWhitelist;
        sharedState.contributionWhitelist = _contributionWhitelist;
        sharedState.allocationMechanismWhitelist = _allocationMechanismWhitelist;
    }

    /// @notice Sets the reward duration for future reward notifications
    /// @dev PRECISION NOTE: The SCALE_FACTOR (1e36) ensures minimal precision loss across all
    ///      reward durations (7-3000 days). Actual precision loss is consistently ~1 wei regardless
    ///      of duration, representing negligible error (< 0.0001%) for typical reward amounts.
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
    /// @param _amount The reward amount to notify
    function _notifyRewardAmountWithCustomDuration(uint256 _amount) internal {
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

        // This check cannot _guarantee_ sufficient rewards have been transferred to the contract,
        // because it cannot isolate the unclaimed rewards owed to stakers left in the balance. While
        // this check is useful for preventing degenerate cases, it is not sufficient. Therefore, it is
        // critical that only safe reward notifier contracts are approved to call this method by the
        // admin.
        if ((scaledRewardRate * sharedState.rewardDuration) > (REWARD_TOKEN.balanceOf(address(this)) * SCALE_FACTOR)) {
            revert Staker__InsufficientRewardBalance();
        }

        emit RewardNotified(_amount, msg.sender);
    }

    /// @notice Sets the whitelist for stakers (who can stake tokens)
    /// @dev ACCESS CONTROL: Use address(0) to disable whitelisting and allow all addresses.
    /// @dev OPERATIONAL IMPACT: Affects all stake and stakeMore operations immediately.
    /// @dev GRANDFATHERING: Existing stakers can continue operations regardless of new whitelist.
    /// @dev Can only be called by admin
    /// @param _stakerWhitelist New staker whitelist contract (address(0) = no restrictions)
    function setStakerWhitelist(IWhitelist _stakerWhitelist) external {
        require(sharedState.stakerWhitelist != _stakerWhitelist, NoOperation());
        // Sanity check: staker whitelist must be distinct from allocation mechanism whitelist
        require(
            address(_stakerWhitelist) != address(sharedState.allocationMechanismWhitelist),
            Staker__InvalidAddress()
        );
        _revertIfNotAdmin();
        if (address(_stakerWhitelist) == address(0)) {
            emit StakerWhitelistDisabled();
        } else {
            emit StakerWhitelistSet(_stakerWhitelist);
        }
        sharedState.stakerWhitelist = _stakerWhitelist;
    }

    /// @notice Sets the whitelist for contributors (who can contribute rewards)
    /// @dev ACCESS CONTROL: Use address(0) to disable whitelisting and allow all addresses.
    /// @dev OPERATIONAL IMPACT: Affects all contribute operations immediately.
    /// @dev GRANDFATHERING: Existing contributors can continue operations regardless of new whitelist.
    /// @dev Can only be called by admin
    /// @param _contributionWhitelist New contribution whitelist contract (address(0) = no restrictions)
    function setContributionWhitelist(IWhitelist _contributionWhitelist) external {
        require(sharedState.contributionWhitelist != _contributionWhitelist, NoOperation());
        // Prevent footgun: ensure distinct from allocation mechanism whitelist
        require(
            address(_contributionWhitelist) != address(sharedState.allocationMechanismWhitelist),
            Staker__InvalidAddress()
        );
        _revertIfNotAdmin();
        if (address(_contributionWhitelist) == address(0)) {
            emit ContributionWhitelistDisabled();
        } else {
            emit ContributionWhitelistSet(_contributionWhitelist);
        }
        sharedState.contributionWhitelist = _contributionWhitelist;
    }

    /// @notice Sets the whitelist for allocation mechanisms
    /// @dev SECURITY: Only add thoroughly audited allocation mechanisms to this whitelist.
    ///      Users will contribute rewards to whitelisted mechanisms and funds cannot be recovered
    ///      if sent to malicious or buggy implementations.
    /// @dev EVALUATION PROCESS: New mechanisms should undergo comprehensive security audit,
    ///      integration testing, and governance review before whitelisting.
    /// @dev OPERATIONAL IMPACT: Changes affect all future contributions. Existing contributions
    ///      to previously whitelisted mechanisms are not affected.
    /// @dev Can only be called by admin. Cannot set to address(0).
    /// @dev AUDIT NOTE: Changes require governance approval.
    /// @param _allocationMechanismWhitelist New whitelist contract (cannot be address(0))
    function setAllocationMechanismWhitelist(IWhitelist _allocationMechanismWhitelist) external {
        require(sharedState.allocationMechanismWhitelist != _allocationMechanismWhitelist, NoOperation());
        require(
            address(_allocationMechanismWhitelist) != address(0),
            DisablingAllocationMechanismWhitelistNotAllowed()
        );
        // Prevent footgun: allocation mechanism whitelist must be distinct from other whitelists
        require(
            address(_allocationMechanismWhitelist) != address(sharedState.stakerWhitelist) &&
                address(_allocationMechanismWhitelist) != address(sharedState.contributionWhitelist),
            Staker__InvalidAddress()
        );
        _revertIfNotAdmin();
        emit AllocationMechanismWhitelistSet(_allocationMechanismWhitelist);
        sharedState.allocationMechanismWhitelist = _allocationMechanismWhitelist;
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
    /// @dev TRUST MODEL: Allocation mechanisms must be whitelisted by protocol governance.
    ///      Only contribute to mechanisms you trust, as the protocol cannot recover funds
    ///      sent to malicious or buggy allocation mechanisms.
    /// @dev SECURITY: This function first withdraws rewards to the contributor, then the contributor
    ///      must have pre-approved the allocation mechanism to pull the tokens.
    /// @dev SECURITY AUDIT: Ensure allocation mechanisms are immutable post-whitelisting.
    /// @dev Requires contract not paused and uses reentrancy guard
    /// @param _depositId The deposit identifier to contribute from
    /// @param _allocationMechanismAddress Whitelisted allocation mechanism to receive contribution
    /// @param _amount Amount of unclaimed rewards to contribute (must be <= available rewards)
    /// @param _deadline Signature expiration timestamp
    /// @param _v Signature component v
    /// @param _r Signature component r
    /// @param _s Signature component s
    /// @return amountContributedToAllocationMechanism Actual amount contributed (after fees)
    function contribute(
        DepositIdentifier _depositId,
        address _allocationMechanismAddress,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public virtual whenNotPaused nonReentrant returns (uint256 amountContributedToAllocationMechanism) {
        _checkWhitelisted(sharedState.contributionWhitelist, msg.sender);
        require(_amount > 0, ZeroOperation());
        _revertIfAddressZero(_allocationMechanismAddress);
        require(
            sharedState.allocationMechanismWhitelist.isWhitelisted(_allocationMechanismAddress),
            NotWhitelisted(sharedState.allocationMechanismWhitelist, _allocationMechanismAddress)
        );

        Deposit storage deposit = deposits[_depositId];
        if (deposit.claimer != msg.sender && deposit.owner != msg.sender) {
            revert Staker__Unauthorized("not claimer or owner", msg.sender);
        }

        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 unclaimedAmount = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;
        require(_amount <= unclaimedAmount, CantAfford(_amount, unclaimedAmount));

        uint256 fee = claimFeeParameters.feeAmount;
        amountContributedToAllocationMechanism = _calculateNetContribution(_amount, fee);

        // Prevent zero-amount contributions after fee deduction
        require(amountContributedToAllocationMechanism > 0, ZeroOperation());

        uint256 scaledAmountConsumed = _amount * SCALE_FACTOR;
        deposit.scaledUnclaimedRewardCheckpoint = deposit.scaledUnclaimedRewardCheckpoint - scaledAmountConsumed;

        emit RewardClaimed(_depositId, msg.sender, amountContributedToAllocationMechanism, deposit.earningPower);

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
            msg.sender,
            amountContributedToAllocationMechanism,
            _deadline,
            _v,
            _r,
            _s
        );

        if (fee > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, claimFeeParameters.feeCollector, fee);
        }

        // check that allowance is zero
        require(REWARD_TOKEN.allowance(address(this), _allocationMechanismAddress) == 0, "allowance not zero");

        return amountContributedToAllocationMechanism;
    }

    /// @notice Compounds rewards by claiming them and immediately restaking them into the same deposit
    /// @dev REQUIREMENT: Only works when REWARD_TOKEN == STAKE_TOKEN, otherwise reverts.
    /// @dev FEE HANDLING: Claim fees are deducted before compounding. Zero fee results in zero compound.
    /// @dev EARNING POWER: Compounding updates earning power based on new total balance.
    /// @dev GAS OPTIMIZATION: More efficient than separate claim + stake operations.
    /// @dev Requires contract not paused and uses reentrancy guard
    /// @param _depositId The deposit to compound rewards for
    /// @return compoundedAmount Amount of rewards compounded (after fees)
    function compoundRewards(
        DepositIdentifier _depositId
    ) external virtual whenNotPaused nonReentrant returns (uint256 compoundedAmount) {
        _checkWhitelisted(sharedState.stakerWhitelist, msg.sender);
        if (address(REWARD_TOKEN) != address(STAKE_TOKEN)) {
            revert CompoundingNotSupported();
        }

        Deposit storage deposit = deposits[_depositId];
        address depositOwner = deposit.owner;

        if (deposit.claimer != msg.sender && depositOwner != msg.sender) {
            revert Staker__Unauthorized("not claimer or owner", msg.sender);
        }

        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 unclaimedAmount = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;
        if (unclaimedAmount == 0) {
            return 0;
        }

        ClaimFeeParameters memory feeParams = claimFeeParameters;
        uint256 fee = feeParams.feeAmount;

        if (unclaimedAmount < fee) {
            return 0;
        }

        compoundedAmount = unclaimedAmount - fee;
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

        // Preserve sub-wei dust like claimReward by subtracting the scaled amount claimed
        // This is done BEFORE updating balance/earning power to match base _claimReward pattern
        deposit.scaledUnclaimedRewardCheckpoint =
            deposit.scaledUnclaimedRewardCheckpoint -
            (unclaimedAmount * SCALE_FACTOR);

        deposit.balance = newBalance.toUint96();
        deposit.earningPower = newEarningPower.toUint96();

        if (fee > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, feeParams.feeCollector, fee);
        }

        // Transfer compounded rewards using the same pattern as _stakeMore for consistency
        // The surrogate must already exist since the deposit exists (created during initial stake)
        // This ensures child contracts can customize behavior through _stakeTokenSafeTransferFrom
        DelegationSurrogate _surrogate = surrogates(deposit.delegatee);
        if (address(_surrogate) == address(0)) {
            revert SurrogateNotFound(deposit.delegatee);
        }
        _stakeTokenSafeTransferFrom(address(this), address(_surrogate), compoundedAmount);

        emit RewardClaimed(_depositId, msg.sender, compoundedAmount, oldEarningPower);
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

    /// @notice Check if user is whitelisted when whitelist is set
    /// @dev Internal view function, reverts if not whitelisted
    /// @param whitelist The whitelist to check against
    /// @param user The user address to check
    function _checkWhitelisted(IWhitelist whitelist, address user) internal view {
        if (whitelist != IWhitelist(address(0)) && !whitelist.isWhitelisted(user)) {
            revert NotWhitelisted(whitelist, user);
        }
    }

    /// @notice Calculate net contribution amount after deducting fees
    /// @dev Pure function for fee calculation
    /// @param amount The gross amount to contribute
    /// @param feeAmount The fee amount to deduct
    /// @return netAmount The amount after fee deduction
    function _calculateNetContribution(uint256 amount, uint256 feeAmount) internal pure returns (uint256 netAmount) {
        if (feeAmount == 0) {
            netAmount = amount;
        } else {
            require(amount >= feeAmount, CantAfford(feeAmount, amount));
            netAmount = amount - feeAmount;
        }
    }

    // === Overridden Functions ===
    /// @inheritdoc Staker
    /// @notice Overrides to prevent staking 0 tokens.
    /// @notice Overrides to prevent staking below the minimum stake amount.
    /// @notice Overrides to prevent staking when the contract is paused.
    /// @notice Overrides to prevent staking if the staker is not whitelisted.
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
        _checkWhitelisted(sharedState.stakerWhitelist, _depositor);
        _depositId = super._stake(_depositor, _amount, _delegatee, _claimer);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent pushing the amount below the minimum stake amount.
    /// @notice Overrides to prevent withdrawing when the contract is paused.
    /// @notice Overrides to prevent withdrawing 0 tokens.
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
    ) internal virtual override nonReentrant {
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
    ) internal virtual override nonReentrant {
        super._alterClaimer(deposit, _depositId, _newClaimer);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent claiming when the contract is paused.
    /// @dev Uses reentrancy guard
    /// @param _depositId The deposit identifier
    /// @param deposit The deposit storage
    /// @param _claimer The claimer address
    /// @return The claimed amount
    function _claimReward(
        DepositIdentifier _depositId,
        Deposit storage deposit,
        address _claimer
    ) internal virtual override whenNotPaused nonReentrant returns (uint256) {
        return super._claimReward(_depositId, deposit, _claimer);
    }

    /// @notice Override notifyRewardAmount to use custom reward duration
    /// @dev nonReentrant as a belts-and-braces guard against exotic ERC20 callback reentry
    /// @param _amount The reward amount
    function notifyRewardAmount(uint256 _amount) external virtual override nonReentrant {
        _notifyRewardAmountWithCustomDuration(_amount);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent staking 0 tokens.
    /// @notice Overrides to ensure the final stake amount meets the minimum requirement.
    /// @notice Overrides to prevent staking more when the contract is paused.
    /// @notice Overrides to prevent staking more if the deposit owner is not whitelisted.
    /// @dev Uses reentrancy guard; validates deposit.owner against staker whitelist before proceeding
    /// @param deposit The deposit storage
    /// @param _depositId The deposit identifier
    /// @param _amount The additional amount to stake
    function _stakeMore(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        uint256 _amount
    ) internal virtual override whenNotPaused nonReentrant {
        require(_amount > 0, ZeroOperation());
        _checkWhitelisted(sharedState.stakerWhitelist, deposit.owner);
        super._stakeMore(deposit, _depositId, _amount);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }
}
