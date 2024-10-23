// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../Base.t.sol";
import "src/routers-transformers/Trader.sol";
import {HelperConfig} from "script/helpers/HelperConfig.s.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestTraderIntegrationETH is BaseTest {
    HelperConfig helperConfig;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    testTemps temps;
    Trader public moduleImplementation;
    Trader public trader;

    function setUp() public {
        helperConfig = new HelperConfig();
        _configure(true);
        moduleImplementation = new Trader();
        temps = _testTemps(address(moduleImplementation), abi.encode(ETH, 0, 0, 0.6 ether, 1.4 ether));
        trader = Trader(payable(temps.module));
    }

    function testCheckModuleInitialization() public view {
        assertTrue(trader.owner() == temps.safe);
        assertTrue(trader.chance() == 0);
        assertTrue(trader.spendADay() == 0);
        assertTrue(trader.saleValueLow() == 0.6 ether);
        assertTrue(trader.saleValueHigh() == 1.4 ether);
    }

    receive() external payable {}

    function test_sellEth() external {
        vm.deal(address(trader), 10_000 ether);
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
        vm.deal(address(this), 10_000 ether);
        (bool sent,) = payable(address(trader)).call{value: 100 ether}("");
        require(sent, "Failed to send Ether");
    }
}

contract TestTraderIntegrationIERC20 is BaseTest {
    HelperConfig helperConfig;
    testTemps temps;
    Trader public moduleImplementation;
    Trader public trader;

    function setUp() public {
        helperConfig = new HelperConfig();
        _configure(true);
        moduleImplementation = new Trader();

        temps = _testTemps(address(moduleImplementation), abi.encode(address(token), 0, 0, 0.6 ether, 1.4 ether));
        trader = Trader(payable(temps.module));
    }

    function testCheckModuleInitialization() public view {
        assertTrue(IERC20(trader.token()).balanceOf(address(trader.owner())) > 0);
    }

    receive() external payable {}

    function test_sellERC20() external {
        token.mint(address(trader), 10_000 ether);

        // effectively disable randomness check
        uint256 chance = type(uint256).max;
        // effectively disable upper bound check
        uint256 spendADay = 1_000_000_000_000 ether;
        vm.startPrank(temps.safe);
        trader.setSpendADay(chance, spendADay, 1 ether, 1 ether);
        vm.stopPrank();
        vm.roll(block.number + 100);

        uint256 oldBalance = token.balanceOf(trader.owner());
        trader.convert(block.number - 2);
        assertEq(trader.spent(), 1 ether);
        assertGt(token.balanceOf(trader.owner()), oldBalance);
    }
}
