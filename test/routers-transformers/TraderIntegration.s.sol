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

    function setUp() public {
        _configure(true);
        moduleImplementation = new Trader();
        temps = _testTemps(address(moduleImplementation), abi.encode(0, 0, 0.6 ether, 1.4 ether));
        trader = Trader(payable(temps.module));
        vm.deal(address(trader), budget);
    }

    function testCheckModuleInitialization() public view {
        assertTrue(trader.owner() == temps.safe);
        assertTrue(trader.chance() == 0);
        assertTrue(trader.spendADay() == 0);
        assertTrue(trader.saleValueLow() == 0.6 ether);
        assertTrue(trader.saleValueHigh() == 1.4 ether);
    }

    receive() external payable {}

    function test_simpleBuy() external {
        // effectively disable randomness check
        uint256 chance = type(uint256).max;
        // effectively disable upper bound check
        uint256 spendADay = 1_000_000_000_000 ether;
        vm.startPrank(temps.safe);
        trader.setSpendADay(chance, spendADay, 1 ether, 1 ether);
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
