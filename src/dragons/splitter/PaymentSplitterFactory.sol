/* solhint-disable gas-custom-errors*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PaymentSplitter } from "./PaymentSplitter.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title PaymentSplitterFactory
 * @dev Factory contract to deploy new PaymentSplitter instances as minimal proxies (ERC-1167)
 * This factory allows for the creation of new PaymentSplitter proxies with specified
 * payees and shares. It uses the Clones library to deploy minimal proxies.
 */
contract PaymentSplitterFactory {
    // Address of the implementation contract
    address public immutable implementation;

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
     * @dev Constructor deploys an implementation contract to be used as the base for all proxies
     */
    constructor() {
        // Deploy the implementation contract
        implementation = address(new PaymentSplitter());
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

        // Create a minimal proxy
        address paymentSplitter = Clones.clone(implementation);

        // Initialize the proxy
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
        require(payees.length == payeeNames.length, "PaymentSplitterFactory: length mismatch");

        // Create a minimal proxy
        address paymentSplitter = Clones.clone(implementation);

        // Initialize the proxy with value
        bytes memory initData = abi.encodeWithSelector(PaymentSplitter.initialize.selector, payees, shares);

        (bool success, ) = paymentSplitter.call{ value: msg.value }(initData);
        require(success, "PaymentSplitterFactory: initialization failed");

        // Store the deployed splitter info
        deployerToSplitters[msg.sender].push(SplitterInfo(paymentSplitter, payees, payeeNames));

        // Emit event for tracking
        emit PaymentSplitterCreated(msg.sender, paymentSplitter, payees, payeeNames, shares);

        return paymentSplitter;
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
