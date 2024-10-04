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
        uint256 forkId = vm.createFork("sepolia");
        vm.selectFork(forkId);
        (address glmToken, address wethToken,,, address router, address pool,) =
            new HelperConfig().activeNetworkConfig();
        glm = ERC20(glmToken);
        weth = WETH(payable(wethToken));
        conv = new Converter(pool, router, glmToken, wethToken);
        conv.setSpendADay(type(uint256).max - 1, 1_000_000_000_000 ether, 1 ether, 2 ether);
        vm.deal(address(this), 1000 ether);
        (bool success,) = payable(address(conv)).call{value: 1000 ether}("");
        require(success);
    }

    receive() external payable {}

    function test_integration() public {
        vm.roll(block.number + 100);
        uint256 ethBefore = address(conv).balance;
        conv.buy(block.number - 1);
        uint256 ethAfter = address(conv).balance;
        assertLt(ethAfter, ethBefore);
    }
}
