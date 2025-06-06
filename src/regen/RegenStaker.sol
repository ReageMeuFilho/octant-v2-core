// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// OpenZeppelin Imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// Staker Library Imports
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { Staker } from "staker/Staker.sol";
import { StakerDelegateSurrogateVotes } from "staker/extensions/StakerDelegateSurrogateVotes.sol";
import { StakerPermitAndStake } from "staker/extensions/StakerPermitAndStake.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

// Local Imports
import { Whitelist } from "src/utils/Whitelist.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "src/regen/interfaces/IWhitelistedEarningPowerCalculator.sol";
import { IFundingRound } from "src/regen/interfaces/IFundingRound.sol";

// --- EIP-712 Specification for IFundingRound Implementations ---
// To ensure security against replay attacks for the `signup` method,
// any contract implementing the `IFundingRound` interface is expected to:
//
// 1. Be EIP-712 Compliant:
//    The `IFundingRound` contract should have its own EIP-712 domain separator.
//    This typically includes:
//    - name: The name of the funding round contract (e.g., "SpecificFundingRound").
//    - version: The version of the signing domain (e.g., "1").
//    - chainId: The chainId of the network where the contract is deployed.
//    - verifyingContract: The address of the `IFundingRound` contract itself.
//
// 2. Define a Typed Data Structure for Signup:
//    The data signed by the user (e.g., `deposit.owner`) must include a nonce.
//    Example structure (names can vary):
//    /*
//    struct FundingRoundSignupPayload {
//        uint256 assets;        // The amount of tokens for signup
//        address receiver;      // The address receiving voting power/shares
//        uint256 nonce;         // The signer's current nonce for this action
//    }
//    */
//
// 3. Define the TYPEHASH for this Structure:
//    This is `keccak256` of the EIP-712 struct definition string.
//    Example:
//    // bytes32 constant SIGNUP_PAYLOAD_TYPEHASH =
//    //     keccak256("FundingRoundSignupPayload(uint256 assets,address receiver,uint256 nonce)");
//
// 4. Manage Nonces:
//    The `IFundingRound` contract must maintain a nonce for each signer to prevent signature reuse.
//    Example:
//    // mapping(address => uint256) public userNonces;
//    Upon successful processing of a `signup` call, the `IFundingRound` contract must:
//    - Verify that the nonce in the signed payload matches `userNonces[signer]`.
//    - Increment `userNonces[signer]`.
//
// 5. Signature Verification:
//    The `signup` function will use `ecrecover` with the EIP-712 hash derived from
//    its domain separator, the `SIGNUP_PAYLOAD_TYPEHASH`, and the specific
//    `assets`, `receiver`, and expected `nonce` for the signer.

