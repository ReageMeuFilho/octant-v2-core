// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { CREATE3 } from "solady/utils/CREATE3.sol";

/**
 * @title BaseStrategyFactory
 * @author Octant
 * @notice Base contract for strategy factories with deterministic deployment
 * @dev Uses CREATE3 with user-provided salts for backward compatibility
 *
 * Security Considerations:
 * - Callers are responsible for managing salt uniqueness to prevent collisions
 * - Salt is combined with msg.sender to ensure deployer-specific addresses
 * - Addresses are deterministic and predictable based on salt and deployer
 */
abstract contract BaseStrategyFactory {
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
     * @dev Mapping from deployer address to their deployed strategies
     * Used for tracking deployed strategies
     */
    mapping(address => StrategyInfo[]) public strategies;

    // Note: Child factories should declare and emit their own `StrategyDeploy` event for compatibility.

    /**
     * @notice Predict deployment address using user-provided salt and deployer
     * @dev Combines salt with deployer address for deterministic deployment
     * @param _salt User-provided salt for uniqueness
     * @param deployer Deployer address
     * @return Predicted contract address
     */
    function predictStrategyAddress(bytes32 _salt, address deployer) external view returns (address) {
        bytes32 finalSalt = keccak256(abi.encodePacked(_salt, deployer));
        return CREATE3.predictDeterministicAddress(finalSalt);
    }

    /**
     * @dev Internal function to deploy strategy using CREATE3
     * @param bytecode The deployment bytecode
     * @param _salt User-provided salt for deterministic deployment
     * @return strategyAddress The deployed strategy address
     */
    function _deployStrategy(bytes memory bytecode, bytes32 _salt) internal returns (address strategyAddress) {
        bytes32 finalSalt = keccak256(abi.encodePacked(_salt, msg.sender));
        strategyAddress = CREATE3.deployDeterministic(bytecode, finalSalt);
    }

    /**
     * @dev Internal function to record strategy deployment
     * @param _name Strategy name
     * @param _donationAddress Donation address
     * @param _strategyAddress Deployed strategy address
     */
    function _recordStrategy(string memory _name, address _donationAddress, address _strategyAddress) internal {
        // Silence unused parameter warning
        _strategyAddress;
        StrategyInfo memory strategyInfo = StrategyInfo({
            deployerAddress: msg.sender,
            timestamp: block.timestamp,
            vaultTokenName: _name,
            donationAddress: _donationAddress
        });

        strategies[msg.sender].push(strategyInfo);
    }

    /**
     * @dev Get all strategies deployed by a specific address
     * @param deployer Address of the deployer
     * @return Array of StrategyInfo for all strategies deployed by the address
     */
    function getStrategiesByDeployer(address deployer) external view returns (StrategyInfo[] memory) {
        return strategies[deployer];
    }
}
