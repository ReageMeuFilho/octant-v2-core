// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Converter} from "../src/routers-transformers/Converter.sol";

contract DeployTraderHelper is Script {
    function run() external {
        (,,, uint256 deployerKey,,, address demoConverter) = new HelperConfig().activeNetworkConfig();

        console.log("Converter at ", demoConverter);
        assert(demoConverter != address(0));

        Converter conv = Converter(payable(demoConverter));

        vm.startBroadcast(deployerKey);

        uint256 chance = type(uint256).max / uint256(20); // corresponds to 1 in 20 chance, 360 trades a day
        uint256 spendADay = 1 ether;
        conv.setSpendADay(chance, spendADay, 0.00277 ether, 0.0035 ether); // will overspend a bit

        vm.stopBroadcast();
    }
}
