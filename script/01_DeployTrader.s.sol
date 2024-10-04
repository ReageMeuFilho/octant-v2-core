// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Converter} from "../src/routers-transformers/Converter.sol";

contract DeployTraderHelper is Script {
    function run() external {
        (
            address glmToken,
            address wethToken,
            address _nPM,
            uint256 deployerKey,
            address uniswapV3Router,
            address uniswapGlmWethPool,
            address _demoConverter
        ) = new HelperConfig().activeNetworkConfig();

        console.log("Glm Token: ", glmToken);
        console.log("Weth Token: ", wethToken);

        vm.startBroadcast(deployerKey);

        Converter conv = new Converter(uniswapGlmWethPool, uniswapV3Router, glmToken, wethToken);

        vm.stopBroadcast();

        console.log("Converter deployed to: ", address(conv));
    }
}
