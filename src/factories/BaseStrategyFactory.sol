// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { CREATE3 } from "solady/utils/CREATE3.sol";

/**
 * @title BaseStrategyFactory
 * @author Octant
 * @notice Base contract for strategy factories with secure deterministic deployment
 * @dev Uses CREATE3 with deployer-specific counters to prevent front-running attacks
 * 
 * Security Considerations:
 * - Each deployer has a unique counter that increments with each deployment
 * - Salt is derived from msg.sender and their deployment count
 * - This prevents front-running as an attacker cannot predict or manipulate the counter
 * - Addresses are deterministic and predictable for legitimate users
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
     * Used for tracking and generating unique salts
     */
    mapping(address => StrategyInfo[]) public strategies;

    /**
     * @dev Counter for each deployer to ensure unique deployments
     * Critical for preventing front-running attacks
     */
    mapping(address => uint256) public deploymentCounter;

    event StrategyDeploy(
        address indexed deployer,
        address indexed donationAddress,
        address indexed strategyAddress,
        string vaultTokenName
    );

    /**
     * @notice Predict deterministic deployment address for the next strategy
     * @dev Uses the current deployment counter for the deployer
     * @param deployer Address that will deploy
     * @return Predicted contract address
     */
    function predictNextStrategyAddress(address deployer) external view returns (address) {
        bytes32 salt = _generateSalt(deployer, deploymentCounter[deployer]);
        return CREATE3.predictDeterministicAddress(salt);
    }

    /**
     * @notice Predict deterministic deployment address for a specific deployment index
     * @param deployer Address that will deploy
     * @param index Deployment index to predict
     * @return Predicted contract address
     */
    function predictStrategyAddressAtIndex(address deployer, uint256 index) external view returns (address) {
        bytes32 salt = _generateSalt(deployer, index);
        return CREATE3.predictDeterministicAddress(salt);
    }

    /**
     * @dev Generate secure salt combining deployer and their counter
     * @param deployer Address of the deployer
     * @param counter Deployment counter for the deployer
     * @return salt Secure salt for deterministic deployment
     */
    function _generateSalt(address deployer, uint256 counter) internal pure returns (bytes32) {
        return keccak256(abi.encode(deployer, counter));
    }

    /**
     * @dev Internal function to deploy strategy using CREATE3
     * @param bytecode The deployment bytecode
     * @return strategyAddress The deployed strategy address
     */
    function _deployStrategy(bytes memory bytecode) internal returns (address strategyAddress) {
        // Generate secure salt using deployer and their counter
        bytes32 salt = _generateSalt(msg.sender, deploymentCounter[msg.sender]);
        
        // Increment counter for next deployment
        deploymentCounter[msg.sender]++;
        
        // Deploy using CREATE3
        strategyAddress = CREATE3.deployDeterministic(bytecode, salt);
    }

    /**
     * @dev Internal function to record strategy deployment
     * @param _name Strategy name
     * @param _donationAddress Donation address
     * @param strategyAddress Deployed strategy address
     */
    function _recordStrategy(
        string memory _name,
        address _donationAddress,
        address strategyAddress
    ) internal {
        emit StrategyDeploy(msg.sender, _donationAddress, strategyAddress, _name);
        
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

    /**
     * @dev Get the number of strategies deployed by an address
     * @param deployer Address of the deployer
     * @return Number of strategies deployed
     */
    function getDeploymentCount(address deployer) external view returns (uint256) {
        return deploymentCounter[deployer];
    }
}