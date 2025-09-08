// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { TokenizedAllocationMechanism } from "./TokenizedAllocationMechanism.sol";
import { QuadraticVotingMechanism } from "./mechanism/QuadraticVotingMechanism.sol";
import { AllocationConfig } from "./BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

/// @title Allocation Mechanism Factory
/// @notice Factory for deploying allocation mechanisms using the Yearn V3 pattern
/// @dev Deploys a single TokenizedAllocationMechanism that is shared by all strategies
contract AllocationMechanismFactory {
    // ---------- State Variables ----------

    /// @notice The shared TokenizedAllocationMechanism implementation
    address public immutable tokenizedAllocationImplementation;

    /// @notice Track deployed allocation mechanisms
    address[] public deployedMechanisms;
    mapping(address => bool) public isMechanism;

    // ---------- Events ----------

    /// @notice Emitted when a new allocation mechanism is deployed
    event AllocationMechanismDeployed(
        address indexed mechanism,
        address indexed asset,
        string name,
        string symbol,
        address indexed deployer
    );

    // ---------- Errors ----------

    /// @notice Thrown when trying to deploy a mechanism with same parameters
    error MechanismAlreadyExists(address existingMechanism);

    // ---------- Constructor ----------

    constructor() {
        // Deploy the shared TokenizedAllocationMechanism implementation
        tokenizedAllocationImplementation = address(new TokenizedAllocationMechanism());
    }

    // ---------- External Functions ----------

    /// @notice Predict the address of a QuadraticVotingMechanism before deployment
    /// @param _config Configuration parameters for the allocation mechanism
    /// @param _alphaNumerator Alpha numerator for quadratic funding
    /// @param _alphaDenominator Alpha denominator for quadratic funding
    /// @param deployer Address that will deploy the mechanism
    /// @return predicted The predicted address of the mechanism
    function predictMechanismAddress(
        AllocationConfig memory _config,
        uint256 _alphaNumerator,
        uint256 _alphaDenominator,
        address deployer
    ) public view returns (address predicted) {
        // Set the deployer as the owner to match deployment logic
        _config.owner = deployer;

        // Generate deterministic salt from parameters
        bytes32 salt = keccak256(
            abi.encode(
                tokenizedAllocationImplementation,
                _config.asset,
                _config.name,
                _config.symbol,
                _config.votingDelay,
                _config.votingPeriod,
                _config.quorumShares,
                _config.timelockDelay,
                _config.gracePeriod,
                _alphaNumerator,
                _alphaDenominator,
                deployer
            )
        );

        // Need to build the same bytecode that will be used in deployment
        bytes memory bytecode = abi.encodePacked(
            type(QuadraticVotingMechanism).creationCode,
            abi.encode(tokenizedAllocationImplementation, _config, _alphaNumerator, _alphaDenominator)
        );

        return Create2.computeAddress(salt, keccak256(bytecode));
    }

    /// @notice Deploy a new QuadraticVotingMechanism
    /// @param _config Configuration parameters for the allocation mechanism
    /// @param _alphaNumerator Alpha numerator for quadratic funding
    /// @param _alphaDenominator Alpha denominator for quadratic funding
    /// @return mechanism Address of the deployed mechanism
    function deployQuadraticVotingMechanism(
        AllocationConfig memory _config,
        uint256 _alphaNumerator,
        uint256 _alphaDenominator
    ) external returns (address mechanism) {
        // Set the deployer as the owner
        _config.owner = msg.sender;

        // Generate deterministic salt from parameters
        bytes32 salt = keccak256(
            abi.encode(
                tokenizedAllocationImplementation,
                _config.asset,
                _config.name,
                _config.symbol,
                _config.votingDelay,
                _config.votingPeriod,
                _config.quorumShares,
                _config.timelockDelay,
                _config.gracePeriod,
                _alphaNumerator,
                _alphaDenominator,
                msg.sender
            )
        );

        // Prepare creation bytecode
        bytes memory bytecode = abi.encodePacked(
            type(QuadraticVotingMechanism).creationCode,
            abi.encode(tokenizedAllocationImplementation, _config, _alphaNumerator, _alphaDenominator)
        );

        // Check if mechanism already exists
        address predictedAddress = Create2.computeAddress(salt, keccak256(bytecode));

        if (predictedAddress.code.length > 0) {
            revert MechanismAlreadyExists(predictedAddress);
        }

        // Deploy new QuadraticVotingMechanism using CREATE2
        mechanism = Create2.deploy(0, salt, bytecode);

        // Track deployment
        deployedMechanisms.push(mechanism);
        isMechanism[mechanism] = true;

        emit AllocationMechanismDeployed(mechanism, address(_config.asset), _config.name, _config.symbol, msg.sender);

        return mechanism;
    }

    // ---------- View Functions ----------

    /// @notice Get the number of deployed mechanisms
    function getDeployedCount() external view returns (uint256) {
        return deployedMechanisms.length;
    }

    /// @notice Get all deployed mechanisms
    function getAllDeployedMechanisms() external view returns (address[] memory) {
        return deployedMechanisms;
    }

    /// @notice Get a deployed mechanism by index
    function getDeployedMechanism(uint256 index) external view returns (address) {
        require(index < deployedMechanisms.length, "Index out of bounds");
        return deployedMechanisms[index];
    }
}
