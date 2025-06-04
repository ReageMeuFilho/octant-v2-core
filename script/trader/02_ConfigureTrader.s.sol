// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import { HelperConfig } from "../helpers/HelperConfig.s.sol";
import { Trader } from "src/utils/routers-transformers/Trader.sol";

contract DeployTraderHelper is Script {
    function run() external {
        (, , , uint256 deployerKey, , , , , , ) = new HelperConfig(false).activeNetworkConfig();

        address traderAddress = vm.envAddress("TRADER");
        Trader trader = Trader(payable(traderAddress));
        console.log("ChainID:", block.chainid);
        require(address(trader) != address(0), "Please provide trader address via TRADER env var");
        console.log("Trader at", address(trader));

        vm.startBroadcast(deployerKey);

        trader.configurePeriod(block.number, 7200);
        trader.setSpending(0.00128 ether, 0.00328 ether, 1 ether);

        vm.stopBroadcast();
    }
}
