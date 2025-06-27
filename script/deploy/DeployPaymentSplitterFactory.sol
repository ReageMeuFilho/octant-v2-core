// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { PaymentSplitterFactory } from "src/factories/PaymentSplitterFactory.sol";

contract DeployPaymentSplitterFactory is Script {
    PaymentSplitterFactory public paymentSplitterFactory;

    function deploy() public virtual {
        run();
    }

    function run() public returns (PaymentSplitterFactory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the factory
        paymentSplitterFactory = new PaymentSplitterFactory();

        console2.log("PaymentSplitterFactory deployed at:", address(paymentSplitterFactory));

        vm.stopBroadcast();

        return paymentSplitterFactory;
    }
}
