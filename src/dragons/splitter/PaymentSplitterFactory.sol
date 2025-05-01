// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PaymentSplitter } from "./PaymentSplitter.sol";

/**
 * @title PaymentSplitterFactory
 * @dev Factory contract to deploy new PaymentSplitter instances
 * This factory allows for the creation of new PaymentSplitter contracts with specified
 * payees and shares. It uses the CREATE opcode to deploy new instances.
 */
contract PaymentSplitterFactory {
    // Struct to store payment splitter information
    struct SplitterInfo {
        address splitterAddress;
        address[] payees;
        string[] payeeNames; // Names of each payee (e.g., "GrantRoundOperator", "ESF", "OpEx")
    }

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
        require(payees.length == payeeNames.length, "PaymentSplitterFactory: payees and payeeNames length mismatch");

        // Create a new PaymentSplitter with the provided arguments
        PaymentSplitter paymentSplitter = new PaymentSplitter(payees, shares);

        // Store the deployed splitter info
        deployerToSplitters[msg.sender].push(SplitterInfo(address(paymentSplitter), payees, payeeNames));

        // Emit event for tracking
        emit PaymentSplitterCreated(msg.sender, address(paymentSplitter), payees, payeeNames, shares);

        return address(paymentSplitter);
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
        require(payees.length == payeeNames.length, "PaymentSplitterFactory: payees and payeeNames length mismatch");

        // Create a new PaymentSplitter with the provided arguments
        PaymentSplitter paymentSplitter = new PaymentSplitter{ value: msg.value }(payees, shares);

        // Store the deployed splitter info
        deployerToSplitters[msg.sender].push(SplitterInfo(address(paymentSplitter), payees, payeeNames));

        // Emit event for tracking
        emit PaymentSplitterCreated(msg.sender, address(paymentSplitter), payees, payeeNames, shares);

        return address(paymentSplitter);
    }

    /**
     * @dev Returns all payment splitters created by a specific deployer
     * @param deployer The address of the deployer
     * @return An array of SplitterInfo structs
     */
    function getSplittersByDeployer(address deployer) external view returns (SplitterInfo[] memory) {
        return deployerToSplitters[deployer];
    }
}
