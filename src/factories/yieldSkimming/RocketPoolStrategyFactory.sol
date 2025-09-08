// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { BaseStrategyFactory } from "../BaseStrategyFactory.sol";
import { RocketPoolStrategy } from "src/strategies/yieldSkimming/RocketPoolStrategy.sol";

/**
 * @title RocketPoolStrategyFactory
 * @author Octant
 * @notice Factory for deploying RocketPool yield skimming strategies
 * @dev Inherits deterministic deployment from BaseStrategyFactory
 */
contract RocketPoolStrategyFactory is BaseStrategyFactory {
    /// @notice rETH token address on mainnet
    address public constant R_ETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    // Child-specific StrategyDeploy event for compatibility with existing tests
    event StrategyDeploy(
        address indexed deployer,
        address indexed donationAddress,
        address indexed strategyAddress,
        string vaultTokenName
    );

    /**
     * @notice Deploys a new RocketPool strategy for the Yield Skimming Vault.
     * @dev Uses deterministic deployment based on strategy parameters to prevent duplicates.
     * @param _name The name of the vault token associated with the strategy.
     * @param _management The address of the management entity responsible for the strategy.
     * @param _keeper The address of the keeper responsible for maintaining the strategy.
     * @param _emergencyAdmin The address of the emergency admin for the strategy.
     * @param _donationAddress The address where donations from the strategy will be sent.
     * @param _enableBurning Whether to enable burning shares from dragon router during loss protection.
     * @param _tokenizedStrategyAddress Address of the tokenized strategy implementation
     * @return strategyAddress The address of the newly deployed strategy contract.
     */
    function createStrategy(
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    ) external returns (address strategyAddress) {
        // Generate deterministic hash from all strategy parameters
        bytes32 parameterHash = keccak256(
            abi.encode(
                R_ETH,
                _name,
                _management,
                _keeper,
                _emergencyAdmin,
                _donationAddress,
                _enableBurning,
                _tokenizedStrategyAddress
            )
        );

        bytes memory bytecode = abi.encodePacked(
            type(RocketPoolStrategy).creationCode,
            abi.encode(
                R_ETH,
                _name,
                _management,
                _keeper,
                _emergencyAdmin,
                _donationAddress,
                _enableBurning,
                _tokenizedStrategyAddress
            )
        );

        // Deploy using parameter hash to prevent duplicates
        strategyAddress = _deployStrategy(bytecode, parameterHash);

        emit StrategyDeploy(_management, _donationAddress, strategyAddress, _name);

        // Record the deployment
        _recordStrategy(_name, _donationAddress, strategyAddress);
    }
}
