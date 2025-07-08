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
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { Staker, SafeCast, SafeERC20, IERC20 } from "staker/Staker.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { StakerPermitAndStake } from "staker/extensions/StakerPermitAndStake.sol";
import { DelegationSurrogate } from "staker/DelegationSurrogate.sol";
import { DelegationSurrogateVotes } from "staker/DelegationSurrogateVotes.sol";
import { IERC20Delegates } from "staker/interfaces/IERC20Delegates.sol";

// Local Imports
import { RegenStakerShared } from "src/regen/RegenStakerShared.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";

/// @title RegenStaker
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This contract is an extended version of the Staker contract by [ScopeLift](https://scopelift.co).
/// @notice This variant supports ERC20 tokens that implement delegation functionality via IERC20Staking.
/// @notice The reward duration can be configured by the admin, overriding the base Staker's constant value.
/// @notice You can tax the rewards with a claim fee. If you don't want rewards to be taxable, set MAX_CLAIM_FEE to 0.
/// @notice Earning power needs to be updated after deposit amount changes. Some changes are automatically triggering the update.
/// @notice Earning power is updated via bumpEarningPower externally. This action is incentivized with a tip. Use maxBumpTip to set the maximum tip.
/// @notice The admin can adjust the minimum stake amount. Existing deposits below a newly set threshold remain valid
///         but will be restricted from certain operations (partial withdraw, stake increase below threshold) until brought above the threshold.
/// @dev This contract uses DelegationSurrogateVotes (not basic DelegationSurrogate) to support voting functionality for IERC20Staking tokens.
/// @dev PRECISION IMPLICATIONS: Variable reward durations affect calculation precision. The original Staker contract assumed a fixed
///      30-day duration for optimal precision. This contract allows 7-3000 days, providing flexibility at the cost of potential precision loss.
///      Shorter durations (especially < 30 days) can increase the margin of error in reward calculations by up to ~1% due to increased
///      reward rates amplifying rounding errors in scaled arithmetic operations. This is an intentional design trade-off favoring
///      operational flexibility over mathematical precision. For maximum precision, prefer longer reward durations (≥30 days).
contract RegenStaker is StakerPermitAndStake, StakerOnBehalf, Pausable, ReentrancyGuard {
    using SafeCast for uint256;
    using RegenStakerShared for RegenStakerShared.SharedState;

    // Shared state variables
    RegenStakerShared.SharedState private sharedState;

    // Surrogate tracking
    mapping(address => DelegationSurrogate) private _surrogates;
    IERC20Delegates public immutable VOTING_TOKEN;

    // Events from shared library
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

    // Errors from shared library
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

    // Shared state getters
    function rewardDuration() external view returns (uint256) {
        return sharedState.rewardDuration;
    }

    function stakerWhitelist() external view returns (IWhitelist) {
        return sharedState.stakerWhitelist;
    }

    function contributionWhitelist() external view returns (IWhitelist) {
        return sharedState.contributionWhitelist;
    }

    function allocationMechanismWhitelist() external view returns (IWhitelist) {
        return sharedState.allocationMechanismWhitelist;
    }

    function minimumStakeAmount() external view returns (uint256) {
        return sharedState.minimumStakeAmount;
    }

    modifier onlyWhitelistedIfWhitelistIsSet(IWhitelist _whitelist, address _user) {
        RegenStakerShared.checkWhitelisted(_whitelist, _user);
        _;
    }

    /// @notice Constructor for the RegenStaker contract.
    /// @param _rewardsToken The token that will be used to reward contributors.
    /// @param _stakeToken The token that will be used to stake (must implement both IERC20Staking and IERC20Permit).
    /// @param _earningPowerCalculator The earning power calculator.
    /// @param _maxBumpTip The maximum bump tip.
    /// @param _admin The address of the admin. TRUSTED.
    /// @param _rewardDuration The duration over which rewards are distributed.
    /// @param _maxClaimFee The maximum claim fee. You can set fees between 0 and _maxClaimFee. _maxClaimFee cannot be changed after deployment.
    /// @param _minimumStakeAmount The minimum stake amount.
    /// @param _stakerWhitelist The whitelist for stakers. Can be address(0) to disable whitelisting.
    /// @param _contributionWhitelist The whitelist for contributors. Can be address(0) to disable whitelisting.
    /// @param _allocationMechanismWhitelist The whitelist for allocation mechanisms. SECURITY CRITICAL.
    ///      Only audited and trusted allocation mechanisms should be whitelisted.
    ///      Users contribute funds to these mechanisms and may lose funds if mechanisms are malicious.
    constructor(
        IERC20 _rewardsToken,
        IERC20Staking _stakeToken,
        IEarningPowerCalculator _earningPowerCalculator,
        uint256 _maxBumpTip,
        address _admin,
        uint256 _rewardDuration,
        uint256 _maxClaimFee,
        uint256 _minimumStakeAmount,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IWhitelist _allocationMechanismWhitelist
    )
        StakerPermitAndStake(IERC20Permit(address(_stakeToken)))
        Staker(_rewardsToken, IERC20(address(_stakeToken)), _earningPowerCalculator, _maxBumpTip, _admin)
        EIP712("RegenStaker", "1")
    {
        MAX_CLAIM_FEE = _maxClaimFee;
        _setClaimFeeParameters(ClaimFeeParameters({ feeAmount: 0, feeCollector: address(0) }));
        VOTING_TOKEN = IERC20Delegates(address(_stakeToken));

        // Initialize shared state
        RegenStakerShared.initializeSharedState(
            sharedState,
            _rewardDuration,
            _minimumStakeAmount,
            _stakerWhitelist,
            _contributionWhitelist,
            _allocationMechanismWhitelist
        );
    }

    /// @notice Override function to return surrogate for a delegatee
    function surrogates(address _delegatee) public view override returns (DelegationSurrogate) {
        return _surrogates[_delegatee];
    }

    /// @notice Implementation of abstract function from Staker to fetch or deploy surrogate
    function _fetchOrDeploySurrogate(address _delegatee) internal override returns (DelegationSurrogate _surrogate) {
        _surrogate = _surrogates[_delegatee];
        if (address(_surrogate) == address(0)) {
            _surrogate = new DelegationSurrogateVotes(VOTING_TOKEN, _delegatee);
            _surrogates[_delegatee] = _surrogate;
        }
    }

    /// @notice Transfers tokens to delegation surrogate during compound rewards
    function _transferForCompound(address _delegatee, uint256 _amount) internal {
        SafeERC20.safeTransfer(STAKE_TOKEN, address(_surrogates[_delegatee]), _amount);
    }

    /// @notice Sets the reward duration for future reward notifications
    /// @dev PRECISION WARNING: Shorter durations (< 30 days) may introduce calculation errors up to ~1%.
    /// @dev GAS IMPLICATIONS: Shorter reward durations may result in higher gas costs for certain
    ///      operations due to more frequent reward rate calculations. Consider gas costs when
    ///      selecting reward durations.
    /// @param _rewardDuration New reward duration in seconds (7 days minimum, 3000 days maximum)
    function setRewardDuration(uint256 _rewardDuration) external {
        _revertIfNotAdmin();
        require(block.timestamp > rewardEndTime, CannotChangeRewardDurationDuringActiveReward());
        require(
            _rewardDuration >= RegenStakerShared.MIN_REWARD_DURATION &&
                _rewardDuration <= RegenStakerShared.MAX_REWARD_DURATION,
            InvalidRewardDuration(_rewardDuration)
        );
        require(sharedState.rewardDuration != _rewardDuration, NoOperation());

        emit RewardDurationSet(_rewardDuration);
        sharedState.rewardDuration = _rewardDuration;
    }

    /// @notice Overrides to use the custom reward duration instead of the fixed 30-day constant
    function notifyRewardAmount(uint256 _amount) external override {
        if (!isRewardNotifier[msg.sender]) revert Staker__Unauthorized("not notifier", msg.sender);

        rewardPerTokenAccumulatedCheckpoint = rewardPerTokenAccumulated();

        uint256 totalRewards;
        if (block.timestamp >= rewardEndTime) {
            scaledRewardRate = (_amount * SCALE_FACTOR) / sharedState.rewardDuration;
            totalRewards = _amount * SCALE_FACTOR;
        } else {
            uint256 _remainingReward = scaledRewardRate * (rewardEndTime - block.timestamp);
            scaledRewardRate = (_remainingReward + _amount * SCALE_FACTOR) / sharedState.rewardDuration;
            totalRewards = _remainingReward + _amount * SCALE_FACTOR;
        }

        rewardEndTime = block.timestamp + sharedState.rewardDuration;
        lastCheckpointTime = block.timestamp;

        if (scaledRewardRate < SCALE_FACTOR) revert Staker__InvalidRewardRate();

        // Avoid "divide before multiply" by restructuring the balance check
        if (totalRewards > (REWARD_TOKEN.balanceOf(address(this)) * SCALE_FACTOR))
            revert Staker__InsufficientRewardBalance();

        emit RewardNotified(_amount, msg.sender);
    }

    /// @notice Sets the whitelist for stakers (who can stake tokens)
    /// @dev ACCESS CONTROL: Use address(0) to disable whitelisting and allow all addresses.
    /// @dev OPERATIONAL IMPACT: Affects all stake and stakeMore operations immediately.
    /// @dev GRANDFATHERING: Existing stakers can continue operations regardless of new whitelist.
    /// @param _stakerWhitelist New staker whitelist contract (address(0) = no restrictions)
    function setStakerWhitelist(IWhitelist _stakerWhitelist) external {
        require(sharedState.stakerWhitelist != _stakerWhitelist, NoOperation());
        _revertIfNotAdmin();
        emit StakerWhitelistSet(_stakerWhitelist);
        sharedState.stakerWhitelist = _stakerWhitelist;
    }

    /// @notice Sets the whitelist for contributors (who can contribute rewards)
    /// @dev ACCESS CONTROL: Use address(0) to disable whitelisting and allow all addresses.
    /// @dev OPERATIONAL IMPACT: Affects all contribute operations immediately.
    /// @dev GRANDFATHERING: Existing contributors can continue operations regardless of new whitelist.
    /// @param _contributionWhitelist New contribution whitelist contract (address(0) = no restrictions)
    function setContributionWhitelist(IWhitelist _contributionWhitelist) external {
        require(sharedState.contributionWhitelist != _contributionWhitelist, NoOperation());
        _revertIfNotAdmin();
        emit ContributionWhitelistSet(_contributionWhitelist);
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
    /// @param _allocationMechanismWhitelist New whitelist contract (cannot be address(0))
    function setAllocationMechanismWhitelist(IWhitelist _allocationMechanismWhitelist) external {
        require(sharedState.allocationMechanismWhitelist != _allocationMechanismWhitelist, NoOperation());
        require(
            address(_allocationMechanismWhitelist) != address(0),
            DisablingAllocationMechanismWhitelistNotAllowed()
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
    /// @param _minimumStakeAmount New minimum stake amount in wei (0 = no minimum)
    function setMinimumStakeAmount(uint256 _minimumStakeAmount) external {
        _revertIfNotAdmin();
        require(
            _minimumStakeAmount <= sharedState.minimumStakeAmount || block.timestamp >= rewardEndTime,
            CannotRaiseMinimumStakeAmountDuringActiveReward()
        );
        emit MinimumStakeAmountSet(_minimumStakeAmount);
        sharedState.minimumStakeAmount = _minimumStakeAmount;
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

    /// @notice Compounds rewards by claiming them and immediately restaking them into the same deposit
    /// @dev REQUIREMENT: Only works when REWARD_TOKEN == STAKE_TOKEN, otherwise reverts.
    /// @dev FEE HANDLING: Claim fees are deducted before compounding. Zero fee results in zero compound.
    /// @dev EARNING POWER: Compounding updates earning power based on new total balance.
    /// @dev GAS OPTIMIZATION: More efficient than separate claim + stake operations.
    /// @param _depositId The deposit to compound rewards for
    /// @return compoundedAmount Amount of rewards compounded (after fees)
    function compoundRewards(
        DepositIdentifier _depositId
    ) external whenNotPaused nonReentrant returns (uint256 compoundedAmount) {
        RegenStakerShared.checkWhitelisted(sharedState.stakerWhitelist, msg.sender);
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
        require(unclaimedAmount > 0, ZeroOperation());

        ClaimFeeParameters memory feeParams = claimFeeParameters;
        uint256 fee = feeParams.feeAmount;

        if (unclaimedAmount < fee) {
            return 0;
        }

        compoundedAmount = unclaimedAmount - fee;
        uint256 newBalance = deposit.balance + compoundedAmount;
        uint256 newEarningPower = earningPowerCalculator.getEarningPower(newBalance, deposit.owner, deposit.delegatee);

        totalEarningPower = _calculateTotalEarningPower(deposit.earningPower, newEarningPower, totalEarningPower);
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );

        totalStaked += compoundedAmount;
        depositorTotalStaked[depositOwner] += compoundedAmount;

        deposit.balance = newBalance.toUint96();
        deposit.earningPower = newEarningPower.toUint96();
        deposit.scaledUnclaimedRewardCheckpoint = 0;

        if (fee > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, feeParams.feeCollector, fee);
        }

        _transferForCompound(deposit.delegatee, compoundedAmount);

        emit RewardCompounded(_depositId, msg.sender, compoundedAmount, newBalance, newEarningPower);

        _revertIfMinimumStakeAmountNotMet(_depositId);

        return compoundedAmount;
    }

    /// @notice Contributes unclaimed rewards to a user-specified allocation mechanism
    /// @dev CONTRIBUTION RISK: Contributed funds are transferred to external allocation mechanisms
    ///      for public good causes. Malicious mechanisms may misappropriate funds for unintended
    ///      purposes rather than the stated public good cause.
    /// @dev TRUST MODEL: Allocation mechanisms must be whitelisted by protocol governance.
    ///      Only contribute to mechanisms you trust, as the protocol cannot recover funds
    ///      sent to malicious or buggy allocation mechanisms.
    /// @dev SECURITY: This function approves the exact contribution amount to the allocation
    ///      mechanism and immediately revokes approval after the call to limit exposure.
    /// @param _depositId The deposit identifier to contribute from
    /// @param _allocationMechanismAddress Whitelisted allocation mechanism to receive contribution
    /// @param _votingDelegatee Address to delegate voting power to in the allocation mechanism
    /// @param _amount Amount of unclaimed rewards to contribute (must be <= available rewards)
    /// @param _deadline Signature expiration timestamp
    /// @param _v Signature component v
    /// @param _r Signature component r
    /// @param _s Signature component s
    /// @return amountContributedToAllocationMechanism Actual amount contributed (after fees)
    function contribute(
        DepositIdentifier _depositId,
        address _allocationMechanismAddress,
        address _votingDelegatee,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public whenNotPaused nonReentrant returns (uint256 amountContributedToAllocationMechanism) {
        RegenStakerShared.checkWhitelisted(sharedState.contributionWhitelist, msg.sender);
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

        SafeERC20.forceApprove(REWARD_TOKEN, _allocationMechanismAddress, 0);

        if (fee > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, claimFeeParameters.feeCollector, fee);
        }

        return amountContributedToAllocationMechanism;
    }

    /// @notice Internal helper to check minimum stake amount
    function _revertIfMinimumStakeAmountNotMet(DepositIdentifier _depositId) internal view {
        Deposit storage deposit = deposits[_depositId];
        if (deposit.balance < sharedState.minimumStakeAmount && deposit.balance > 0) {
            revert MinimumStakeAmountNotMet(sharedState.minimumStakeAmount, deposit.balance);
        }
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
    ) internal override whenNotPaused nonReentrant returns (DepositIdentifier _depositId) {
        require(_amount > 0, ZeroOperation());
        RegenStakerShared.checkWhitelisted(sharedState.stakerWhitelist, _depositor);
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
    ) internal override whenNotPaused nonReentrant {
        require(_amount > 0, ZeroOperation());
        RegenStakerShared.checkWhitelisted(sharedState.stakerWhitelist, msg.sender);
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
}
