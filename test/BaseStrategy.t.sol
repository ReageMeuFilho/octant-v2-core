// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";
import { MockStrategy } from "./mocks/MockStrategy.sol";
import { MockYieldSource } from "./mocks/MockYieldSource.sol";
import { MockTokenizedStrategy } from "./mocks/MockTokenizedStrategy.sol";

import { ITokenizedStrategy } from "../src/interfaces/ITokenizedStrategy.sol";

contract BaseStrategyTest is BaseTest {
    address keeper = makeAddr("keeper");
    address treasury = makeAddr("treasury");
    address dragonRouter = makeAddr("dragonRouter");
    address management = makeAddr("management");

    testTemps temps;
    MockStrategy moduleImplementation;
    MockStrategy module;
    MockYieldSource yieldSource;
    MockTokenizedStrategy tokenizedStrategyImplementation;

    string public name = "Test Mock Strategy";
    uint256 public maxReportDelay = 9;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // using this address to represent native ETH

    function setUp() public override {
        super.setUp();
        moduleImplementation = new MockStrategy();
        yieldSource = new MockYieldSource(ETH);
        tokenizedStrategyImplementation = new MockTokenizedStrategy();
        temps = _testTemps(
            address(moduleImplementation),
            abi.encode(address(tokenizedStrategyImplementation), ETH, address(yieldSource), management, keeper, dragonRouter, maxReportDelay, name)
        );
        module = MockStrategy(payable(temps.module));
    }

    /// @dev tests if initial params are set correctly.
    function testInitialize() public {
        assertTrue(module.tokenizedStrategyImplementation() == address(tokenizedStrategyImplementation));
        assertTrue(module.maxReportDelay() == maxReportDelay);
        assertTrue(ITokenizedStrategy(address(module)).management() == management);
        assertTrue(ITokenizedStrategy(address(module)).keeper() == keeper);
        assertTrue(ITokenizedStrategy(address(module)).owner() == temps.safe);
        assertTrue(ITokenizedStrategy(address(module)).dragonRouter() == dragonRouter);
    }

    function testDeployFunds() public {
        // add some assets to the safe
        uint256 amount = 1 ether;
        vm.deal(temps.safe, amount);

        // only safe can call deposit function
        vm.expectRevert("Unauthorized");
        ITokenizedStrategy(address(module)).deposit(amount, temps.safe);

        vm.startPrank(temps.safe);

        assertTrue(ITokenizedStrategy(address(module)).balanceOf(temps.safe) == 0);
        assertTrue(address(yieldSource).balance == 0);
        ITokenizedStrategy(address(module)).deposit(amount, temps.safe);
        assertTrue(ITokenizedStrategy(address(module)).balanceOf(temps.safe) == amount);
        assertTrue(address(yieldSource).balance == amount);

        vm.stopPrank();
    }

    function testfreeFunds() public {
        /// Setup
        uint256 amount = 1 ether;
        _deposit(amount);

        uint256 withdrawAmount = 0.5 ether;
        // only safe can call withdraw function
        vm.expectRevert("Unauthorized");
        ITokenizedStrategy(address(module)).withdraw(withdrawAmount, temps.safe, temps.safe, type(uint256).max);

        vm.startPrank(temps.safe);
        
        assertTrue(ITokenizedStrategy(address(module)).balanceOf(temps.safe) == amount);
        assertTrue(address(yieldSource).balance == amount);
        ITokenizedStrategy(address(module)).withdraw(withdrawAmount, temps.safe, temps.safe, type(uint256).max);
        assertTrue(ITokenizedStrategy(address(module)).balanceOf(temps.safe) == amount - withdrawAmount);
        assertTrue(address(yieldSource).balance == amount - withdrawAmount);

        vm.stopPrank();
    }
    function testharvestAndReport() public {
        /// Setup
        uint256 amount = 1 ether;
        _deposit(amount);

        uint256 harvestedAmount = 0.1 ether;
        vm.deal(address(yieldSource), amount + harvestedAmount);
        ITokenizedStrategy(address(module)).report();
        assertTrue(dragonRouter.balance == harvestedAmount);
    }
    function testTendThis() public {
        // tend works only through keepers
        vm.expectRevert("!keeper");
        ITokenizedStrategy(address(module)).tend();

        vm.startPrank(keeper);

        uint256 idleFunds = 1 ether;
        vm.deal(address(module), idleFunds);
        
        assertTrue(address(module).balance == idleFunds);
        assertTrue(address(yieldSource).balance == 0);
        ITokenizedStrategy(address(module)).tend();
        assertTrue(address(module).balance == 0);
        assertTrue(address(yieldSource).balance == idleFunds);

        vm.stopPrank();

    }

    function _deposit(uint256 _amount) internal {
        vm.deal(temps.safe, _amount);
        vm.prank(temps.safe);
        ITokenizedStrategy(address(module)).deposit(_amount, temps.safe);
    }
}
