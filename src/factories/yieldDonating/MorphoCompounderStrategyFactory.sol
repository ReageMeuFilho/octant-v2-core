// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { CREATE3 } from "solady/utils/CREATE3.sol";
import { MorphoCompounderStrategy } from "src/strategies/yieldDonating/MorphoCompounderStrategy.sol";

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

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    event StrategyDeploy(
        address indexed deployer,
        address indexed donationAddress,
        address indexed strategyAddress,
        string vaultTokenName
    );

    error StrategyAlreadyExists(address existingStrategy);

    /**
     * @notice Predict deterministic deployment address
     * @param _parameterHash Hash of all strategy parameters
     * @param deployer Address that will deploy
     * @return Predicted contract address
     */
    function predictStrategyAddress(bytes32 _parameterHash, address deployer) external view returns (address) {
        bytes32 finalSalt = keccak256(abi.encodePacked(_parameterHash, deployer));
        return CREATE3.predictDeterministicAddress(finalSalt);
    }

    /**
     * @notice Deploys a new MorphoCompounder strategy for the Yield Donating Vault.
     * @dev This function uses CREATE3 to deploy a new strategy contract deterministically.
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
        address _compounderVault,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress,
        bool _allowDepositDuringLoss
    ) external returns (address) {
        bytes32 finalSalt;
        address strategyAddress;

        {
            // Generate parameter hash from all inputs (in a closure to reduce stack usage)
            bytes32 parameterHash = keccak256(
                abi.encode(
                    _compounderVault,
                    USDC,
                    _name,
                    _management,
                    _keeper,
                    _emergencyAdmin,
                    _donationAddress,
                    _enableBurning,
                    _tokenizedStrategyAddress,
                    _allowDepositDuringLoss
                )
            );

            // Generate final salt using parameter hash and sender
            finalSalt = keccak256(abi.encodePacked(parameterHash, msg.sender));

            // Check if strategy already exists
            address predictedAddress = CREATE3.predictDeterministicAddress(finalSalt);
            if (predictedAddress.code.length > 0) {
                revert StrategyAlreadyExists(predictedAddress);
            }
        }

        {
            // Deploy strategy in another closure
            bytes memory bytecode = abi.encodePacked(
                type(MorphoCompounderStrategy).creationCode,
                abi.encode(
                    _compounderVault,
                    USDC,
                    _name,
                    _management,
                    _keeper,
                    _emergencyAdmin,
                    _donationAddress,
                    _enableBurning,
                    _tokenizedStrategyAddress,
                    _allowDepositDuringLoss
                )
            );

            strategyAddress = CREATE3.deployDeterministic(bytecode, finalSalt);
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
