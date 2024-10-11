/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "src/routers-transformers/Trader.sol";
import {HelperConfig} from "script/helpers/HelperConfig.s.sol";

contract TraderIntegrationWrapper is Test {
    Trader public conv;

    function setUp() public {
        uint256 forkId = vm.createFork("sepolia");
        vm.selectFork(forkId);
        conv = new Trader();
        conv.setSpendADay(type(uint256).max - 1, 1_000_000_000_000 ether, 1 ether, 2 ether);
        vm.deal(address(this), 1000 ether);
        (bool success,) = payable(address(conv)).call{value: 1000 ether}("");
        require(success);
    }

    receive() external payable {}

    function test_integration() public {
        vm.roll(block.number + 100);
        uint256 ethBefore = address(conv).balance;
        conv.convert(block.number - 1);
        uint256 ethAfter = address(conv).balance;
        assertLt(ethAfter, ethBefore);
    }
}
