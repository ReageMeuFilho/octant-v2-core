/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../Base.t.sol";
import "src/routers-transformers/Trader.sol";
import {HelperConfig} from "script/helpers/HelperConfig.s.sol";

contract TestTraderConfig is BaseTest {
    uint256 public constr = 0;
    uint256 public budget = 10_000 ether;
    HelperConfig helperConfig = new HelperConfig();

    testTemps temps;
    Trader public moduleImplementation;
    Trader public trader;

    function setUp() public override {
        configure(true);
        moduleImplementation = new Trader();
        temps = _testTemps(address(moduleImplementation), abi.encode());
        trader = Trader(payable(temps.module));
        vm.deal(address(trader), budget);
    }

    function testCheckModuleInitialization() public view {
        assertTrue(trader.owner() == temps.safe);
    }

    function testConfiguration() public {
        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, 1 ether, block.number + 102);
        vm.stopPrank();
        assertEq(trader.getSafetyBlocks(), 1);
        assertEq(trader.deadline(), block.number + 102);
        assertEq(trader.remainingBlocks(), 101);
        assertTrue(trader.chance() > 0);
        assertTrue(trader.saleValueLow() == 1 ether);
        assertTrue(trader.saleValueHigh() == 1 ether);
    }

    receive() external payable {}

    function test_simpleBuy() external {
        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 1 ether;
        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, fakeBudget, block.number + 101);
        vm.stopPrank();
        vm.roll(block.number + 100);
        trader.convert(block.number - 2);
        assertEq(trader.spent(), 1 ether);
    }

    function test_receivesEth() external {
        (bool sent,) = payable(address(trader)).call{value: 100000}("");
        require(sent, "Failed to send Ether");
    }
}
