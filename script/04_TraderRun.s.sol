// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "solady/src/tokens/ERC20.sol";
import "solady/src/tokens/WETH.sol";

import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Converter} from "../src/routers-transformers/Converter.sol";

contract TraderRun is Script {
    function run() external {
        (
            address glmToken,
            address wethToken,
            address _nPM,
            uint256 deployerKey,
            address _uniswapV3Router,
            address _uniswapGlmWethPool,
            address demoConverter
        ) = new HelperConfig().activeNetworkConfig();

        console.log("ChainID:", block.chainid);
        console.log("Converter at", demoConverter);
        assert(demoConverter != address(0));

        vm.startBroadcast(deployerKey);

        Converter conv = Converter(payable(demoConverter));
        conv.buy(block.number - 1);

        vm.stopBroadcast();
    }
}
