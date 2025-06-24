// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// OpenZeppelin Imports
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Staker Library Imports
import { IERC20, SafeERC20, SafeCast } from "staker/Staker.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

// Local Imports
import { RegenStaker } from "./RegenStaker.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";

/// @title ProxyableRegenStaker
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This contract is a proxy-compatible version of RegenStaker designed for minimal proxy pattern
/// @notice Uses storage variables for reward token, stake token, and max claim fee instead of immutable variables
/// @notice The reward duration can be configured by the admin, overriding the base Staker's constant value.
/// @notice You can tax the rewards with a claim fee. If you don't want rewards to be taxable, set MAX_CLAIM_FEE to 0.
/// @notice Earning power needs to be updated after deposit amount changes. Some changes are automatically triggering the update.
/// @notice Earning power is updated via bumpEarningPower externally. This action is incentivized with a tip. Use maxBumpTip to set the maximum tip.
/// @notice The admin can adjust the minimum stake amount. Existing deposits below a newly set threshold remain valid
///         but will be restricted from certain operations (partial withdraw, stake increase below threshold) until brought above the threshold.
/// @dev SCALE_FACTOR (1e36) is inherited from base Staker and used to minimize precision loss in reward calculations by scaling up values before division.
/// @dev Earning power is capped at uint96.max (~7.9e28) to prevent overflow in reward calculations while still supporting extremely large values.
/// @dev This contract uses the surrogate pattern from base Staker: tokens are transferred to surrogate contracts that delegate voting power to the designated delegatee.
/// @dev Storage variables replace immutable variables from base Staker to enable proxy compatibility
contract ProxyableRegenStaker is RegenStaker, Initializable
{
    using SafeCast for uint256;

    // Storage variables to replace immutable variables from base Staker
    IERC20 private rewardTokenStorage;
    IERC20 private stakeTokenStorage;
    uint256 private maxClaimFeeStorage;

    /// @notice Constructor for the implementation contract (master copy)
    /// @dev This sets placeholder values for immutable variables in the implementation
    /// @dev Real values are set via storage variables when creating clones
    constructor()
        RegenStaker(
            IERC20(address(1)), // non-zero placeholder to avoid immutable assignment error
            IERC20Staking(address(1)), // non-zero placeholder to avoid immutable assignment error
            address(1), // non-zero placeholder admin
            IWhitelist(address(0)), // placeholder - can be zero
            IWhitelist(address(0)), // placeholder - can be zero
            IWhitelist(address(1)), // non-zero placeholder to avoid validation error
            IEarningPowerCalculator(address(1)), // non-zero placeholder to avoid immutable assignment error
            0, // placeholder maxBumpTip
            0, // placeholder maxClaimFee - NOTE: This creates the immutable variable issue
            0, // placeholder minimumStakeAmount
            7 days // MIN_REWARD_DURATION placeholder
        )
    {
        _disableInitializers();
    }

    /// @notice Initialize the proxy instance
    /// @param _rewardToken The token that will be used to reward contributors.
    /// @param _stakeToken The token that will be used to stake.
    /// @param _maxClaimFee The maximum claim fee.
    /// @param _admin The address of the admin. TRUSTED.
    /// @param _stakerWhitelist The whitelist for stakers. Can be address(0) to disable whitelisting.
    /// @param _contributionWhitelist The whitelist for contributors. Can be address(0) to disable whitelisting.
    /// @param _allocationMechanismWhitelist The whitelist for allocation mechanisms.
    /// @param _earningPowerCalculator The earning power calculator.
    /// @param _maxBumpTip The maximum bump tip.
    /// @param _minimumStakeAmount The minimum stake amount.
    /// @param _rewardDuration The duration over which rewards are distributed.
    function initialize(
        IERC20 _rewardToken,
        IERC20 _stakeToken,
        uint256 _maxClaimFee,
        address _admin,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IWhitelist _allocationMechanismWhitelist,
        IEarningPowerCalculator _earningPowerCalculator,
        uint256 _maxBumpTip,
        uint256 _minimumStakeAmount,
        uint256 _rewardDuration
    ) external initializer {
        require(
            _rewardDuration >= MIN_REWARD_DURATION && _rewardDuration <= MAX_REWARD_DURATION,
            InvalidRewardDuration(_rewardDuration)
        );

        // Set storage variables that replace immutable variables
        rewardTokenStorage = _rewardToken;
        stakeTokenStorage = _stakeToken;
        maxClaimFeeStorage = _maxClaimFee;

        // Initialize parent contracts
        _setAdmin(_admin);
        _setMaxBumpTip(_maxBumpTip);
        _setEarningPowerCalculator(address(_earningPowerCalculator));

        rewardDuration = _rewardDuration;
        emit RewardDurationSet(_rewardDuration);

        stakerWhitelist = _stakerWhitelist;
        contributionWhitelist = _contributionWhitelist;
        allocationMechanismWhitelist = _allocationMechanismWhitelist;

        _setClaimFeeParameters(ClaimFeeParameters({ feeAmount: 0, feeCollector: address(0) }));
        minimumStakeAmount = _minimumStakeAmount;
    }

    /// @notice Get the reward token from storage
    /// @dev Returns the proxy's reward token, overriding base Staker's immutable version
    function getRewardToken() public view returns (IERC20) {
        return rewardTokenStorage;
    }

    /// @notice Get the stake token from storage
    /// @dev Returns the proxy's stake token, overriding base Staker's immutable version
    function getStakeToken() public view returns (IERC20) {
        return stakeTokenStorage;
    }

    /// @notice Get the max claim fee from storage
    /// @dev Returns the proxy's max claim fee, overriding base Staker's immutable version
    function getMaxClaimFee() public view returns (uint256) {
        return maxClaimFeeStorage;
    }

    /// @notice Override to use storage variable for max claim fee validation
    function _setClaimFeeParameters(ClaimFeeParameters memory _params) internal override {
        if (_params.feeAmount > getMaxClaimFee() || (_params.feeCollector == address(0) && _params.feeAmount > 0))
            revert Staker__InvalidClaimFeeParameters();

        emit ClaimFeeParametersSet(
            claimFeeParameters.feeAmount,
            _params.feeAmount,
            claimFeeParameters.feeCollector,
            _params.feeCollector
        );

        claimFeeParameters = _params;
    }

    /// @notice Override to use storage variable for stake token transfers
    function _stakeTokenSafeTransferFrom(address _from, address _to, uint256 _value) internal override {
        SafeERC20.safeTransferFrom(getStakeToken(), _from, _to, _value);
    }



    /// @notice Overrides to use the custom reward duration and storage variables
    /// @notice Changing the reward duration will not affect the rate of the rewards unless this function is called.
    function notifyRewardAmount(uint256 _amount) external override {
        if (!isRewardNotifier[msg.sender]) revert Staker__Unauthorized("not notifier", msg.sender);

        rewardPerTokenAccumulatedCheckpoint = rewardPerTokenAccumulated();

        if (block.timestamp >= rewardEndTime) {
            scaledRewardRate = (_amount * SCALE_FACTOR) / rewardDuration;
        } else {
            uint256 _remainingReward = scaledRewardRate * (rewardEndTime - block.timestamp);
            // slither-disable-next-line divide-before-multiply
            scaledRewardRate = (_remainingReward + _amount * SCALE_FACTOR) / rewardDuration;
        }

        rewardEndTime = block.timestamp + rewardDuration;
        lastCheckpointTime = block.timestamp;

        if (scaledRewardRate < SCALE_FACTOR) revert Staker__InvalidRewardRate();

        // USE STORAGE VARIABLE INSTEAD OF IMMUTABLE
        // slither-disable-next-line divide-before-multiply
        if ((scaledRewardRate * rewardDuration) > (getRewardToken().balanceOf(address(this)) * SCALE_FACTOR))
            revert Staker__InsufficientRewardBalance();

        emit RewardNotified(_amount, msg.sender);
    }



    /// @notice Compounds rewards by claiming them and immediately restaking them into the same deposit.
    /// @param _depositId The deposit identifier for which to compound rewards.
    /// @return compoundedAmount The amount of rewards that were compounded into the deposit.
    function compoundRewards(
        DepositIdentifier _depositId
    )
        external
        override
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, msg.sender)
        returns (uint256 compoundedAmount)
    {
        // USE STORAGE VARIABLES INSTEAD OF IMMUTABLE
        if (address(getRewardToken()) != address(getStakeToken())) {
            revert CompoundingNotSupported();
        }

        Deposit storage deposit = deposits[_depositId];

        address depositOwner = deposit.owner;
        address depositDelegatee = deposit.delegatee;

        if (deposit.claimer != msg.sender && depositOwner != msg.sender) {
            revert Staker__Unauthorized("not claimer or owner", msg.sender);
        }

        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 unclaimedAmount = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;
        require(unclaimedAmount > 0, ZeroOperation());

        ClaimFeeParameters memory feeParams = claimFeeParameters;
        uint256 fee = feeParams.feeAmount;

        if (unclaimedAmount < fee) {
            return 0;
        }

        compoundedAmount = unclaimedAmount - fee;

        uint256 newBalance = deposit.balance + compoundedAmount;
        uint256 newEarningPower = _updateEarningPower(deposit, newBalance);

        unchecked {
            totalStaked += compoundedAmount;
            depositorTotalStaked[depositOwner] += compoundedAmount;
        }

        deposit.balance = newBalance.toUint96();
        deposit.scaledUnclaimedRewardCheckpoint = 0;

        if (fee > 0) {
            SafeERC20.safeTransfer(getRewardToken(), feeParams.feeCollector, fee);
        }

        SafeERC20.safeTransfer(getStakeToken(), address(surrogates(depositDelegatee)), compoundedAmount);

        emit RewardCompounded(_depositId, msg.sender, compoundedAmount, newBalance, newEarningPower);

        _revertIfMinimumStakeAmountNotMet(_depositId);

        return compoundedAmount;
    }

    /// @notice Contributes unclaimed rewards to a user-specified allocation mechanism.
    /// @notice WARNING: The allocation mechanism address is not validated. Only contribute to trusted contracts.
    /// @notice Funds sent to malicious or incorrect addresses cannot be recovered.
    /// @dev This function allows deposit owners/claimers to contribute their unclaimed rewards to allocation mechanisms.
    /// @dev The function enforces strict balance checking to ensure the allocation mechanism correctly receives tokens.
    /// @dev Fees are deducted from the contribution amount if claim fees are configured.
    /// @dev SECURITY WARNING: This function approves and transfers tokens to the user-specified allocation mechanism.
    /// @dev Users MUST verify the allocation mechanism contract is legitimate and audited before contributing.
    /// @dev The protocol does NOT validate or restrict which contracts can receive contributions.
    /// @dev Contributing to a malicious or buggy contract will result in permanent loss of rewards.
    /// @param _depositId The deposit identifier for the staked amount.
    /// @param _allocationMechanismAddress The allocation mechanism address - USER MUST VERIFY THIS ADDRESS IS CORRECT AND TRUSTWORTHY.
    /// @param _votingDelegatee The address to receive voting power in the allocation mechanism.
    /// @param _amount The amount of reward tokens to contribute (before fees).
    /// @param _deadline Expiration timestamp for the EIP-712 signature.
    /// @param _v ECDSA signature parameter v.
    /// @param _r ECDSA signature parameter r.
    /// @param _s ECDSA signature parameter s.
    function contribute(
        DepositIdentifier _depositId,
        address _allocationMechanismAddress,
        address _votingDelegatee,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        public
        override
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(contributionWhitelist, msg.sender)
        returns (uint256 amountContributedToAllocationMechanism)
    {
        require(_amount > 0, ZeroOperation());
        _revertIfAddressZero(_allocationMechanismAddress);
        require(
            allocationMechanismWhitelist.isWhitelisted(_allocationMechanismAddress),
            NotWhitelisted(allocationMechanismWhitelist, _allocationMechanismAddress)
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
        if (fee == 0) {
            amountContributedToAllocationMechanism = _amount;
        } else {
            require(_amount >= fee, CantAfford(fee, _amount));
            amountContributedToAllocationMechanism = _amount - fee;
        }

        uint256 scaledAmountConsumed = _amount * SCALE_FACTOR;
        deposit.scaledUnclaimedRewardCheckpoint = deposit.scaledUnclaimedRewardCheckpoint - scaledAmountConsumed;

        emit RewardClaimed(_depositId, msg.sender, amountContributedToAllocationMechanism, deposit.earningPower);

        // USE STORAGE VARIABLE INSTEAD OF IMMUTABLE
        SafeERC20.forceApprove(getRewardToken(), _allocationMechanismAddress, amountContributedToAllocationMechanism);

        emit RewardContributed(
            _depositId,
            msg.sender,
            _allocationMechanismAddress,
            amountContributedToAllocationMechanism
        );

        TokenizedAllocationMechanism(_allocationMechanismAddress).signupWithSignature(
            _votingDelegatee,
            amountContributedToAllocationMechanism,
            _deadline,
            _v,
            _r,
            _s
        );

        SafeERC20.forceApprove(getRewardToken(), _allocationMechanismAddress, 0);

        if (fee > 0) {
            SafeERC20.safeTransfer(getRewardToken(), claimFeeParameters.feeCollector, fee);
        }

        return amountContributedToAllocationMechanism;
    }

    /// @notice Overrides to use storage variables and prevent pushing amount below minimum stake
    /// @notice Overrides to prevent claiming when the contract is paused.
    function _claimReward(
        DepositIdentifier _depositId,
        Deposit storage deposit,
        address _claimer
    ) internal override whenNotPaused nonReentrant returns (uint256) {
        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 _reward = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;
        uint256 _feeAmount = claimFeeParameters.feeAmount;

        // Intentionally reverts due to overflow if unclaimed rewards are less than fee.
        uint256 _payout = _reward - _feeAmount;
        if (_payout == 0) return 0;

        // retain sub-wei dust that would be left due to the precision loss
        // slither-disable-next-line divide-before-multiply
        deposit.scaledUnclaimedRewardCheckpoint = deposit.scaledUnclaimedRewardCheckpoint - (_reward * SCALE_FACTOR);

        uint256 _newEarningPower = earningPowerCalculator.getEarningPower(
            deposit.balance,
            deposit.owner,
            deposit.delegatee
        );

        emit RewardClaimed(_depositId, _claimer, _payout, _newEarningPower);

        totalEarningPower = _calculateTotalEarningPower(deposit.earningPower, _newEarningPower, totalEarningPower);
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            _newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );
        deposit.earningPower = _newEarningPower.toUint96();

        // USE STORAGE VARIABLE INSTEAD OF IMMUTABLE
        SafeERC20.safeTransfer(getRewardToken(), _claimer, _payout);
        if (_feeAmount > 0) {
            SafeERC20.safeTransfer(getRewardToken(), claimFeeParameters.feeCollector, _feeAmount);
        }

        _revertIfMinimumStakeAmountNotMet(_depositId);
        return _payout;
    }


}
