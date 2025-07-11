// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// OpenZeppelin Imports
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

// Staker Library Imports
import { Staker, IEarningPowerCalculator, SafeCast, SafeERC20, IERC20 } from "staker/Staker.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { StakerPermitAndStake } from "staker/extensions/StakerPermitAndStake.sol";
import { DelegationSurrogate } from "staker/DelegationSurrogate.sol";

// Local Imports
import { RegenStakerShared } from "src/regen/RegenStakerShared.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

/// @title RegenStakerWithoutDelegateSurrogateVotes
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This contract is an extended version of the Staker contract by [ScopeLift](https://scopelift.co) for regular ERC20 tokens.
/// @notice This variant supports ERC20 tokens that do not implement delegation functionality.
/// @notice Unlike the full RegenStaker, this contract does NOT use delegation surrogates - all tokens are held directly by this contract.
/// @notice The reward duration can be configured by the admin, overriding the base Staker's constant value.
/// @notice You can tax the rewards with a claim fee. If you don't want rewards to be taxable, set MAX_CLAIM_FEE to 0.
/// @notice Earning power needs to be updated after deposit amount changes. Some changes are automatically triggering the update.
/// @notice Earning power is updated via bumpEarningPower externally. This action is incentivized with a tip. Use maxBumpTip to set the maximum tip.
/// @notice The admin can adjust the minimum stake amount. Existing deposits below a newly set threshold remain valid
///         but will be restricted from certain operations (partial withdraw, stake increase below threshold) until brought above the threshold.
/// @dev NO SURROGATES: This contract eliminates the surrogate pattern entirely - all tokens are held directly by this contract.
/// @dev PRECISION IMPLICATIONS: Variable reward durations affect calculation precision. The original Staker contract assumed a fixed
///      30-day duration for optimal precision. This contract allows 7-3000 days, providing flexibility at the cost of potential precision loss.
///      Shorter durations (especially < 30 days) can increase the margin of error in reward calculations by up to ~1% due to increased
///      reward rates amplifying rounding errors in scaled arithmetic operations. This is an intentional design trade-off favoring
///      operational flexibility over mathematical precision. For maximum precision, prefer longer reward durations (≥30 days).
/// @dev DELEGATION LIMITATION: This variant does not support delegation functionality since it works with regular ERC20 tokens.
///      The delegatee parameter is still tracked for compatibility but has no effect on token delegation.
contract RegenStakerWithoutDelegateSurrogateVotes is StakerPermitAndStake, StakerOnBehalf, Pausable, ReentrancyGuard {
    using SafeCast for uint256;
    using RegenStakerShared for RegenStakerShared.SharedState;

    // Shared state variables
    RegenStakerShared.SharedState private sharedState;

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

    /// @notice Constructor for the RegenStakerWithoutDelegateSurrogateVotes contract.
    /// @param _rewardsToken The token that will be used to reward contributors.
    /// @param _stakeToken The ERC20 token that will be used to stake (must implement IERC20Permit for permit functionality).
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
        IERC20 _stakeToken,
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
        Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
        EIP712("RegenStakerWithoutDelegateSurrogateVotes", "1")
    {
        MAX_CLAIM_FEE = _maxClaimFee;
        _setClaimFeeParameters(ClaimFeeParameters({ feeAmount: 0, feeCollector: address(0) }));

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

    /// @inheritdoc Staker
    /// @notice Returns address(0) since this contract doesn't use surrogates
    /// @dev WITHOUT_DELEGATION: This variant eliminates delegation entirely for gas efficiency
    /// @dev COMPATIBILITY: Maintains interface compatibility with base Staker contract
    function surrogates(address /* _delegatee */) public pure override returns (DelegationSurrogate) {
        return DelegationSurrogate(address(0));
    }

    /// @inheritdoc Staker
    /// @notice Returns address(0) since this contract doesn't deploy surrogates
    /// @dev WITHOUT_DELEGATION: Surrogate deployment disabled for this variant
    /// @dev GAS_SAVINGS: Eliminates surrogate deployment costs
    function _fetchOrDeploySurrogate(address /* _delegatee */) internal pure override returns (DelegationSurrogate) {
        return DelegationSurrogate(address(0));
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
    /// @notice Overrides to handle tokens directly without delegation surrogates.
    function _stake(
        address _depositor,
        uint256 _amount,
        address _delegatee,
        address _claimer
    ) internal override whenNotPaused nonReentrant returns (DepositIdentifier _depositId) {
        require(_amount > 0, ZeroOperation());
        RegenStakerShared.checkWhitelisted(sharedState.stakerWhitelist, _depositor);

        SafeERC20.safeTransferFrom(STAKE_TOKEN, _depositor, address(this), _amount);

        _depositId = _createDeposit(_depositor, _amount, _delegatee, _claimer);

        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent staking 0 tokens.
    /// @notice Overrides to prevent pushing the amount below the minimum stake amount.
    /// @notice Overrides to prevent staking more when the contract is paused.
    /// @notice Overrides to prevent staking more if the staker is not whitelisted.
    /// @notice Overrides to handle tokens directly without delegation surrogates.
    function _stakeMore(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        uint256 _amount
    ) internal override whenNotPaused nonReentrant {
        require(_amount > 0, ZeroOperation());
        RegenStakerShared.checkWhitelisted(sharedState.stakerWhitelist, deposit.owner);

        // slither-disable-next-line arbitrary-send-erc20
        SafeERC20.safeTransferFrom(STAKE_TOKEN, deposit.owner, address(this), _amount);

        _updateDeposit(deposit, _depositId, _amount);

        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @inheritdoc Staker
    /// @notice Override to handle delegatee changes without surrogates (delegatee is tracked but has no effect)
    function _alterDelegatee(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        address _newDelegatee
    ) internal override nonReentrant {
        _revertIfAddressZero(_newDelegatee);
        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 _newEarningPower = earningPowerCalculator.getEarningPower(
            deposit.balance,
            deposit.owner,
            _newDelegatee
        );

        totalEarningPower = _calculateTotalEarningPower(deposit.earningPower, _newEarningPower, totalEarningPower);
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            _newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );

        emit DelegateeAltered(_depositId, deposit.delegatee, _newDelegatee, _newEarningPower);
        deposit.delegatee = _newDelegatee;
        deposit.earningPower = _newEarningPower.toUint96();

        // No token transfer needed since we don't use surrogates
    }

    /// @inheritdoc Staker
    /// @notice Overrides to prevent pushing the amount below the minimum stake amount.
    /// @notice Overrides to prevent withdrawing when the contract is paused.
    /// @notice Overrides to prevent withdrawing 0 tokens.
    /// @notice Overrides to handle tokens directly without delegation surrogates.
    function _withdraw(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        uint256 _amount
    ) internal override whenNotPaused nonReentrant {
        require(_amount > 0, ZeroOperation());

        _updateDepositForWithdraw(deposit, _depositId, _amount);

        SafeERC20.safeTransfer(STAKE_TOKEN, deposit.owner, _amount);

        _revertIfMinimumStakeAmountNotMet(_depositId);
    }

    /// @notice Contributes unclaimed rewards to a user-specified allocation mechanism
    /// @dev CONTRIBUTION RISK: Contributed funds are transferred to external allocation mechanisms
    ///      for public good causes. Malicious mechanisms may misappropriate funds for unintended
    ///      purposes rather than the stated public good cause.
    /// @dev TRUST MODEL: Allocation mechanisms must be whitelisted by protocol governance.
    ///      Only contribute to mechanisms you trust, as the protocol cannot recover funds
    ///      sent to malicious or buggy allocation mechanisms.
    /// @dev SECURITY: This function first withdraws rewards to the contributor, then the contributor
    ///      must have pre-approved the allocation mechanism to pull the tokens.
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

        uint256 currentAllowance = REWARD_TOKEN.allowance(msg.sender, _allocationMechanismAddress);
        require(
            currentAllowance >= amountContributedToAllocationMechanism,
            CantAfford(amountContributedToAllocationMechanism, currentAllowance)
        );

        uint256 scaledAmountConsumed = _amount * SCALE_FACTOR;
        deposit.scaledUnclaimedRewardCheckpoint = deposit.scaledUnclaimedRewardCheckpoint - scaledAmountConsumed;

        emit RewardClaimed(_depositId, msg.sender, amountContributedToAllocationMechanism, deposit.earningPower);

        // First withdraw rewards to the contributor
        SafeERC20.safeTransfer(REWARD_TOKEN, msg.sender, amountContributedToAllocationMechanism);

        emit RewardContributed(
            _depositId,
            msg.sender,
            _allocationMechanismAddress,
            amountContributedToAllocationMechanism
        );

        TokenizedAllocationMechanism(_allocationMechanismAddress).signupWithSignature(
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

        return amountContributedToAllocationMechanism;
    }

    /// @notice Internal helper to create a deposit without delegation surrogates
    /// @param _depositor The address making the deposit
    /// @param _amount The amount to stake
    /// @param _delegatee The delegatee address (tracked but not used for delegation)
    /// @param _claimer The claimer address
    /// @return _depositId The created deposit ID
    function _createDeposit(
        address _depositor,
        uint256 _amount,
        address _delegatee,
        address _claimer
    ) internal returns (DepositIdentifier _depositId) {
        _revertIfAddressZero(_delegatee);
        _revertIfAddressZero(_claimer);

        _checkpointGlobalReward();

        _depositId = _useDepositId();

        uint256 _earningPower = earningPowerCalculator.getEarningPower(_amount, _depositor, _delegatee);

        totalStaked += _amount;
        totalEarningPower += _earningPower;
        depositorTotalStaked[_depositor] += _amount;
        depositorTotalEarningPower[_depositor] += _earningPower;
        deposits[_depositId] = Deposit({
            balance: _amount.toUint96(),
            owner: _depositor,
            delegatee: _delegatee,
            claimer: _claimer,
            earningPower: _earningPower.toUint96(),
            rewardPerTokenCheckpoint: rewardPerTokenAccumulatedCheckpoint,
            scaledUnclaimedRewardCheckpoint: 0
        });

        emit StakeDeposited(_depositor, _depositId, _amount, _amount, _earningPower);
        emit ClaimerAltered(_depositId, address(0), _claimer, _earningPower);
        emit DelegateeAltered(_depositId, address(0), _delegatee, _earningPower);
    }

    /// @notice Internal helper to update a deposit for staking more without delegation surrogates
    /// @param deposit The deposit storage reference
    /// @param _depositId The deposit ID
    /// @param _amount The additional amount to stake
    function _updateDeposit(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount) internal {
        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 _newBalance = deposit.balance + _amount;
        uint256 _newEarningPower = earningPowerCalculator.getEarningPower(
            _newBalance,
            deposit.owner,
            deposit.delegatee
        );

        totalEarningPower = _calculateTotalEarningPower(deposit.earningPower, _newEarningPower, totalEarningPower);
        totalStaked += _amount;
        depositorTotalStaked[deposit.owner] += _amount;
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            _newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );
        deposit.earningPower = _newEarningPower.toUint96();
        deposit.balance = _newBalance.toUint96();

        emit StakeDeposited(deposit.owner, _depositId, _amount, _newBalance, _newEarningPower);
    }

    /// @notice Internal helper to update a deposit for withdrawal without delegation surrogates
    /// @param deposit The deposit storage reference
    /// @param _depositId The deposit ID
    /// @param _amount The amount to withdraw
    function _updateDepositForWithdraw(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        uint256 _amount
    ) internal {
        _checkpointGlobalReward();
        _checkpointReward(deposit);

        require(_amount <= deposit.balance, CantAfford(_amount, deposit.balance));

        uint256 _newBalance = deposit.balance - _amount;
        uint256 _newEarningPower = earningPowerCalculator.getEarningPower(
            _newBalance,
            deposit.owner,
            deposit.delegatee
        );

        totalEarningPower = _calculateTotalEarningPower(deposit.earningPower, _newEarningPower, totalEarningPower);
        totalStaked -= _amount;
        depositorTotalStaked[deposit.owner] -= _amount;
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            _newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );
        deposit.earningPower = _newEarningPower.toUint96();
        deposit.balance = _newBalance.toUint96();

        emit StakeWithdrawn(deposit.owner, _depositId, _amount, _newBalance, _newEarningPower);
    }

    /// @inheritdoc Staker
    /// @notice Override to handle claim rewards without surrogates
    function _claimReward(
        DepositIdentifier _depositId,
        Deposit storage deposit,
        address _claimer
    ) internal override whenNotPaused nonReentrant returns (uint256) {
        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 _scaledReward = deposit.scaledUnclaimedRewardCheckpoint;
        uint256 _reward = _scaledReward / SCALE_FACTOR;
        // Intentionally reverts due to overflow if unclaimed rewards are less than fee.
        uint256 _payout = _reward - claimFeeParameters.feeAmount;
        if (_payout == 0) return 0;

        // Use the original scaled amount to avoid precision loss from divide-before-multiply
        deposit.scaledUnclaimedRewardCheckpoint = deposit.scaledUnclaimedRewardCheckpoint - _scaledReward;

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

        SafeERC20.safeTransfer(REWARD_TOKEN, _claimer, _payout);
        if (claimFeeParameters.feeAmount > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, claimFeeParameters.feeCollector, claimFeeParameters.feeAmount);
        }
        return _payout;
    }

    /// @inheritdoc Staker
    /// @notice Override to handle claimer changes without surrogates
    function _alterClaimer(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        address _newClaimer
    ) internal override nonReentrant {
        _revertIfAddressZero(_newClaimer);
        _checkpointGlobalReward();
        _checkpointReward(deposit);

        // Updating the earning power here is not strictly necessary, but if the user is touching their
        // deposit anyway, it seems reasonable to make sure their earning power is up to date.
        uint256 _newEarningPower = earningPowerCalculator.getEarningPower(
            deposit.balance,
            deposit.owner,
            deposit.delegatee
        );
        totalEarningPower = _calculateTotalEarningPower(deposit.earningPower, _newEarningPower, totalEarningPower);
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            _newEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );

        deposit.earningPower = _newEarningPower.toUint96();

        emit ClaimerAltered(_depositId, deposit.claimer, _newClaimer, _newEarningPower);
        deposit.claimer = _newClaimer;
    }
}
