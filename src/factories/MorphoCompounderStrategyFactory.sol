// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { MorphoCompounderStrategy } from "src/strategies/yieldDonating/MorphoCompounderStrategy.sol";
import { BaseStrategyFactory } from "src/factories/BaseStrategyFactory.sol";

/**
 * @title MorphoCompounderStrategyFactory
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Factory for deploying Morpho Compounder yield donating strategies
 * @dev Uses CREATE2 for deterministic deployments; records deployments via BaseStrategyFactory
 */
contract MorphoCompounderStrategyFactory is BaseStrategyFactory {
    address public constant YS_USDC = 0x074134A2784F4F66b6ceD6f68849382990Ff3215;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice Emitted on successful strategy deployment
    /// @param deployer Transaction sender performing deployment
    /// @param donationAddress Donation destination address for strategy
    /// @param strategyAddress Deployed strategy address
    /// @param vaultTokenName Vault token name associated with strategy
    event StrategyDeploy(
        address indexed deployer,
        address indexed donationAddress,
        address indexed strategyAddress,
        string vaultTokenName
    );

    /**
     * @notice Deploy a new MorphoCompounder strategy
     * @dev Deterministic salt derived from all parameters to avoid duplicates
     * @param _name Strategy share token name
     * @param _management Management address (can update params)
     * @param _keeper Keeper address (calls report)
     * @param _emergencyAdmin Emergency admin address
     * @param _donationAddress Dragon router address (receives profit shares)
     * @param _enableBurning True to enable burning shares during loss protection
     * @param _tokenizedStrategyAddress TokenizedStrategy implementation address
     * @return strategyAddress Deployed MorphoCompounderStrategy address
     */
    function createStrategy(
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    ) external returns (address) {
        bytes32 parameterHash = keccak256(
            abi.encode(
                YS_USDC,
                USDC,
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
            type(MorphoCompounderStrategy).creationCode,
            abi.encode(
                YS_USDC,
                USDC,
                _name,
                _management,
                _keeper,
                _emergencyAdmin,
                _donationAddress,
                _enableBurning,
                _tokenizedStrategyAddress
            )
        );

        address strategyAddress = _deployStrategy(bytecode, parameterHash);
        _recordStrategy(_name, _donationAddress, strategyAddress);

        emit StrategyDeploy(msg.sender, _donationAddress, strategyAddress, _name);
        return strategyAddress;
    }
}
