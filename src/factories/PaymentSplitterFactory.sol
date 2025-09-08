/* solhint-disable gas-custom-errors*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PaymentSplitter } from "src/core/PaymentSplitter.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title PaymentSplitterFactory
 * @dev Factory contract to deploy new PaymentSplitter instances as minimal proxies (ERC-1167)
 * This factory allows for the creation of new PaymentSplitter proxies with specified
 * payees and shares. It uses the Clones library to deploy minimal proxies.
 */
contract PaymentSplitterFactory {
    // Struct to store payment splitter information
    struct SplitterInfo {
        address splitterAddress;
        address[] payees;
        string[] payeeNames; // Names of each payee (e.g., "GrantRoundOperator", "ESF", "OpEx")
    }

    // Address of the implementation contract
    address public immutable implementation;

    // Owner allowed to sweep any accidentally sent ETH
    address public immutable owner;

    // Mapping from deployer address to their deployed splitters
    mapping(address => SplitterInfo[]) public deployerToSplitters;

    // Event emitted when a new PaymentSplitter is created
    event PaymentSplitterCreated(
        address indexed deployer,
        address indexed paymentSplitter,
        address[] payees,
        string[] payeeNames,
        uint256[] shares
    );

    /**
     * @dev Constructor deploys an implementation contract to be used as the base for all proxies
     */
    constructor() {
        // Deploy the implementation contract
        implementation = address(new PaymentSplitter());
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "PaymentSplitterFactory: not owner");
        _;
    }

    /**
     * @dev Creates a new PaymentSplitter instance with the specified payees and shares
     * @param payees The addresses of the payees to receive payments
     * @param payeeNames Names for each payee (e.g., "GrantRoundOperator", "ESF", "OpEx")
     * @param shares The number of shares assigned to each payee
     * @return The address of the newly created PaymentSplitter
     */
    function createPaymentSplitter(
        address[] memory payees,
        string[] memory payeeNames,
        uint256[] memory shares
    ) external returns (address) {
        require(
            payees.length == payeeNames.length && payees.length == shares.length,
            "PaymentSplitterFactory: length mismatch"
        );

        // Generate deterministic salt combining user input with sender and deployment count
        bytes32 finalSalt = keccak256(abi.encode(msg.sender, deployerToSplitters[msg.sender].length));

        // Create a deterministic minimal proxy
        address paymentSplitter = Clones.cloneDeterministic(implementation, finalSalt);

        // Initialize the proxy; revert with a factory-specific error if initialization fails
        bytes memory initData = abi.encodeWithSelector(PaymentSplitter.initialize.selector, payees, shares);
        (bool success, ) = paymentSplitter.call(initData);
        require(success, "PaymentSplitterFactory: initialization failed");

        // Store the deployed splitter info
        deployerToSplitters[msg.sender].push(SplitterInfo(paymentSplitter, payees, payeeNames));

        // Emit event for tracking
        emit PaymentSplitterCreated(msg.sender, paymentSplitter, payees, payeeNames, shares);

        return paymentSplitter;
    }

    /**
     * @dev Creates a new PaymentSplitter instance with the specified payees and shares and sends ETH to it
     * @param payees The addresses of the payees to receive payments
     * @param payeeNames Names for each payee (e.g., "GrantRoundOperator", "ESF", "OpEx")
     * @param shares The number of shares assigned to each payee
     * @return The address of the newly created PaymentSplitter
     */
    function createPaymentSplitterWithETH(
        address[] memory payees,
        string[] memory payeeNames,
        uint256[] memory shares
    ) external payable returns (address) {
        require(
            payees.length == payeeNames.length && payees.length == shares.length,
            "PaymentSplitterFactory: length mismatch"
        );

        // Generate deterministic salt combining user input with sender and deployment count
        bytes32 finalSalt = keccak256(abi.encode(msg.sender, deployerToSplitters[msg.sender].length));

        // Create a deterministic minimal proxy with value
        address paymentSplitter = Clones.cloneDeterministic(implementation, finalSalt, msg.value);

        // Initialize the proxy; revert with a factory-specific error if initialization fails
        bytes memory initData = abi.encodeWithSelector(PaymentSplitter.initialize.selector, payees, shares);
        (bool success, ) = paymentSplitter.call(initData);
        require(success, "PaymentSplitterFactory: initialization failed");

        // Store the deployed splitter info
        deployerToSplitters[msg.sender].push(SplitterInfo(paymentSplitter, payees, payeeNames));

        // Emit event for tracking
        emit PaymentSplitterCreated(msg.sender, paymentSplitter, payees, payeeNames, shares);

        return paymentSplitter;
    }

    /**
     * @dev Sweep any ETH accidentally left on this factory to the provided recipient.
     * This should normally be zero since ETH is forwarded to clones at creation.
     */
    function sweep(address payable recipient) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "PaymentSplitterFactory: no ETH to sweep");
        (bool success, ) = recipient.call{ value: balance }("");
        require(success, "PaymentSplitterFactory: sweep failed");
    }

    /**
     * @dev Returns all payment splitters created by a specific deployer
     * @param deployer The address of the deployer
     * @return An array of SplitterInfo structs
     */
    function getSplittersByDeployer(address deployer) external view returns (SplitterInfo[] memory) {
        return deployerToSplitters[deployer];
    }

    /**
     * @dev Predicts the address of a deterministic clone that would be created with the given salt
     * @param deployer The address of the deployer
     * @return The predicted address of the clone
     */
    function predictDeterministicAddress(address deployer) external view returns (address) {
        bytes32 finalSalt = keccak256(abi.encode(deployer, deployerToSplitters[deployer].length));
        return Clones.predictDeterministicAddress(implementation, finalSalt);
    }
}
