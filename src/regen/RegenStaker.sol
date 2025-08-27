// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// === Variant-Specific Imports ===
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { DelegationSurrogateVotes } from "staker/DelegationSurrogateVotes.sol";
import { IERC20Delegates } from "staker/interfaces/IERC20Delegates.sol";

// === Base Imports ===
import { RegenStakerBase, Staker, SafeERC20, IERC20, DelegationSurrogate, IWhitelist, IEarningPowerCalculator } from "src/regen/RegenStakerBase.sol";

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
        uint128 _rewardDuration,
        uint256 _maxClaimFee,
        uint128 _minimumStakeAmount,
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

    // === Events ===
    /// @notice Emitted when a new delegation surrogate is deployed
    /// @param delegatee The address that receives the voting power
    /// @param surrogate The address of the deployed surrogate contract
    event SurrogateDeployed(address indexed delegatee, address indexed surrogate);

    // === Overridden Functions ===

    /// @inheritdoc Staker
    function surrogates(address _delegatee) public view override returns (DelegationSurrogate) {
        return _surrogates[_delegatee];
    }

    /// @notice Predicts the address of a surrogate that would be deployed for a given delegatee
    /// @param _delegatee The address that will receive delegated voting power
    /// @return The predicted address of the surrogate contract
    /// @dev EIP-1014 (CREATE2): last 20 bytes of keccak256(0xff ++ deployer ++ salt ++ keccak256(init_code))
    function predictSurrogateAddress(address _delegatee) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_delegatee));
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(type(DelegationSurrogateVotes).creationCode, abi.encode(VOTING_TOKEN, _delegatee))
        );

        // EIP-1014: 0xff domain separator
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }

    /// @notice Gets the delegatee address for a given surrogate
    /// @param _surrogate The surrogate contract address
    /// @return The address that this surrogate delegates voting power to
    /// @dev Returns zero address if the surrogate doesn't delegate (invalid surrogate)
    function getDelegateeFromSurrogate(address _surrogate) external view returns (address) {
        return VOTING_TOKEN.delegates(_surrogate);
    }

    /// @inheritdoc Staker
    /// @dev GAS WARNING: First use of a new delegatee deploys a DelegationSurrogateVotes contract
    ///      costing ~250k-350k gas. Subsequent operations with the same delegatee reuse existing surrogate.
    ///      Consider pre-deploying surrogates for frequently used delegatees during low gas price periods.
    function _fetchOrDeploySurrogate(address _delegatee) internal override returns (DelegationSurrogate _surrogate) {
        _surrogate = _surrogates[_delegatee];
        if (address(_surrogate) == address(0)) {
            _surrogate = new DelegationSurrogateVotes{ salt: keccak256(abi.encodePacked(_delegatee)) }(
                VOTING_TOKEN,
                _delegatee
            );

            _surrogates[_delegatee] = _surrogate;
            emit SurrogateDeployed(_delegatee, address(_surrogate));
        }
    }
}
