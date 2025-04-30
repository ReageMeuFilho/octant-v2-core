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
    // Event emitted when a new PaymentSplitter is created
    event PaymentSplitterCreated(address indexed paymentSplitter, address[] payees, uint256[] shares);

    /**
     * @dev Creates a new PaymentSplitter instance with the specified payees and shares
     * @param payees The addresses of the payees to receive payments
     * @param shares The number of shares assigned to each payee
     * @return The address of the newly created PaymentSplitter
     */
    function createPaymentSplitter(address[] memory payees, uint256[] memory shares) external returns (address) {
        // Create a new PaymentSplitter with the provided arguments
        PaymentSplitter paymentSplitter = new PaymentSplitter(payees, shares);

        // Emit event for tracking
        emit PaymentSplitterCreated(address(paymentSplitter), payees, shares);

        return address(paymentSplitter);
    }

    /**
     * @dev Creates a new PaymentSplitter instance with the specified payees and shares and sends ETH to it
     * @param payees The addresses of the payees to receive payments
     * @param shares The number of shares assigned to each payee
     * @return The address of the newly created PaymentSplitter
     */
    function createPaymentSplitterWithETH(
        address[] memory payees,
        uint256[] memory shares
    ) external payable returns (address) {
        // Create a new PaymentSplitter with the provided arguments
        PaymentSplitter paymentSplitter = new PaymentSplitter{ value: msg.value }(payees, shares);

        // Emit event for tracking
        emit PaymentSplitterCreated(address(paymentSplitter), payees, shares);

        return address(paymentSplitter);
    }
}
