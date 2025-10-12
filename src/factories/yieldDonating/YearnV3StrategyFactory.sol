// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { BaseStrategyFactory } from "src/factories/BaseStrategyFactory.sol";
import { YearnV3Strategy } from "src/strategies/yieldDonating/YearnV3Strategy.sol";

contract YearnV3StrategyFactory is BaseStrategyFactory {
    /**
     * @dev Extended struct to store YearnV3Strategy-specific information.
     * @param management The address of the management entity responsible for the strategy.
     */
    struct YearnV3StrategyInfo {
        address management;
    }

    /**
     * @dev Mapping to store YearnV3Strategy-specific information.
     * Maps strategy address to YearnV3StrategyInfo
     */
    mapping(address => YearnV3StrategyInfo) public yearnV3StrategyInfo;

    event StrategyDeploy(
        address indexed management,
        address indexed donationAddress,
        address indexed strategyAddress,
        string vaultTokenName
    );

    /**
     * @notice Deploys a new YearnV3 strategy for the Yield Donating Vault.
     * @dev This function uses CREATE2 to deploy a new strategy contract deterministically.
     *      The strategy is initialized with the provided parameters, and its address is
     *      returned upon successful deployment. The function emits a `StrategyDeploy` event.
     * @param _yearnVault The address of the Yearn v3 vault to compound into.
     * @param _asset The address of the underlying asset.
     * @param _name The name of the vault token associated with the strategy.
     * @param _management The address of the management entity responsible for the strategy.
     * @param _keeper The address of the keeper responsible for maintaining the strategy.
     * @param _emergencyAdmin The address of the emergency admin for the strategy.
     * @param _donationAddress The address where donations from the strategy will be sent.
     * @param _enableBurning Whether to enable burning shares from dragon router during loss protection.
     * @param _tokenizedStrategyAddress The address of the tokenized strategy implementation.
     * @return strategyAddress The address of the newly deployed strategy contract.
     */
    function createStrategy(
        address _yearnVault,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    ) external returns (address) {
        // Generate parameter hash from all inputs
        bytes32 parameterHash = keccak256(
            abi.encode(
                _yearnVault,
                _asset,
                _name,
                _management,
                _keeper,
                _emergencyAdmin,
                _donationAddress,
                _enableBurning,
                _tokenizedStrategyAddress
            )
        );

        // Prepare bytecode for deployment
        bytes memory bytecode = abi.encodePacked(
            type(YearnV3Strategy).creationCode,
            abi.encode(
                _yearnVault,
                _asset,
                _name,
                _management,
                _keeper,
                _emergencyAdmin,
                _donationAddress,
                _enableBurning,
                _tokenizedStrategyAddress
            )
        );

        // Deploy strategy using base factory method
        address strategyAddress = _deployStrategy(bytecode, parameterHash);

        // Record strategy in base factory
        _recordStrategy(_name, _donationAddress, strategyAddress);

        // Store YearnV3-specific information
        yearnV3StrategyInfo[strategyAddress] = YearnV3StrategyInfo({ management: _management });

        emit StrategyDeploy(_management, _donationAddress, strategyAddress, _name);
        return strategyAddress;
    }
}