/// @title RegenStaker
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This contract is an extended version of the Staker contract by [ScopeLift](https://scopelift.co).
/// @notice The reward duration can be configured by the admin, overriding the base Staker's constant value.
/// @notice You can tax the rewards with a claim fee. If you don't want rewards to be taxable, set MAX_CLAIM_FEE to 0.
/// @notice Earning power needs to be updated after deposit amount changes. Some changes are automatically triggering the update.
/// @notice Earning power is updated via bumpEarningPower externally. This action is incentivized with a tip. Use maxBumpTip to set the maximum tip.
contract RegenStaker is Staker, StakerDelegateSurrogateVotes, StakerPermitAndStake, Pausable, ReentrancyGuard {
    using SafeCast for uint256;

    uint256 public constant MIN_REWARD_DURATION = 30 days;
    uint256 public constant MAX_REWARD_DURATION = 3000 days;

    IWhitelist public stakerWhitelist;
    IWhitelist public contributionWhitelist;
    uint256 public minimumStakeAmount = 0;
    uint256 public rewardDuration; // @notice The duration over which rewards are distributed. Overrides the base Staker's REWARD_DURATION.

    event StakerWhitelistSet(IWhitelist indexed whitelist);
    event ContributionWhitelistSet(IWhitelist indexed whitelist);
    event RewardDurationSet(uint256 newDuration);
    event RewardContributed(
        DepositIdentifier indexed depositId,
        address indexed contributor,
        address indexed fundingRound,
        uint256 amount
    );

    error NotWhitelisted(IWhitelist whitelist, address user);
    error CantAfford(uint256 requested, uint256 available);
    error FundingRoundSignUpFailed(address fundingRound, address contributor, uint256 amount, address votingDelegatee);
    error PreferencesAndPreferenceWeightsMustHaveTheSameLength();
    error InvalidNumberOfPreferences(uint256 actual, uint256 min, uint256 max);
    error MinimumStakeAmountNotMet(uint256 expected, uint256 actual);
    error InvalidRewardDuration(uint256 rewardDuration);
    error CannotChangeRewardDurationDuringActiveReward();

    modifier onlyWhitelistedIfWhitelistIsSet(IWhitelist _whitelist, address _user) {
        if (_whitelist != IWhitelist(address(0)) && !_whitelist.isWhitelisted(_user)) {
            revert NotWhitelisted(_whitelist, _user);
        }
        _;
    }

    // @notice Constructor for the RegenStaker contract.
    // @param _rewardsToken The token that will be used to reward contributors.
    // @param _stakeToken The token that will be used to stake.
    // @param _admin The address of the admin. TRUSTED.
    // @param _stakerWhitelist The whitelist for stakers. If passed as address(0), a new Whitelist contract will be deployed.
    // @param _contributionWhitelist The whitelist for contributors. If passed as address(0), a new Whitelist contract will be deployed.
    // @param _earningPowerCalculator The earning power calculator.
    // @param _maxBumpTip The maximum bump tip.
    // @param _maxClaimFee The maximum claim fee. You can set fees between 0 and _maxClaimFee. _maxClaimFee cannot be changed after deployment.
    // @param _rewardDuration The duration over which rewards are distributed. If 0, defaults to the base Staker's REWARD_DURATION (30 days).
    constructor(
        IERC20 _rewardsToken,
        IERC20Staking _stakeToken,
        address _admin,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IEarningPowerCalculator _earningPowerCalculator,
        uint256 _maxBumpTip,
        uint256 _maxClaimFee,
        uint256 _minimumStakeAmount,
        uint256 _rewardDuration
    )
        Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
        StakerPermitAndStake(_stakeToken)
        StakerDelegateSurrogateVotes(_stakeToken)
    {
        if (address(_stakerWhitelist) == address(0)) {
            stakerWhitelist = new Whitelist();
            Ownable(address(stakerWhitelist)).transferOwnership(_admin);
        } else {
            stakerWhitelist = _stakerWhitelist;
        }

        if (address(_contributionWhitelist) == address(0)) {
            contributionWhitelist = new Whitelist();
            Ownable(address(contributionWhitelist)).transferOwnership(_admin);
        } else {
            contributionWhitelist = _contributionWhitelist;
        }

        MAX_CLAIM_FEE = _maxClaimFee;
        _setClaimFeeParameters(ClaimFeeParameters({ feeAmount: 0, feeCollector: address(0) }));
        minimumStakeAmount = _minimumStakeAmount;

        if (_rewardDuration < MIN_REWARD_DURATION) rewardDuration = MIN_REWARD_DURATION;
        else if (_rewardDuration > MAX_REWARD_DURATION) rewardDuration = MAX_REWARD_DURATION;
        else rewardDuration = _rewardDuration;
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

        // We checkpoint the accumulator without updating the timestamp at which it was updated,
        // because that second operation will be done after updating the reward rate.
        rewardPerTokenAccumulatedCheckpoint = rewardPerTokenAccumulated();

        if (block.timestamp >= rewardEndTime) {
            scaledRewardRate = (_amount * SCALE_FACTOR) / rewardDuration;
        } else {
            uint256 _remainingReward = scaledRewardRate * (rewardEndTime - block.timestamp);
            scaledRewardRate = (_remainingReward + _amount * SCALE_FACTOR) / rewardDuration;
        }

        rewardEndTime = block.timestamp + rewardDuration;
        lastCheckpointTime = block.timestamp;

        if ((scaledRewardRate / SCALE_FACTOR) == 0) revert Staker__InvalidRewardRate();

        // This check cannot _guarantee_ sufficient rewards have been transferred to the contract,
        // because it cannot isolate the unclaimed rewards owed to stakers left in the balance. While
        // this check is useful for preventing degenerate cases, it is not sufficient. Therefore, it is
        // critical that only safe reward notifier contracts are approved to call this method by the
        // admin.
        if ((scaledRewardRate * rewardDuration) > (REWARD_TOKEN.balanceOf(address(this)) * SCALE_FACTOR))
            revert Staker__InsufficientRewardBalance();

        emit RewardNotified(_amount, msg.sender);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent staking below the minimum stake amount.
    /// @notice Overrides to prevent staking when the contract is paused.
    /// @notice Overrides to prevent staking if the staker is not whitelisted.
    function stake(
        uint256 amount,
        address delegatee
    )
        external
        override(Staker)
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, msg.sender)
        returns (DepositIdentifier _depositId)
    {
        _depositId = _stake(msg.sender, amount, delegatee, msg.sender);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent staking below the minimum stake amount.
    /// @notice Overrides to prevent staking when the contract is paused.
    /// @notice Overrides to prevent staking if the staker is not whitelisted.
    function stake(
        uint256 amount,
        address delegatee,
        address claimer
    )
        external
        override(Staker)
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, msg.sender)
        returns (DepositIdentifier _depositId)
    {
        _depositId = _stake(msg.sender, amount, delegatee, claimer);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    // @inheritdoc Staker
    /// @notice Overrides to prevent staking more below the minimum stake amount.
    /// @notice Overrides to prevent staking more when the contract is paused.
    /// @notice Overrides to prevent staking more if the claimer is not whitelisted.
    function stakeMore(
        DepositIdentifier _depositId,
        uint256 _amount
    ) external override whenNotPaused nonReentrant onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, msg.sender) {
        Deposit storage deposit = deposits[_depositId];

        _revertIfNotDepositOwner(deposit, msg.sender);
        _stakeMore(deposit, _depositId, _amount);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc StakerPermitAndStake
    /// @notice Overrides to prevent staking below the minimum stake amount.
    /// @notice Overrides to prevent staking when the contract is paused.
    /// @notice Overrides to prevent staking if the staker is not whitelisted.
    function permitAndStake(
        uint256 _amount,
        address _delegatee,
        address _claimer,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        external
        override
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, msg.sender)
        returns (DepositIdentifier _depositId)
    {
        try
            IERC20Permit(address(STAKE_TOKEN)).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s)
        {} catch {}
        _depositId = _stake(msg.sender, _amount, _delegatee, _claimer);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc StakerPermitAndStake
    /// @notice Overrides to prevent staking more below the minimum stake amount.
    /// @notice Overrides to prevent staking more when the contract is paused.
    /// @notice Overrides to prevent staking more if the staker is not whitelisted.
    function permitAndStakeMore(
        DepositIdentifier _depositId,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override whenNotPaused nonReentrant onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, msg.sender) {
        Deposit storage deposit = deposits[_depositId];
        _revertIfNotDepositOwner(deposit, msg.sender);

        try
            IERC20Permit(address(STAKE_TOKEN)).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s)
        {} catch {}
        _stakeMore(deposit, _depositId, _amount);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @notice Sets the whitelist for the staker. If the whitelist is not set, the staking will be open to all users.
    /// @notice For admin use only.
    /// @param _stakerWhitelist The whitelist to set.
    function setStakerWhitelist(Whitelist _stakerWhitelist) external {
        _revertIfNotAdmin();
        emit StakerWhitelistSet(_stakerWhitelist);
        stakerWhitelist = _stakerWhitelist;
    }

    /// @notice Sets the whitelist for the contribution. If the whitelist is not set, the contribution will be open to all users.
    /// @notice For admin use only.
    /// @param _contributionWhitelist The whitelist to set.
    function setContributionWhitelist(Whitelist _contributionWhitelist) external {
        _revertIfNotAdmin();
        emit ContributionWhitelistSet(_contributionWhitelist);
        contributionWhitelist = _contributionWhitelist;
    }

    /// @notice Sets the minimum stake amount.
    /// @notice For admin use only.
    /// @param _minimumStakeAmount The minimum stake amount.
    function setMinimumStakeAmount(uint256 _minimumStakeAmount) external {
        _revertIfNotAdmin();
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

    /// @notice Reverts if the deposit is below the minimum stake amount.
    /// @param _depositId The deposit identifier.
    function _revertIfMinimumStakeAmountNotMet(DepositIdentifier _depositId) internal view {
        Deposit storage deposit = deposits[_depositId];
        if (deposit.balance < minimumStakeAmount && deposit.balance > 0) {
            revert MinimumStakeAmountNotMet(minimumStakeAmount, deposit.balance);
        }
    }

    // @inheritdoc Staker
    /// @notice Overrides to prevent pushing the amount below the minimum stake amount.
    /// @notice Overrides to prevent withdrawing when the contract is paused.
    function withdraw(
        Staker.DepositIdentifier _depositId,
        uint256 _amount
    ) external override whenNotPaused nonReentrant {
        Deposit storage deposit = deposits[_depositId];
        _revertIfNotDepositOwner(deposit, msg.sender);
        _withdraw(deposit, _depositId, _amount);
        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent pushing the amount below the minimum stake amount.
    /// @notice Overrides to prevent claiming when the contract is paused.
    function claimReward(
        Staker.DepositIdentifier _depositId
    ) external override whenNotPaused nonReentrant returns (uint256) {
        Deposit storage deposit = deposits[_depositId];
        if (deposit.claimer != msg.sender && deposit.owner != msg.sender) {
            revert Staker__Unauthorized("not claimer or owner", msg.sender);
        }
        uint256 payout = _claimReward(_depositId, deposit, msg.sender);
        _revertIfMinimumStakeAmountNotMet(_depositId);
        return payout;
    }

    /// @notice Contributes to a funding round.
    /// @param _depositId The deposit identifier for the staked amount.
    /// @param _fundingRoundAddress The address of the funding round.
    /// @param _votingDelegatee The address of the delegatee to delegate voting power to.
    /// @param _amount The amount of reward tokens to contribute.
    /// @param _signature The signature for the IFundingRound.signup call.
    function contribute(
        DepositIdentifier _depositId,
        address _fundingRoundAddress,
        address _votingDelegatee,
        uint256 _amount,
        bytes32 _signature
    )
        public
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(contributionWhitelist, msg.sender)
        returns (uint256 amountContributedToFundingRound)
    {
        _revertIfAddressZero(_fundingRoundAddress);

        Deposit storage deposit = deposits[_depositId];

        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 unclaimedAmount = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;
        require(_amount <= unclaimedAmount, CantAfford(_amount, unclaimedAmount));

        uint256 fee = claimFeeParameters.feeAmount;
        if (fee == 0) {
            amountContributedToFundingRound = _amount;
        } else {
            require(_amount >= fee, CantAfford(fee, _amount));
            amountContributedToFundingRound = _amount - fee;
        }

        uint256 scaledAmountConsumed = _amount * SCALE_FACTOR;
        deposit.scaledUnclaimedRewardCheckpoint = deposit.scaledUnclaimedRewardCheckpoint - scaledAmountConsumed;

        uint256 newCalculatedEarningPower = earningPowerCalculator.getEarningPower(
            deposit.balance,
            deposit.owner,
            deposit.delegatee
        );

        totalEarningPower = _calculateTotalEarningPower(
            deposit.earningPower,
            newCalculatedEarningPower,
            totalEarningPower
        );
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            newCalculatedEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );
        deposit.earningPower = newCalculatedEarningPower.toUint96();

        emit RewardClaimed(_depositId, msg.sender, amountContributedToFundingRound, deposit.earningPower);

        if (fee > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, claimFeeParameters.feeCollector, fee);
        }

        SafeERC20.safeIncreaseAllowance(REWARD_TOKEN, _fundingRoundAddress, amountContributedToFundingRound);
        require(
            IFundingRound(_fundingRoundAddress).signup(amountContributedToFundingRound, _votingDelegatee, _signature) >
                0,
            FundingRoundSignUpFailed(
                _fundingRoundAddress,
                msg.sender,
                amountContributedToFundingRound,
                _votingDelegatee
            )
        );

        emit RewardContributed(_depositId, msg.sender, _fundingRoundAddress, amountContributedToFundingRound);

        return amountContributedToFundingRound;
    }
}
