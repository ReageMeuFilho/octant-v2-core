// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CREATE3 } from "lib/solady/src/utils/CREATE3.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

/// @title RegenStakerFactory
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Factory for deploying RegenStaker contracts.
/// @dev This contract is used to deploy RegenStaker contracts.
contract RegenStakerFactory {
    struct StakerInfo {
        address deployerAddress;
        uint256 timestamp;
        address admin;
        address rewardsToken;
        address stakeToken;
        uint256 maxBumpTip;
        uint256 maxClaimFee;
        uint256 minimumStakeAmount;
    }

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

    mapping(address => StakerInfo[]) public stakers;

    event StakerDeploy(
        address indexed deployer,
        address indexed admin,
        address indexed stakerAddress,
        address rewardsToken,
        address stakeToken,
        uint256 maxBumpTip,
        uint256 maxClaimFee,
        uint256 minimumStakeAmount,
        bytes32 salt
    );

    /// @notice Creates a RegenStaker contract.
    /// @param _params The parameters for creating the RegenStaker contract.
    /// @param _salt The salt used to deploy the RegenStaker contract.
    /// @return stakerAddress The address of the RegenStaker contract.
    function createStaker(CreateStakerParams calldata _params, bytes32 _salt) external returns (address stakerAddress) {
        bytes memory bytecode = abi.encodePacked(
            type(RegenStaker).creationCode,
            abi.encode(
                _params.rewardsToken,
                _params.stakeToken,
                _params.admin,
                _params.stakerWhitelist,
                _params.contributionWhitelist,
                _params.earningPowerCalculator,
                _params.maxBumpTip,
                _params.maxClaimFee,
                _params.minimumStakeAmount,
                _params.rewardDuration
            )
        );

        stakerAddress = CREATE3.deployDeterministic(bytecode, keccak256(abi.encodePacked(_salt, msg.sender)));

        emit StakerDeploy(
            msg.sender,
            _params.admin,
            stakerAddress,
            address(_params.rewardsToken),
            address(_params.stakeToken),
            _params.maxBumpTip,
            _params.maxClaimFee,
            _params.minimumStakeAmount,
            _salt
        );

        StakerInfo memory stakerInfo = StakerInfo({
            deployerAddress: msg.sender,
            timestamp: block.timestamp,
            admin: _params.admin,
            rewardsToken: address(_params.rewardsToken),
            stakeToken: address(_params.stakeToken),
            maxBumpTip: _params.maxBumpTip,
            maxClaimFee: _params.maxClaimFee,
            minimumStakeAmount: _params.minimumStakeAmount
        });

        stakers[msg.sender].push(stakerInfo);
    }

    /// @notice Predicts the address of a RegenStaker contract.
    /// @param _salt The salt used to deploy the RegenStaker contract.
    /// @return The address of the RegenStaker contract.
    function predictStakerAddress(bytes32 _salt) external view returns (address) {
        return CREATE3.predictDeterministicAddress(keccak256(abi.encodePacked(_salt, msg.sender)));
    }

    /// @notice Gets all stakers by deployer.
    /// @param _deployer The address of the deployer.
    /// @return The stakers by deployer.
    function getStakersByDeployer(address _deployer) external view returns (StakerInfo[] memory) {
        return stakers[_deployer];
    }
}
