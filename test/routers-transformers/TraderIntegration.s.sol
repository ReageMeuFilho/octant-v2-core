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

    address swapper = makeAddr("swapper");

    function setUp() public {
        _configure(true);
        helperConfig = new HelperConfig();
        moduleImplementation = new Trader();
        temps = _testTemps(address(moduleImplementation), abi.encode(ETH, swapper));
        trader = Trader(payable(temps.module));
    }

    function testCheckModuleInitialization() public view {
        assertTrue(trader.owner() == temps.safe);
        assertTrue(trader.swapper() == swapper);
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

    function test_sellEth() external {
        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 1 ether;
        vm.deal(address(trader), 2 ether);

        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, fakeBudget, block.number + 101);
        vm.stopPrank();

        uint256 oldBalance = swapper.balance;
        vm.roll(block.number + 100);
        trader.convert(block.number - 2);
        assertEq(trader.spent(), 1 ether);
        assertGt(swapper.balance, oldBalance);
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

    address swapper = makeAddr("swapper");

    function setUp() public {
        helperConfig = new HelperConfig();
        _configure(true);
        moduleImplementation = new Trader();

        temps = _testTemps(address(moduleImplementation), abi.encode(address(token), swapper));
        trader = Trader(payable(temps.module));
    }

    function testCheckModuleInitialization() public view {
        assertTrue(IERC20(trader.token()).balanceOf(address(trader.owner())) > 0);
    }

    receive() external payable {}

    function test_sellERC20() external {
        uint256 fakeBudget = 1 ether;
        token.mint(address(trader), 2 ether);

        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, fakeBudget, block.number + 101);
        vm.stopPrank();
        vm.roll(block.number + 100);

        uint256 oldBalance = token.balanceOf(swapper);
        trader.convert(block.number - 2);
        assertEq(trader.spent(), 1 ether);
        assertGt(token.balanceOf(swapper), oldBalance);
    }
}
