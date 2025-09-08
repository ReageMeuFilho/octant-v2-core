// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// === Base Imports ===
// Note: DelegationSurrogate is now imported via RegenStakerBase
import { RegenStakerBase, Staker, IERC20, DelegationSurrogate, IWhitelist, IEarningPowerCalculator } from "src/regen/RegenStakerBase.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// === Contract Header ===
/// @title RegenStakerWithoutDelegateSurrogateVotes
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Variant of RegenStakerBase for regular ERC20 tokens without delegation support.
/// @dev Eliminates surrogate pattern; tokens are held directly by this contract.
/// @dev DELEGATION LIMITATION: Delegatee is tracked for compatibility but has no effect on token delegation.
///
/// @dev VARIANT COMPARISON: (See RegenStaker.sol for the delegation variant)
/// ┌─────────────────────────────────────┬─────────────────┬──────────────────────────────────┐
/// │ Feature                             │ RegenStaker     │ RegenStakerWithoutDelegateSurro… │
/// ├─────────────────────────────────────┼─────────────────┼──────────────────────────────────┤
/// │ Delegation Support                  │ ✓ Full Support  │ ✗ No Support                     │
/// │ Surrogate Deployment                │ ✓ Per Delegatee │ ✗ Contract as Surrogate          │
/// │ Token Holder                        │ Surrogates      │ Contract Directly                │
/// │ Voting Capability                   │ ✓ via Surrogate │ ✗ Not Available                  │
/// │ Gas Cost (First Delegatee)          │ Higher          │ Lower                            │
/// │ Integration Complexity              │ Higher          │ Lower                            │
/// └─────────────────────────────────────┴─────────────────┴──────────────────────────────────┘
///
/// @dev VARIANT COMPARISON: See RegenStaker.sol for detailed comparison table.
///
/// @dev KEY DIFFERENCES FROM RegenStaker:
/// - No delegation support: delegatee parameter is informational only
/// - Lower gas costs: no surrogate contract deployment
/// - Simpler integration: contract holds tokens directly
/// - No voting capabilities through delegation
/// - Same security model: both variants use owner-centric whitelist authorization
///
/// @dev USE CASE: Choose this variant for simple ERC20 staking without governance requirements.
contract RegenStakerWithoutDelegateSurrogateVotes is RegenStakerBase {
    // === Custom Errors ===

    /// @notice Error thrown when attempting delegation operations that are not supported in this variant
    error DelegationNotSupported();

    // === Constructor ===
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
        uint128 _rewardDuration,
        uint256 _maxClaimFee,
        uint128 _minimumStakeAmount,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IWhitelist _allocationMechanismWhitelist
    )
        RegenStakerBase(
            _rewardsToken,
            _stakeToken,
            _earningPowerCalculator,
            _maxBumpTip,
            _admin,
            _rewardDuration,
            _maxClaimFee,
            _minimumStakeAmount,
            _stakerWhitelist,
            _contributionWhitelist,
            _allocationMechanismWhitelist,
            "RegenStakerWithoutDelegateSurrogateVotes"
        )
    {}

    // === Overridden Functions ===

    /// @notice Validates sufficient reward token balance for all token scenarios in this variant
    /// @dev Overrides base to include totalStaked for same-token scenarios since stakes are held in main contract
    /// @param _amount The reward amount being added
    /// @return required The required balance including appropriate obligations
    function _validateRewardBalance(uint256 _amount) internal view override returns (uint256 required) {
        uint256 currentBalance = REWARD_TOKEN.balanceOf(address(this));

        if (address(REWARD_TOKEN) == address(STAKE_TOKEN)) {
            // Same-token scenario: stakes ARE in main contract, so include totalStaked
            // Accounting: totalStaked + totalRewards - totalClaimedRewards + newAmount
            required = totalStaked + totalRewards - totalClaimedRewards + _amount;
        } else {
            // Different-token scenario: stakes are separate, only track reward obligations
            // Accounting: totalRewards - totalClaimedRewards + newAmount
            required = totalRewards - totalClaimedRewards + _amount;
        }

        if (currentBalance < required) {
            revert InsufficientRewardBalance(currentBalance, required);
        }

        return required;
    }

    /// @inheritdoc Staker
    /// @notice Returns this contract as the "surrogate" since we hold tokens directly
    /// @dev ARCHITECTURE: This variant uses address(this) as surrogate to eliminate delegation complexity
    ///      while maintaining compatibility with base Staker contract logic. This allows reuse of all
    ///      base functionality without deploying separate surrogate contracts.
    /// @dev WARNING: Deviates from standard surrogate pattern. Always returns address(this).
    ///      Integrators expecting separate surrogate contracts will fail. Do not assume external
    ///      surrogate contracts exist when integrating with this variant.
    function surrogates(address /* _delegatee */) public view override returns (DelegationSurrogate) {
        return DelegationSurrogate(address(this));
    }

    /// @inheritdoc Staker
    /// @notice Returns this contract as the "surrogate" - no separate contracts needed
    /// @dev SIMPLIFICATION: Eliminates need for complex token transfer overrides
    function _fetchOrDeploySurrogate(address /* _delegatee */) internal view override returns (DelegationSurrogate) {
        return DelegationSurrogate(address(this));
    }

    /// @inheritdoc Staker
    /// @notice Override to support withdrawals when this contract acts as its own surrogate
    /// @dev Since this contract uses address(this) as surrogate, use safeTransfer for contract-to-user paths.
    function _stakeTokenSafeTransferFrom(address _from, address _to, uint256 _value) internal override {
        // Use safeTransfer for withdrawals (contract -> user)
        if (_from == address(this)) {
            SafeERC20.safeTransfer(STAKE_TOKEN, _to, _value);
            return;
        }

        // Default behavior for deposits (user -> contract)
        super._stakeTokenSafeTransferFrom(_from, _to, _value);
    }

    /// @inheritdoc Staker
    /// @notice Delegation changes are not supported in this variant
    /// @dev Always reverts since this contract doesn't use delegation surrogates - always uses address(this)
    function alterDelegatee(DepositIdentifier, address) external pure override {
        revert DelegationNotSupported();
    }
}
