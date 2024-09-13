// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Converter} from "../src/routers-transformers/Converter.sol";

contract DeployTraderHelper is Script {
    function run() external {
        (
            address _glmToken,
            address _wethToken,
            address _nPM,
            uint256 deployerKey,
            address _uniswapV3Router,
            address _uniswapGlmWethPool,
            address demoConverter
        ) = new HelperConfig().activeNetworkConfig();

        console.log("Converter at ", demoConverter);
        assert(demoConverter != address(0));

        Converter conv = Converter(payable(demoConverter));

        vm.startBroadcast(deployerKey);

        uint256 chance = type(uint256).max / uint256(2); // corresponds to 1 in 2 chance, 3600 trades a day
        uint256 spendADay = 1 ether;
        conv.setSpendADay(chance, spendADay, 0.0001 ether, 0.0003 ether);

        /* uint256 chance = type(uint256).max / uint256(10); // corresponds to 1 in 10 chance, 720 trades a day */
        /* uint256 spendADay = 1 ether; */
        /* conv.setSpendADay(chance, spendADay, 0.002 ether, 0.003 ether); // this overspends a bit, 1.8 a day */

        vm.stopBroadcast();
    }
}
