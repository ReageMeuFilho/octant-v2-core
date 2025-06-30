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
import { Whitelist } from "src/utils/Whitelist.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";

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
/// @dev SCALE_FACTOR (1e36) is inherited from base Staker and used to minimize precision loss in reward calculations by scaling up values before division.
/// @dev Earning power is capped at uint96.max (~7.9e28) to prevent overflow in reward calculations while still supporting extremely large values.
/// @dev NO SURROGATES: This contract eliminates the surrogate pattern entirely - all tokens are held directly by this contract.
/// @dev PRECISION IMPLICATIONS: Variable reward durations affect calculation precision. The original Staker contract assumed a fixed
///      30-day duration for optimal precision. This contract allows 7-3000 days, providing flexibility at the cost of potential precision loss.
///      Shorter durations (especially < 30 days) can increase the margin of error in reward calculations by up to ~1% due to increased
///      reward rates amplifying rounding errors in scaled arithmetic operations. This is an intentional design trade-off favoring
///      operational flexibility over mathematical precision. For maximum precision, prefer longer reward durations (≥30 days).
/// @dev DELEGATION LIMITATION: This variant does not support delegation functionality since it works with regular ERC20 tokens.
///      The delegatee parameter is still tracked for compatibility but has no effect on token delegation.
/// @dev PERMIT SUPPORT: This variant supports EIP-2612 permit functionality when the token implements IERC20Permit.
///      If the token does not support permit, the permitAndStake functions will revert, but standard approve() + stake() flow works.
///      This provides flexibility for both permit-enabled and basic ERC20 tokens.
contract RegenStakerWithoutDelegateSurrogateVotes is
    Staker,
    StakerPermitAndStake,
    StakerOnBehalf,
    Pausable,
    ReentrancyGuard
{
    using SafeCast for uint256;

    /// @notice Minimum allowed reward duration. Values below 30 days may introduce precision loss up to ~1%.
    /// @dev The original Staker contract used a fixed 30-day duration. Allowing shorter durations trades precision for flexibility.
    uint256 public constant MIN_REWARD_DURATION = 7 days;

    /// @notice Current reward duration over which rewards are distributed.
    /// @dev This overrides the base Staker's fixed REWARD_DURATION constant. Shorter durations increase reward rates,
    ///      which can amplify rounding errors in the scaled arithmetic operations used for reward calculations.
    uint256 public rewardDuration;

    /// @notice Maximum allowed reward duration to prevent excessively long reward periods.
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

    /// @notice Constructor for the RegenStakerWithoutDelegateSurrogateVotes contract.
    /// @param _rewardsToken The token that will be used to reward contributors.
    /// @param _stakeToken The ERC20 token that will be used to stake (no delegation required).
    /// @param _earningPowerCalculator The earning power calculator.
    /// @param _maxBumpTip The maximum bump tip.
    /// @param _admin The address of the admin. TRUSTED.
    /// @param _rewardDuration The duration over which rewards are distributed.
    /// @param _maxClaimFee The maximum claim fee. You can set fees between 0 and _maxClaimFee. _maxClaimFee cannot be changed after deployment.
    /// @param _minimumStakeAmount The minimum stake amount.
    /// @param _stakerWhitelist The whitelist for stakers. Can be address(0) to disable whitelisting.
    /// @param _contributionWhitelist The whitelist for contributors. Can be address(0) to disable whitelisting.
    /// @param _allocationMechanismWhitelist The whitelist for allocation mechanisms.
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
        Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
        StakerPermitAndStake(IERC20Permit(address(_stakeToken)))
        StakerOnBehalf()
        EIP712("RegenStakerWithoutDelegateSurrogateVotes", "1")
    {
        _revertIfAddressZero(address(_rewardsToken));
        _revertIfAddressZero(address(_stakeToken));

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

    /// @inheritdoc Staker
    /// @notice Returns address(0) since this contract doesn't use surrogates
    function surrogates(address /* _delegatee */) public pure override returns (DelegationSurrogate) {
        return DelegationSurrogate(address(0));
    }

    /// @inheritdoc Staker
    /// @notice Returns address(0) since this contract doesn't use surrogates
    function _fetchOrDeploySurrogate(address /* _delegatee */) internal pure override returns (DelegationSurrogate) {
        return DelegationSurrogate(address(0));
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
    )
        internal
        override
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, _depositor)
        returns (DepositIdentifier _depositId)
    {
        require(_amount > 0, ZeroOperation());

        // Transfer tokens directly to this contract (no surrogate)
        SafeERC20.safeTransferFrom(STAKE_TOKEN, _depositor, address(this), _amount);

        // Create deposit without delegation surrogate
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
    ) internal override whenNotPaused nonReentrant onlyWhitelistedIfWhitelistIsSet(stakerWhitelist, deposit.owner) {
        require(_amount > 0, ZeroOperation());

        // Transfer tokens directly to this contract (no surrogate)
        // slither-disable-next-line arbitrary-send-erc20
        SafeERC20.safeTransferFrom(STAKE_TOKEN, deposit.owner, address(this), _amount);

        // Update deposit without delegation surrogate
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

        // Update deposit state
        _updateDepositForWithdraw(deposit, _depositId, _amount);

        // Transfer tokens directly from this contract (no surrogate)
        SafeERC20.safeTransfer(STAKE_TOKEN, deposit.owner, _amount);

        _revertIfMinimumStakeAmountNotMet(_depositId);
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

        totalStaked += compoundedAmount;
        depositorTotalStaked[depositOwner] += compoundedAmount;

        deposit.balance = newBalance.toUint96();
        deposit.scaledUnclaimedRewardCheckpoint = 0;

        if (fee > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, feeParams.feeCollector, fee);
        }

        // No surrogate transfer needed - tokens are already in this contract
        // The compounding just updates the deposit balance

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
        // Checks
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

        // Effects - Update state before external calls
        amountContributedToAllocationMechanism = _processContribution(_depositId, deposit, _amount);

        // Interactions - External calls
        _executeContribution(
            _depositId,
            _allocationMechanismAddress,
            _votingDelegatee,
            amountContributedToAllocationMechanism,
            _deadline,
            _v,
            _r,
            _s
        );

        return amountContributedToAllocationMechanism;
    }

    /// @notice Internal function to process contribution state changes (Effects phase)
    /// @param _depositId The deposit identifier
    /// @param deposit The deposit storage reference
    /// @param _amount The amount to contribute
    /// @return amountContributedToAllocationMechanism The amount after fees
    function _processContribution(
        DepositIdentifier _depositId,
        Deposit storage deposit,
        uint256 _amount
    ) internal returns (uint256 amountContributedToAllocationMechanism) {
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
    }

    /// @notice Internal function to execute external interactions (Interactions phase)
    /// @param _depositId The deposit identifier
    /// @param _allocationMechanismAddress The allocation mechanism address
    /// @param _votingDelegatee The voting delegatee address
    /// @param amountContributedToAllocationMechanism The amount to contribute after fees
    /// @param _deadline Signature deadline
    /// @param _v Signature parameter
    /// @param _r Signature parameter
    /// @param _s Signature parameter
    function _executeContribution(
        DepositIdentifier _depositId,
        address _allocationMechanismAddress,
        address _votingDelegatee,
        uint256 amountContributedToAllocationMechanism,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal {
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

        uint256 fee = claimFeeParameters.feeAmount;
        if (fee > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, claimFeeParameters.feeCollector, fee);
        }
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

    /// @notice Sets the reward duration for future reward notifications
    /// @param _rewardDuration The new reward duration in seconds
    /// @dev PRECISION WARNING: Shorter durations (< 30 days) may introduce calculation errors up to ~1%.
    ///      The original Staker contract was optimized for 30-day periods. Shorter durations create higher
    ///      reward rates that amplify rounding errors in fixed-point arithmetic. Consider this trade-off
    ///      between operational flexibility and mathematical precision when setting reward durations.
    function setRewardDuration(uint256 _rewardDuration) external {
        _revertIfNotAdmin();
        require(block.timestamp > rewardEndTime, CannotChangeRewardDurationDuringActiveReward());
        require(
            _rewardDuration >= MIN_REWARD_DURATION && _rewardDuration <= MAX_REWARD_DURATION,
            InvalidRewardDuration(_rewardDuration)
        );
        require(rewardDuration != _rewardDuration, NoOperation());

        emit RewardDurationSet(_rewardDuration);
        rewardDuration = _rewardDuration;
    }

    /// @inheritdoc Staker
    /// @notice Overrides to use the custom reward duration instead of the fixed 30-day constant
    /// @notice Changing the reward duration will not affect the rate of the rewards unless this function is called.
    /// @dev PRECISION CONSIDERATIONS: This function performs scaled arithmetic using the variable rewardDuration.
    ///      Shorter durations result in higher scaledRewardRate values, which can amplify rounding errors in
    ///      subsequent calculations. The margin of error is proportional to (30 days / rewardDuration) and can
    ///      reach ~1% for the minimum 7-day duration. This precision loss is an accepted trade-off for the
    ///      flexibility of variable reward periods.
    function notifyRewardAmount(uint256 _amount) external override {
        if (!isRewardNotifier[msg.sender]) revert Staker__Unauthorized("not notifier", msg.sender);

        rewardPerTokenAccumulatedCheckpoint = rewardPerTokenAccumulated();

        if (block.timestamp >= rewardEndTime) {
            // PRECISION SENSITIVE: Division by variable rewardDuration affects precision
            scaledRewardRate = (_amount * SCALE_FACTOR) / rewardDuration;
        } else {
            uint256 _remainingReward = scaledRewardRate * (rewardEndTime - block.timestamp);
            // slither-disable-next-line divide-before-multiply
            // PRECISION SENSITIVE: Division by variable rewardDuration affects precision
            scaledRewardRate = (_remainingReward + _amount * SCALE_FACTOR) / rewardDuration;
        }

        rewardEndTime = block.timestamp + rewardDuration;
        lastCheckpointTime = block.timestamp;

        if (scaledRewardRate < SCALE_FACTOR) revert Staker__InvalidRewardRate();

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
