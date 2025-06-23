// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibClone } from "lib/solady/src/utils/LibClone.sol";
import { IERC20, IERC20Staking, IWhitelist, IEarningPowerCalculator } from "src/regen/RegenStaker.sol";
import { ProxyableRegenStaker } from "src/regen/ProxyableRegenStaker.sol";

/// @notice Minimal proxy factory for ProxyableRegenStaker deployment
/// @dev Uses standard EIP-1167 minimal proxy for gas-efficient deployment
/// @dev Each clone has ~45 bytes total (minimal proxy bytecode)
contract RegenStakerFactory {
    /// @notice The master ProxyableRegenStaker implementation contract
    address public immutable implementation;

    struct CreateStakerParams {
        IERC20 rewardsToken;
        IERC20Staking stakeToken;
        address admin;
        IWhitelist stakerWhitelist;
        IWhitelist contributionWhitelist;
        IWhitelist allocationMechanismWhitelist;
        IEarningPowerCalculator earningPowerCalculator;
        uint256 maxBumpTip;
        uint256 maxClaimFee;
        uint256 minimumStakeAmount;
        uint256 rewardDuration;
    }

    event StakerDeploy(address indexed deployer, address indexed admin, address indexed stakerAddress, bytes32 salt);

    /// @notice Constructor
    /// @param _implementation The master ProxyableRegenStaker implementation contract
    constructor(address _implementation) {
        implementation = _implementation;
    }

    /// @notice Creates a new RegenStaker proxy with deterministic address
    /// @param p The parameters for creating the staker
    /// @param s The salt for deterministic deployment
    /// @return a The address of the deployed proxy
    function createStaker(CreateStakerParams calldata p, bytes32 s) external returns (address a) {
        // Deploy minimal proxy (no immutable args needed with storage approach)
        a = LibClone.cloneDeterministic(implementation, keccak256(abi.encodePacked(s, msg.sender)));

        // Initialize the proxy with all parameters
        ProxyableRegenStaker(a).initialize(
            p.rewardsToken,
            p.stakeToken,
            p.maxClaimFee,
            p.admin,
            p.stakerWhitelist,
            p.contributionWhitelist,
            p.allocationMechanismWhitelist,
            p.earningPowerCalculator,
            p.maxBumpTip,
            p.minimumStakeAmount,
            p.rewardDuration
        );

        emit StakerDeploy(msg.sender, p.admin, a, s);
    }

    /// @notice Predicts the address of a staker proxy
    /// @param s The salt for deterministic deployment
    /// @return The predicted address
    function predictStakerAddress(bytes32 s) external view returns (address) {
        return
            LibClone.predictDeterministicAddress(
                implementation,
                keccak256(abi.encodePacked(s, msg.sender)),
                address(this)
            );
    }
}
