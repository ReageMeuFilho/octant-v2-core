// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CREATE3 } from "@solady/utils/CREATE3.sol";
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
    /// @param _rewardsToken The address of the rewards token.
    /// @param _stakeToken The address of the stake token.
    /// @param _admin The address of the admin.
    /// @param _stakerWhitelist The address of the staker whitelist.
    /// @param _contributionWhitelist The address of the contribution whitelist.
    /// @param _earningPowerCalculator The address of the earning power calculator.
    /// @param _maxBumpTip The maximum bump tip.
    /// @param _maxClaimFee The maximum claim fee.
    /// @param _minimumStakeAmount The minimum stake amount.
    /// @param _salt The salt used to deploy the RegenStaker contract.
    /// @return stakerAddress The address of the RegenStaker contract.
    function createStaker(
        IERC20 _rewardsToken,
        IERC20Staking _stakeToken,
        address _admin,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IEarningPowerCalculator _earningPowerCalculator,
        uint256 _maxBumpTip,
        uint256 _maxClaimFee,
        uint256 _minimumStakeAmount,
        bytes32 _salt
    ) external returns (address stakerAddress) {
        bytes memory bytecode = abi.encodePacked(
            type(RegenStaker).creationCode,
            abi.encode(
                _rewardsToken,
                _stakeToken,
                _admin,
                _stakerWhitelist,
                _contributionWhitelist,
                _earningPowerCalculator,
                _maxBumpTip,
                _maxClaimFee,
                _minimumStakeAmount
            )
        );

        stakerAddress = CREATE3.deployDeterministic(bytecode, keccak256(abi.encodePacked(_salt, msg.sender)));

        emit StakerDeploy(
            msg.sender,
            _admin,
            stakerAddress,
            address(_rewardsToken),
            address(_stakeToken),
            _maxBumpTip,
            _maxClaimFee,
            _minimumStakeAmount,
            _salt
        );

        StakerInfo memory stakerInfo = StakerInfo({
            deployerAddress: msg.sender,
            timestamp: block.timestamp,
            admin: _admin,
            rewardsToken: address(_rewardsToken),
            stakeToken: address(_stakeToken),
            maxBumpTip: _maxBumpTip,
            maxClaimFee: _maxClaimFee,
            minimumStakeAmount: _minimumStakeAmount
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
