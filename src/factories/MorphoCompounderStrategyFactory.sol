// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { MorphoCompounderStrategy } from "src/strategies/yieldDonating/MorphoCompounderStrategy.sol";
import { BaseStrategyFactory } from "src/factories/BaseStrategyFactory.sol";

contract MorphoCompounderStrategyFactory is BaseStrategyFactory {
    address public constant YS_USDC = 0x074134A2784F4F66b6ceD6f68849382990Ff3215;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    event StrategyDeploy(
        address indexed deployer,
        address indexed donationAddress,
        address indexed strategyAddress,
        string vaultTokenName
    );

    /**
     * @notice Deploys a new MorphoCompounder strategy for the Yield Skimming Vault.
     * @dev This function uses CREATE2 to deploy a new strategy contract deterministically.
     *      The strategy is initialized with the provided parameters, and its address is
     *      returned upon successful deployment. The function emits a `MorphoStrategyDeploy` event.
     * @param _name The name of the vault token associated with the strategy.
     * @param _management The address of the management entity responsible for the strategy.
     * @param _keeper The address of the keeper responsible for maintaining the strategy.
     * @param _emergencyAdmin The address of the emergency admin for the strategy.
     * @param _donationAddress The address where donations from the strategy will be sent.
     * @param _enableBurning Whether to enable burning shares from dragon router during loss protection.
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
