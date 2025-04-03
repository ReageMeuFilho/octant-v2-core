// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import { HelperConfig } from "../helpers/HelperConfig.s.sol";
import { UniswapLiquidityHelper } from "../helpers/UniswapLiquidityHelper.s.sol";

contract UniswapLiquidityHelperDeployer is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig(false);

        (
            address glmToken,
            address wethToken,
            address nonfungiblePositionManager,
            uint256 deployerKey,
            ,
            ,
            ,
            ,
            ,

        ) = helperConfig.activeNetworkConfig();
        console.log("Glm Token: ", glmToken);
        console.log("Weth Token: ", wethToken);
        console.log("nonfungiblePositionManager: ", nonfungiblePositionManager);

        vm.startBroadcast(deployerKey);

        UniswapLiquidityHelper uniswapLiquidityHelper = new UniswapLiquidityHelper(
            glmToken,
            wethToken,
            nonfungiblePositionManager,
            10000
        );

        vm.stopBroadcast();

        console.log("UniswapLiquidityHelper deployed to: ", address(uniswapLiquidityHelper));
    }
}
