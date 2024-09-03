/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "solady/src/tokens/ERC20.sol";
import "solady/src/tokens/WETH.sol";
import "src/routers-transformers/Converter.sol";
import {HelperConfig} from "script/helpers/HelperConfig.s.sol";
import {UniswapLiquidityHelper} from "script/helpers/UniswapLiquidityHelper.s.sol";

contract ConverterIntegrationWrapper is Test {
    Converter public conv;
    ERC20 public glm;
    WETH public weth;

    function setUp() public {
        uint forkId = vm.createFork("mainnet");
        vm.selectFork(forkId);
        (
            address glmToken,
            address wethToken,
            address _nonfungiblePositionManager,
            uint256 _deployerKey,
            address router,
            address pool
        ) = new HelperConfig().activeNetworkConfig();
        glm = ERC20(glmToken);
        weth = WETH(payable(wethToken));
        conv = new Converter(pool, router, glmToken, wethToken);
        conv.setSpendADay(
            type(uint256).max - 1,
            1_000_000_000_000 ether,
            1 ether,
            2 ether
        );
        vm.deal(address(conv), 1000 ether);
        conv.wrap();
    }

    function test_integration() public {
        vm.roll(block.number + 100);
        uint256 wethBefore = weth.balanceOf(address(conv));
        uint256 glmBefore = glm.balanceOf(address(conv));
        conv.buy();
        uint256 wethAfter = weth.balanceOf(address(conv));
        uint256 glmAfter = glm.balanceOf(address(conv));
        assertLt(wethAfter, wethBefore);
        assertGt(glmAfter, glmBefore);
        assertGt(glmAfter - glmBefore, 5000 ether);
    }
}
