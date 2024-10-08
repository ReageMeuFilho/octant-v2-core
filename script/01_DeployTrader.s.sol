// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Trader} from "../src/routers-transformers/Trader.sol";

contract DeployTraderHelper is Script {
    function run() external {
        (, address wethToken,, uint256 deployerKey,,,) = new HelperConfig().activeNetworkConfig();

        console.log("Weth Token: ", wethToken);

        vm.startBroadcast(deployerKey);

        Trader conv = new Trader(wethToken);

        vm.stopBroadcast();

        console.log("Trader deployed to: ", address(conv));
    }
}
