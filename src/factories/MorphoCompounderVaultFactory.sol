// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { MorphoCompounder } from "src/regens/YieldSkimming/strategy/MorphoCompounder.sol";

contract MorphoCompounderVaultFactory {
    /**
     * @dev Struct to store information about a strategy.
     * @param deployerAddress The address of the deployer who created the strategy.
     * @param timestamp The timestamp when the strategy was created.
     * @param vaultTokenName The name of the vault token associated with the strategy.
     * @param donationAddress The address where donations from the strategy will be sent.
     */
    struct StrategyInfo {
        address deployerAddress;
        uint256 timestamp;
        string vaultTokenName;
        address donationAddress;
    }

    /**
     * @dev Mapping to store information about strategies.
     * Each strategy is identified by its address and is associated with a `StrategyInfo` struct.
     * This mapping provides a way to retrieve details about a specific strategy.
     *
     * @notice The `StrategyInfo` struct typically contains data related to the strategy's configuration
     * and operational parameters. Ensure that the address provided as a key is valid and corresponds
     * to a registered strategy.
     *
     * index is the address The address of the strategy.
     * returns the information associated with the given strategy address.
     */
    mapping(address => StrategyInfo[]) public strategies;

    address public constant ysUSDC = 0x074134A2784F4F66b6ceD6f68849382990Ff3215;

    event StrategyDeploy(
        address indexed deployer,
        address indexed donationAddress,
        address indexed strategyAddress,
        string vaultTokenName
    );

    /**
     * @notice Deploys a new MorphoCompounder strategy for the Yield Skimming Vault.
     * @dev This function uses CREATE3 to deploy a new strategy contract deterministically.
     *      The strategy is initialized with the provided parameters, and its address is
     *      returned upon successful deployment. The function emits a `MorphoStrategyDeploy` event.
     * @param _name The name of the vault token associated with the strategy.
     * @param _management The address of the management entity responsible for the strategy.
     * @param _keeper The address of the keeper responsible for maintaining the strategy.
     * @param _emergencyAdmin The address of the emergency admin for the strategy.
     * @param _donationAddress The address where donations from the strategy will be sent.
     * @param _salt A unique salt used for deterministic deployment of the strategy.
     * @return strategyAddress The address of the newly deployed strategy contract.
     */
    function createStrategy(
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bytes32 _salt
    ) external returns (address strategyAddress) {
        bytes memory bytecode = abi.encodePacked(
            type(MorphoCompounder).creationCode,
            abi.encode(ysUSDC, _name, _management, _keeper, _emergencyAdmin, _donationAddress)
        );

        strategyAddress = CREATE3.deployDeterministic(bytecode, _salt);
        emit StrategyDeploy(msg.sender, _donationAddress, strategyAddress, _name);
        StrategyInfo memory strategyInfo = StrategyInfo({
            deployerAddress: msg.sender,
            timestamp: block.timestamp,
            vaultTokenName: _name,
            donationAddress: _donationAddress
        });
        strategies[msg.sender].push(strategyInfo);
    }
}
