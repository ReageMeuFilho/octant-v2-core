// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// Staker Library Imports
import { Staker, IEarningPowerCalculator, SafeCast, SafeERC20, IERC20 } from "staker/Staker.sol";

// Local Imports
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";

// Import necessary types from Staker
type DepositIdentifier is uint256;

/// @title RegenStakerShared
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Library containing shared functionality for RegenStaker variants.
/// @notice This library provides common functions for:
///         - Variable reward duration (7-3000 days)
///         - Whitelist support for stakers, contributors, and allocation mechanisms
///         - Minimum stake amount enforcement
///         - Reward compounding
///         - Reward contribution to allocation mechanisms
/// @dev SCALE_FACTOR (1e36) is inherited from base Staker and used to minimize precision loss in reward calculations.
/// @dev Earning power is capped at uint96.max (~7.9e28) to prevent overflow in reward calculations.
/// @dev PRECISION IMPLICATIONS: Variable reward durations affect calculation precision. The original Staker contract assumed a fixed
///      30-day duration for optimal precision. This contract allows 7-3000 days, providing flexibility at the cost of potential precision loss.
///      Shorter durations (especially < 30 days) can increase the margin of error in reward calculations by up to ~1% due to increased
///      reward rates amplifying rounding errors in scaled arithmetic operations. This is an intentional design trade-off favoring
///      operational flexibility over mathematical precision. For maximum precision, prefer longer reward durations (≥30 days).
library RegenStakerShared {
    using SafeCast for uint256;

    /// @notice Minimum allowed reward duration. Values below 30 days may introduce precision loss up to ~1%.
    /// @dev The original Staker contract used a fixed 30-day duration. Allowing shorter durations trades precision for flexibility.
    uint256 public constant MIN_REWARD_DURATION = 7 days;

    /// @notice Maximum allowed reward duration to prevent excessively long reward periods.
    uint256 public constant MAX_REWARD_DURATION = 3000 days;

    // Events
    event StakerWhitelistSet(IWhitelist indexed whitelist);
    event ContributionWhitelistSet(IWhitelist indexed whitelist);
    event AllocationMechanismWhitelistSet(IWhitelist indexed whitelist);
    event RewardDurationSet(uint256 newDuration);
    event RewardContributed(
        DepositIdentifier indexed depositId,
        address indexed contributor,
        address indexed fundingRound,
        uint256 amount
    );
    event RewardCompounded(
        DepositIdentifier indexed depositId,
        address indexed user,
        uint256 rewardAmount,
        uint256 newBalance,
        uint256 newEarningPower
    );
    event MinimumStakeAmountSet(uint256 newMinimumStakeAmount);

    // Errors
    error NotWhitelisted(IWhitelist whitelist, address user);
    error CantAfford(uint256 requested, uint256 available);
    error MinimumStakeAmountNotMet(uint256 expected, uint256 actual);
    error InvalidRewardDuration(uint256 rewardDuration);
    error CannotChangeRewardDurationDuringActiveReward();
    error CompoundingNotSupported();
    error CannotRaiseMinimumStakeAmountDuringActiveReward();
    error ZeroOperation();
    error NoOperation();
    error DisablingAllocationMechanismWhitelistNotAllowed();

    /// @notice Struct to hold shared configuration state
    struct SharedState {
        uint256 rewardDuration;
        IWhitelist stakerWhitelist;
        IWhitelist contributionWhitelist;
        IWhitelist allocationMechanismWhitelist;
        uint256 minimumStakeAmount;
    }

    /// @notice Struct to hold fee parameters
    struct ClaimFeeParameters {
        uint256 feeAmount;
        address feeCollector;
    }

    /// @notice Struct representing a deposit
    struct Deposit {
        uint96 balance;
        address owner;
        address delegatee;
        address claimer;
        uint96 earningPower;
        uint256 rewardPerTokenCheckpoint;
        uint256 scaledUnclaimedRewardCheckpoint;
    }

    /// @notice Initialize shared state with validation
    /// @param state The shared state struct to initialize
    /// @param _rewardDuration The duration over which rewards are distributed
    /// @param _minimumStakeAmount The minimum stake amount
    /// @param _stakerWhitelist The whitelist for stakers
    /// @param _contributionWhitelist The whitelist for contributors
    /// @param _allocationMechanismWhitelist The whitelist for allocation mechanisms
    function initializeSharedState(
        SharedState storage state,
        uint256 _rewardDuration,
        uint256 _minimumStakeAmount,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IWhitelist _allocationMechanismWhitelist
    ) external {
        require(
            _rewardDuration >= MIN_REWARD_DURATION && _rewardDuration <= MAX_REWARD_DURATION,
            InvalidRewardDuration(_rewardDuration)
        );

        state.rewardDuration = _rewardDuration;
        state.minimumStakeAmount = _minimumStakeAmount;
        state.stakerWhitelist = _stakerWhitelist;
        state.contributionWhitelist = _contributionWhitelist;
        state.allocationMechanismWhitelist = _allocationMechanismWhitelist;

        emit RewardDurationSet(_rewardDuration);
        emit MinimumStakeAmountSet(_minimumStakeAmount);
    }

    /// @notice Check if user is whitelisted when whitelist is set
    /// @param whitelist The whitelist to check against
    /// @param user The user address to check
    function checkWhitelisted(IWhitelist whitelist, address user) external view {
        if (whitelist != IWhitelist(address(0)) && !whitelist.isWhitelisted(user)) {
            revert NotWhitelisted(whitelist, user);
        }
    }

    /// @notice Validate minimum stake amount for a deposit
    /// @param deposit The deposit to check
    /// @param minimumStakeAmount The minimum stake amount required
    function validateMinimumStakeAmount(Deposit storage deposit, uint256 minimumStakeAmount) external view {
        if (deposit.balance < minimumStakeAmount && deposit.balance > 0) {
            revert MinimumStakeAmountNotMet(minimumStakeAmount, deposit.balance);
        }
    }
}
