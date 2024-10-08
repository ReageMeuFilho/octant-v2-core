// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Trader} from "../src/routers-transformers/Trader.sol";

contract DeployTraderHelper is Script {
    function run() external {
        (,,, uint256 deployerKey,,, address trader) = new HelperConfig().activeNetworkConfig();

        console.log("Trader at ", trader);
        assert(trader != address(0));

        Trader conv = Trader(payable(trader));

        vm.startBroadcast(deployerKey);

        uint256 chance = type(uint256).max / uint256(10); // corresponds to 1 in 10 chance, 720 trades a day
        uint256 spendADay = 1 ether;
        conv.setSpendADay(chance, spendADay, 0.00128 ether, 0.00328 ether); // will overspend a bit

        vm.stopBroadcast();
    }
}
