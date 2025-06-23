// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// OpenZeppelin Imports
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Staker Library Imports
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { Staker, IEarningPowerCalculator, SafeCast, SafeERC20, IERC20 } from "staker/Staker.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { StakerDelegateSurrogateVotes } from "staker/extensions/StakerDelegateSurrogateVotes.sol";
import { StakerPermitAndStake } from "staker/extensions/StakerPermitAndStake.sol";

// Local Imports
import { Whitelist } from "src/utils/Whitelist.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";

/// @title RegenStaker
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This contract is an extended version of the Staker contract by [ScopeLift](https://scopelift.co).
/// @notice The reward duration can be configured by the admin, overriding the base Staker's constant value.
/// @notice You can tax the rewards with a claim fee. If you don't want rewards to be taxable, set MAX_CLAIM_FEE to 0.
/// @notice Earning power needs to be updated after deposit amount changes. Some changes are automatically triggering the update.
/// @notice Earning power is updated via bumpEarningPower externally. This action is incentivized with a tip. Use maxBumpTip to set the maximum tip.
/// @notice The admin can adjust the minimum stake amount. Existing deposits below a newly set threshold remain valid
///         but will be restricted from certain operations (partial withdraw, stake increase below threshold) until brought above the threshold.
/// @dev SCALE_FACTOR (1e36) is inherited from base Staker and used to minimize precision loss in reward calculations by scaling up values before division.
/// @dev Earning power is capped at uint96.max (~7.9e28) to prevent overflow in reward calculations while still supporting extremely large values.
/// @dev This contract uses the surrogate pattern from base Staker: tokens are transferred to surrogate contracts that delegate voting power to the designated delegatee.
contract RegenStaker is
    Staker,
    StakerDelegateSurrogateVotes,
    StakerPermitAndStake,
    StakerOnBehalf,
    Pausable,
    ReentrancyGuard
{
    using SafeCast for uint256;

    uint256 public constant MIN_REWARD_DURATION = 7 days;
    uint256 public rewardDuration;
    uint256 public constant MAX_REWARD_DURATION = 3000 days;

    IWhitelist public stakerWhitelist;
    IWhitelist public contributionWhitelist;
    IWhitelist public allocationMechanismWhitelist;

    uint256 public minimumStakeAmount = 0;

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

    modifier onlyWhitelistedIfWhitelistIsSet(IWhitelist _whitelist, address _user) {
        if (_whitelist != IWhitelist(address(0)) && !_whitelist.isWhitelisted(_user)) {
            revert NotWhitelisted(_whitelist, _user);
        }
        _;
    }

    /// @notice Constructor for the RegenStaker contract.
    /// @param _rewardsToken The token that will be used to reward contributors.
    /// @param _stakeToken The token that will be used to stake.
    /// @param _admin The address of the admin. TRUSTED.
    /// @param _stakerWhitelist The whitelist for stakers. Can be address(0) to disable whitelisting.
    /// @param _contributionWhitelist The whitelist for contributors. Can be address(0) to disable whitelisting.
    /// @param _allocationMechanismWhitelist The whitelist for allocation mechanisms.
    /// @param _earningPowerCalculator The earning power calculator.
    /// @param _maxBumpTip The maximum bump tip.
    /// @param _maxClaimFee The maximum claim fee. You can set fees between 0 and _maxClaimFee. _maxClaimFee cannot be changed after deployment.
    /// @param _rewardDuration The duration over which rewards are distributed.
    constructor(
        IERC20 _rewardsToken,
        IERC20Staking _stakeToken,
        address _admin,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IWhitelist _allocationMechanismWhitelist,
        IEarningPowerCalculator _earningPowerCalculator,
        uint256 _maxBumpTip,
        uint256 _maxClaimFee,
        uint256 _minimumStakeAmount,
        uint256 _rewardDuration
    )
        Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
        StakerPermitAndStake(_stakeToken)
        StakerDelegateSurrogateVotes(_stakeToken)
        EIP712("RegenStaker", "1")
    {
        require(
            _rewardDuration >= MIN_REWARD_DURATION && _rewardDuration <= MAX_REWARD_DURATION,
            InvalidRewardDuration(_rewardDuration)
        );
        rewardDuration = _rewardDuration;
        emit RewardDurationSet(_rewardDuration);

        stakerWhitelist = _stakerWhitelist;
        contributionWhitelist = _contributionWhitelist;
        allocationMechanismWhitelist = _allocationMechanismWhitelist;

        MAX_CLAIM_FEE = _maxClaimFee;
        _setClaimFeeParameters(ClaimFeeParameters({ feeAmount: 0, feeCollector: address(0) }));
        minimumStakeAmount = _minimumStakeAmount;
    }

    /// @notice Sets the reward duration for future reward notifications
    /// @param _rewardDuration The new reward duration in seconds
    function setRewardDuration(uint256 _rewardDuration) external {
        _revertIfNotAdmin();
        require(block.timestamp > rewardEndTime, CannotChangeRewardDurationDuringActiveReward());
        require(
            _rewardDuration >= MIN_REWARD_DURATION && _rewardDuration <= MAX_REWARD_DURATION,
            InvalidRewardDuration(_rewardDuration)
        );

        emit RewardDurationSet(_rewardDuration);
        rewardDuration = _rewardDuration;
    }

    /// @inheritdoc Staker
    /// @notice Overrides to use the custom reward duration
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

        if ((scaledRewardRate / SCALE_FACTOR) == 0) revert Staker__InvalidRewardRate();

        // slither-disable-next-line divide-before-multiply
        if ((scaledRewardRate * rewardDuration) > (REWARD_TOKEN.balanceOf(address(this)) * SCALE_FACTOR))
            revert Staker__InsufficientRewardBalance();

        emit RewardNotified(_amount, msg.sender);
    }

    /// @notice Sets the whitelist for the staker. If the whitelist is not set, the staking will be open to all users.
    /// @notice For admin use only.
    /// @param _stakerWhitelist The whitelist to set.
    function setStakerWhitelist(Whitelist _stakerWhitelist) external {
        require(stakerWhitelist != _stakerWhitelist, NoOperation());
        _revertIfNotAdmin();
        emit StakerWhitelistSet(_stakerWhitelist);
        stakerWhitelist = _stakerWhitelist;
    }

    /// @notice Sets the whitelist for the contribution. If the whitelist is not set, the contribution will be open to all users.
    /// @notice For admin use only.
    /// @param _contributionWhitelist The whitelist to set.
    function setContributionWhitelist(Whitelist _contributionWhitelist) external {
        require(contributionWhitelist != _contributionWhitelist, NoOperation());
        _revertIfNotAdmin();
        emit ContributionWhitelistSet(_contributionWhitelist);
        contributionWhitelist = _contributionWhitelist;
    }

    /// @notice Sets the whitelist for the allocation mechanism. If the whitelist is not set, the allocation mechanism will be open to all users.
    /// @notice For admin use only.
    /// @param _allocationMechanismWhitelist The whitelist to set.
    function setAllocationMechanismWhitelist(Whitelist _allocationMechanismWhitelist) external {
        require(allocationMechanismWhitelist != _allocationMechanismWhitelist, NoOperation());
        require(
            address(_allocationMechanismWhitelist) != address(0),
            DisablingAllocationMechanismWhitelistNotAllowed()
        );
        _revertIfNotAdmin();
        emit AllocationMechanismWhitelistSet(_allocationMechanismWhitelist);
        allocationMechanismWhitelist = _allocationMechanismWhitelist;
    }

    /// @notice Sets the minimum stake amount.
    /// @notice Existing deposits that fall below a newly set threshold are grandfathered and remain valid,
    ///         but will be restricted from withdraw and stakeMore operations until brought above the threshold.
    /// @notice For admin use only.
    /// @param _minimumStakeAmount The minimum stake amount.
    function setMinimumStakeAmount(uint256 _minimumStakeAmount) external {
        _revertIfNotAdmin();
        require(
            _minimumStakeAmount <= minimumStakeAmount || block.timestamp >= rewardEndTime,
            CannotRaiseMinimumStakeAmountDuringActiveReward()
        );
        emit MinimumStakeAmountSet(_minimumStakeAmount);
        minimumStakeAmount = _minimumStakeAmount;
    }

    /// @notice Pauses the contract.
    /// @notice For admin use only.
    function pause() external whenNotPaused {
        _revertIfNotAdmin();
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @notice For admin use only.
    function unpause() external whenPaused {
        _revertIfNotAdmin();
        _unpause();
    }

    /// @notice Compounds rewards by claiming them and immediately restaking them into the same deposit.
    /// @param _depositId The deposit identifier for which to compound rewards.
    /// @return compoundedAmount The amount of rewards that were compounded into the deposit.
    function compoundRewards(
        DepositIdentifier _depositId
    )
        external
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, msg.sender)
        returns (uint256 compoundedAmount)
    {
        if (address(REWARD_TOKEN) != address(STAKE_TOKEN)) {
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
            return 0; // Not enough to pay fee
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
            SafeERC20.safeTransfer(REWARD_TOKEN, feeParams.feeCollector, fee);
        }

        SafeERC20.safeTransfer(STAKE_TOKEN, address(surrogates(depositDelegatee)), compoundedAmount);

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
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(contributionWhitelist, msg.sender)
        returns (uint256 amountContributedToAllocationMechanism)
    {
        require(_amount > 0, ZeroOperation());
        _revertIfAddressZero(_allocationMechanismAddress);

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

        SafeERC20.forceApprove(REWARD_TOKEN, _allocationMechanismAddress, amountContributedToAllocationMechanism);

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

        if (fee > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, claimFeeParameters.feeCollector, fee);
        }

        return amountContributedToAllocationMechanism;
    }

    /// @notice Internal helper to update earning power for a deposit
    /// @param deposit The deposit to update
    /// @param newBalance The new balance to calculate earning power from
    /// @return newEarningPower The calculated new earning power
    function _updateEarningPower(
        Deposit storage deposit,
        uint256 newBalance
    ) private returns (uint256 newEarningPower) {
        newEarningPower = earningPowerCalculator.getEarningPower(newBalance, deposit.owner, deposit.delegatee);

        totalEarningPower = _calculateTotalEarningPower(deposit.earningPower, newEarningPower, totalEarningPower);

        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );

        deposit.earningPower = newEarningPower.toUint96();
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent staking 0 tokens.
    /// @notice Overrides to prevent staking below the minimum stake amount.
    /// @notice Overrides to prevent staking when the contract is paused.
    /// @notice Overrides to prevent staking if the staker is not whitelisted.
    function _stake(
        address _depositor,
        uint256 _amount,
        address _delegatee,
        address _claimer
    )
        internal
        override
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, _depositor)
        returns (DepositIdentifier _depositId)
    {
        require(_amount > 0, ZeroOperation());
        _depositId = super._stake(_depositor, _amount, _delegatee, _claimer);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent staking 0 tokens.
    /// @notice Overrides to prevent pushing the amount below the minimum stake amount.
    /// @notice Overrides to prevent staking more when the contract is paused.
    /// @notice Overrides to prevent staking more if the staker is not whitelisted.
    function _stakeMore(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        uint256 _amount
    ) internal override whenNotPaused nonReentrant onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, msg.sender) {
        require(_amount > 0, ZeroOperation());
        super._stakeMore(deposit, _depositId, _amount);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent pushing the amount below the minimum stake amount.
    /// @notice Overrides to prevent withdrawing when the contract is paused.
    /// @notice Overrides to prevent withdrawing 0 tokens.
    function _withdraw(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        uint256 _amount
    ) internal override whenNotPaused nonReentrant {
        require(_amount > 0, ZeroOperation());
        super._withdraw(deposit, _depositId, _amount);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent pushing the amount below the minimum stake amount.
    /// @notice Overrides to prevent claiming when the contract is paused.
    function _claimReward(
        DepositIdentifier _depositId,
        Deposit storage deposit,
        address _claimer
    ) internal override whenNotPaused nonReentrant returns (uint256) {
        uint256 _payout = super._claimReward(_depositId, deposit, _claimer);
        _revertIfMinimumStakeAmountNotMet(_depositId);
        return _payout;
    }

    /// @inheritdoc Staker
    /// @notice Overrides to add reentrancy protection.
    function _alterDelegatee(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        address _newDelegatee
    ) internal override nonReentrant {
        super._alterDelegatee(deposit, _depositId, _newDelegatee);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to add reentrancy protection.
    function _alterClaimer(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        address _newClaimer
    ) internal override nonReentrant {
        super._alterClaimer(deposit, _depositId, _newClaimer);
    }

    /// @notice Resets the allowance for a given token and spender to zero if it's currently non-zero.
    /// @dev This is a security measure to prevent allowance accumulation and ensure clean state before/after external calls.
    /// @dev Only resets if current allowance > 0 to save gas when already zero.
    /// @param token The token contract address.
    /// @param spender The spender address to reset allowance for.
    function _resetAllowance(address token, address spender) private {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance > 0) {
            SafeERC20.safeDecreaseAllowance(IERC20(token), spender, allowance);
        }
    }

    /// @notice Reverts if the deposit is below the minimum stake amount.
    /// @notice Deposits that become under-threshold due to admin raising the minimum are grandfathered
    ///         but cannot perform withdraw or stakeMore operations until brought above the threshold.
    /// @dev This creates a "grandfathering" effect: existing deposits remain valid but restricted.
    /// @dev Users can either withdraw everything (to 0) or add funds to meet the new minimum.
    /// @dev This prevents dust accumulation while preserving user rights to exit positions.
    /// @param _depositId The deposit identifier.
    function _revertIfMinimumStakeAmountNotMet(DepositIdentifier _depositId) internal view {
        Deposit storage deposit = deposits[_depositId];
        if (deposit.balance < minimumStakeAmount && deposit.balance > 0) {
            revert MinimumStakeAmountNotMet(minimumStakeAmount, deposit.balance);
        }
    }
}
