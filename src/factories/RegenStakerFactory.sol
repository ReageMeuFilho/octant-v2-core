// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CREATE3 } from "solady/utils/CREATE3.sol";
import { IERC20, IERC20Staking, IWhitelist, IEarningPowerCalculator } from "src/regen/RegenStaker.sol";

/// @notice Lightweight factory for RegenStaker deployment
/// @dev Users must provide RegenStaker bytecode to stay under EIP-170 size limit
contract RegenStakerFactory {
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

    function createStaker(
        CreateStakerParams calldata params,
        bytes32 salt,
        bytes calldata code
    ) external returns (address stakerAddress) {
        bytes memory constructorParams = abi.encode(
            params.rewardsToken,
            params.stakeToken,
            params.earningPowerCalculator,
            params.maxBumpTip,
            params.admin,
            params.rewardDuration,
            params.maxClaimFee,
            params.minimumStakeAmount,
            params.stakerWhitelist,
            params.contributionWhitelist,
            params.allocationMechanismWhitelist
        );

        stakerAddress = CREATE3.deployDeterministic(
            bytes.concat(code, constructorParams),
            keccak256(abi.encodePacked(salt, msg.sender))
        );
        emit StakerDeploy(msg.sender, params.admin, stakerAddress, salt);
    }

    function predictStakerAddress(bytes32 salt, address deployer) external view returns (address) {
        return CREATE3.predictDeterministicAddress(keccak256(abi.encodePacked(salt, deployer)));
    }
}
