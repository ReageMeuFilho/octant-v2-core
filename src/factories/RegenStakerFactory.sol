// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CREATE3 } from "lib/solady/src/utils/CREATE3.sol";
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
        IEarningPowerCalculator earningPowerCalculator;
        uint256 maxBumpTip;
        uint256 maxClaimFee;
        uint256 minimumStakeAmount;
        uint256 rewardDuration;
    }

    event StakerDeploy(address indexed deployer, address indexed admin, address indexed stakerAddress, bytes32 salt);

    function createStaker(CreateStakerParams calldata p, bytes32 s, bytes calldata code) external returns (address a) {
        a = CREATE3.deployDeterministic(
            abi.encode(
                code,
                p.rewardsToken,
                p.stakeToken,
                p.admin,
                p.stakerWhitelist,
                p.contributionWhitelist,
                p.earningPowerCalculator,
                p.maxBumpTip,
                p.maxClaimFee,
                p.minimumStakeAmount,
                p.rewardDuration
            ),
            keccak256(abi.encodePacked(s, msg.sender))
        );
        emit StakerDeploy(msg.sender, p.admin, a, s);
    }

    function predictStakerAddress(bytes32 s) external view returns (address) {
        return CREATE3.predictDeterministicAddress(keccak256(abi.encodePacked(s, msg.sender)));
    }
}
