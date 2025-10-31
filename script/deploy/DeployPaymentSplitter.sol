// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { PaymentSplitterFactory } from "src/factories/PaymentSplitterFactory.sol";
import { PaymentSplitter } from "src/core/PaymentSplitter.sol";

contract DeployPaymentSplitter is Script {
    address public paymentSplitter;

    // Default configuration if not overridden by environment variables
    address[] public defaultPayees = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Default anvil address 1
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // Default anvil address 2
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC // Default anvil address 3
    ];

    // Get existing factory address from environment or use default
    address factoryAddress = 0x0000000000000000000000000000000000000000;

    // Optional initial ETH amount
    uint256 initialEthAmount = 0;

    string[] public defaultPayeeNames = ["GrantRoundOperator", "ESF", "OpEx"];

    uint256[] public defaultShares = [50, 30, 20];

    function run() public returns (address) {
        require(factoryAddress != address(0), "Factory address must be set");

        // Use either environment variables or defaults
        address[] memory payees;
        string[] memory payeeNames;
        uint256[] memory shares;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PaymentSplitterFactory factory = PaymentSplitterFactory(factoryAddress);

        // Deploy with or without ETH
        if (initialEthAmount > 0) {
            paymentSplitter = factory.createPaymentSplitterWithETH{ value: initialEthAmount }(
                payees,
                payeeNames,
                shares
            );
        } else {
            paymentSplitter = factory.createPaymentSplitter(payees, payeeNames, shares);
        }

        console2.log("PaymentSplitter deployed at:", paymentSplitter);

        vm.stopBroadcast();

        return paymentSplitter;
    }
}
