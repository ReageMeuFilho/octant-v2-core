// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { MorphoCompounderStrategy } from "src/strategies/yieldSkimming/MorphoCompounderStrategy.sol";

contract MorphoCompounderStrategyFactory {
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

    address public constant YS_USDC = 0x074134A2784F4F66b6ceD6f68849382990Ff3215;

    event StrategyDeploy(
        address indexed deployer,
        address indexed donationAddress,
        address indexed strategyAddress,
        string vaultTokenName
    );

    error StrategyAlreadyExists(address existingStrategy);

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
        bytes32 parameterHash;
        bytes32 finalSalt;
        address strategyAddress;

        {
            // Generate parameter hash from all inputs (in a closure to reduce stack usage)
            parameterHash = keccak256(
                abi.encode(
                    YS_USDC,
                    _name,
                    _management,
                    _keeper,
                    _emergencyAdmin,
                    _donationAddress,
                    _enableBurning,
                    _tokenizedStrategyAddress
                )
            );

            // Generate final salt using parameter hash and sender
            finalSalt = keccak256(abi.encodePacked(parameterHash, msg.sender));
        }

        {
            // Deploy strategy in another closure
            bytes memory bytecode = abi.encodePacked(
                type(MorphoCompounderStrategy).creationCode,
                abi.encode(
                    YS_USDC,
                    _name,
                    _management,
                    _keeper,
                    _emergencyAdmin,
                    _donationAddress,
                    _enableBurning,
                    _tokenizedStrategyAddress
                )
            );

            // Check if strategy already exists
            address predictedAddress = Create2.computeAddress(finalSalt, keccak256(bytecode));

            if (predictedAddress.code.length > 0) {
                revert StrategyAlreadyExists(predictedAddress);
            }

            strategyAddress = Create2.deploy(0, finalSalt, bytecode);
        }

        // Store strategy info
        strategies[msg.sender].push(
            StrategyInfo({
                deployerAddress: msg.sender,
                timestamp: block.timestamp,
                vaultTokenName: _name,
                donationAddress: _donationAddress
            })
        );

        emit StrategyDeploy(_management, _donationAddress, strategyAddress, _name);
        return strategyAddress;
    }
}
