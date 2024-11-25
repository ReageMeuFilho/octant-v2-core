// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Trader} from "../src/routers-transformers/Trader.sol";

contract DeployTraderHelper is Script {
    function run() external {
        (,,, uint256 deployerKey,,, address traderAddress,,,) = new HelperConfig(false).activeNetworkConfig();

        console.log("Trader at ", traderAddress);
        assert(traderAddress != address(0));

        Trader trader = Trader(payable(traderAddress));

        vm.startBroadcast(deployerKey);

        trader.setSpending(0.00128 ether, 0.00328 ether, 1 ether, block.number + 7200);

        vm.stopBroadcast();
    }
}
