// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { BaseStrategyFactory } from "./BaseStrategyFactory.sol";
import { SkyCompounderStrategy } from "src/strategies/yieldDonating/SkyCompounderStrategy.sol";

/**
 * @title SkyCompounderStrategyFactory
 * @author Octant
 * @notice Factory for deploying Sky Compounder yield donating strategies
 * @dev Inherits deterministic deployment from BaseStrategyFactory
 */
contract SkyCompounderStrategyFactory is BaseStrategyFactory {
    /// @notice USDS reward address on mainnet
    address constant USDS_REWARD_ADDRESS = 0x0650CAF159C5A49f711e8169D4336ECB9b950275;

    // Child-specific StrategyDeploy event for compatibility with existing tests
    event StrategyDeploy(
        address indexed deployer,
        address indexed donationAddress,
        address indexed strategyAddress,
        string vaultTokenName
    );

    /**
     * @notice Deploys a new SkyCompounder strategy for the Yield Donating Vault.
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
                USDS_REWARD_ADDRESS,
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
            type(SkyCompounderStrategy).creationCode,
            abi.encode(
                USDS_REWARD_ADDRESS,
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
