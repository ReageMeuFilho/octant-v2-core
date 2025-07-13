// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// === Variant-Specific Imports ===
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { DelegationSurrogate } from "staker/DelegationSurrogate.sol";
import { DelegationSurrogateVotes } from "staker/DelegationSurrogateVotes.sol";
import { IERC20Delegates } from "staker/interfaces/IERC20Delegates.sol";

// === Base Imports ===
import { RegenStakerBase, Staker, SafeERC20, IERC20, IERC20Permit, IWhitelist, IEarningPowerCalculator } from "src/regen/RegenStakerBase.sol";

// === Contract Header ===
/// @title RegenStaker
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Variant of RegenStakerBase supporting ERC20 tokens with delegation via IERC20Staking.
/// @dev Uses DelegationSurrogateVotes to enable voting functionality for IERC20Staking tokens.
///
/// @dev VARIANT COMPARISON: (See RegenStakerWithoutDelegateSurrogateVotes.sol for the non-delegation variant)
/// ┌─────────────────────────────────────┬─────────────────┬──────────────────────────────────┐
/// │ Feature                             │ RegenStaker     │ RegenStakerWithoutDelegateSurro… │
/// ├─────────────────────────────────────┼─────────────────┼──────────────────────────────────┤
/// │ Delegation Support                  │ ✓ Full Support  │ ✗ No Support                     │
/// │ Surrogate Deployment                │ ✓ Per Delegatee │ ✗ Contract as Surrogate          │
/// │ Whitelist Authorization             │ deposit.owner   │ deposit.owner                    │
/// │ Token Holder                        │ Surrogates      │ Contract Directly                │
/// │ Voting Capability                   │ ✓ via Surrogate │ ✗ Not Available                  │
/// │ Gas Cost (First Delegatee)          │ Higher          │ Lower                            │
/// │ Integration Complexity              │ Higher          │ Lower                            │
/// └─────────────────────────────────────┴─────────────────┴──────────────────────────────────┘
///
/// @dev INTEGRATION GUIDANCE:
/// - Use RegenStaker for tokens requiring voting/governance participation
/// - Use RegenStakerWithoutDelegateSurrogateVotes for simple ERC20 staking
/// - Consider gas costs: delegation variant has higher initial costs for new delegatees
contract RegenStaker is RegenStakerBase {
    using SafeERC20 for IERC20;

    // === State Variables ===
    mapping(address => DelegationSurrogate) private _surrogates;
    IERC20Delegates public immutable VOTING_TOKEN;

    // === Constructor ===
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
        RegenStakerBase(
            _rewardsToken,
            IERC20(address(_stakeToken)),
            _earningPowerCalculator,
            _maxBumpTip,
            _admin,
            _rewardDuration,
            _maxClaimFee,
            _minimumStakeAmount,
            _stakerWhitelist,
            _contributionWhitelist,
            _allocationMechanismWhitelist,
            "RegenStaker"
        )
    {
        VOTING_TOKEN = IERC20Delegates(address(_stakeToken));
    }

    // === Overridden Functions ===
    /// @inheritdoc Staker
    function surrogates(address _delegatee) public view override returns (DelegationSurrogate) {
        return _surrogates[_delegatee];
    }

    /// @inheritdoc Staker
    /// @dev GAS WARNING: First use of a new delegatee deploys a DelegationSurrogateVotes contract
    ///      costing ~250k-350k gas. Subsequent operations with the same delegatee reuse existing surrogate.
    ///      Consider pre-deploying surrogates for frequently used delegatees during low gas price periods.
    function _fetchOrDeploySurrogate(address _delegatee) internal override returns (DelegationSurrogate _surrogate) {
        _surrogate = _surrogates[_delegatee];
        if (address(_surrogate) == address(0)) {
            _surrogate = new DelegationSurrogateVotes(VOTING_TOKEN, _delegatee);
            _surrogates[_delegatee] = _surrogate;
        }
    }

    /// @inheritdoc RegenStakerBase
    function _stake(
        address _depositor,
        uint256 _amount,
        address _delegatee,
        address _claimer
    ) internal override returns (DepositIdentifier _depositId) {
        return super._stake(_depositor, _amount, _delegatee, _claimer);
    }

    /// @inheritdoc RegenStakerBase
    function _stakeMore(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount) internal override {
        super._stakeMore(deposit, _depositId, _amount);
    }

    /// @inheritdoc RegenStakerBase
    function _withdraw(Deposit storage deposit, DepositIdentifier _depositId, uint256 _amount) internal override {
        super._withdraw(deposit, _depositId, _amount);
    }

    /// @inheritdoc RegenStakerBase
    function _alterDelegatee(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        address _newDelegatee
    ) internal override {
        super._alterDelegatee(deposit, _depositId, _newDelegatee);
    }

    /// @inheritdoc RegenStakerBase
    function _alterClaimer(
        Deposit storage deposit,
        DepositIdentifier _depositId,
        address _newClaimer
    ) internal override {
        super._alterClaimer(deposit, _depositId, _newClaimer);
    }

    /// @inheritdoc RegenStakerBase
    function _claimReward(
        DepositIdentifier _depositId,
        Deposit storage deposit,
        address _claimer
    ) internal override returns (uint256) {
        return super._claimReward(_depositId, deposit, _claimer);
    }

    /// @inheritdoc RegenStakerBase
    /// @dev For RegenStaker, we check deposit.owner for stakeMore operations using the owner-centric model.
    /// @dev OWNER-CENTRIC SECURITY: Both initial staking and stakeMore operations verify that the deposit owner
    ///      is whitelisted. This prevents whitelist circumvention through delegation or stakeOnBehalf calls.
    /// @dev DELEGATION COMPATIBILITY: Delegation still works - authorized delegates can perform stakeMore
    ///      operations, but the whitelist always checks the actual deposit owner, not the caller.
    /// @dev CONSISTENT MODEL: Both RegenStaker and RegenStakerWithoutDelegateSurrogateVotes now use
    ///      the same owner-centric authorization, ensuring consistent security across variants.
    /// @dev SECURITY BENEFIT: Only whitelisted users can own deposits and benefit from staking rewards,
    ///      eliminating potential whitelist bypass through delegation mechanisms.
    function _getStakeMoreWhitelistTarget(Deposit storage deposit) internal view override returns (address) {
        return deposit.owner;
    }

    /// @inheritdoc RegenStakerBase
    /// @dev Transfers tokens to the delegation surrogate for the delegatee
    function _transferForCompound(address _delegatee, uint256 _amount) internal override {
        DelegationSurrogate surrogate = _fetchOrDeploySurrogate(_delegatee);
        SafeERC20.safeTransfer(STAKE_TOKEN, address(surrogate), _amount);
    }

    /// @notice Indicates if this staker variant supports delegation
    /// @return true if delegation is supported
    function supportsDelegation() external pure returns (bool) {
        return true;
    }
}
