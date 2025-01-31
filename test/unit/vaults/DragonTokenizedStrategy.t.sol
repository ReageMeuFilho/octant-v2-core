// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { DragonTokenizedStrategy } from "src/dragons/vaults/DragonTokenizedStrategy.sol";
import { MockStrategy } from "test/mocks/MockStrategy.sol";
import { MockYieldSource } from "test/mocks/MockYieldSource.sol";
import { TokenizedStrategy__NotOperator, DragonTokenizedStrategy__InsufficientLockupDuration, DragonTokenizedStrategy__RageQuitInProgress, DragonTokenizedStrategy__SharesStillLocked, DragonTokenizedStrategy__StrategyInShutdown, DragonTokenizedStrategy__SharesAlreadyUnlocked, DragonTokenizedStrategy__NoSharesToRageQuit, DragonTokenizedStrategy__ZeroLockupDuration, DragonTokenizedStrategy__WithdrawMoreThanMax, DragonTokenizedStrategy__RedeemMoreThanMax, TokenizedStrategy__TransferFailed, ZeroAssets, ZeroShares, DragonTokenizedStrategy__DepositMoreThanMax, DragonTokenizedStrategy__MintMoreThanMax, ERC20InsufficientBalance } from "src/errors.sol";
import { BaseTest } from "../Base.t.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";

contract DragonTokenizedStrategyTest is BaseTest {
    address keeper = makeAddr("keeper");
    address treasury = makeAddr("treasury");
    address dragonRouter = makeAddr("dragonRouter");
    address management = makeAddr("management");
    address regenGovernance = makeAddr("regenGovernance");
    address operator = makeAddr("operator");
    address randomUser = makeAddr("randomUser");
    testTemps temps;
    MockStrategy moduleImplementation;
    DragonTokenizedStrategy module;
    MockYieldSource yieldSource;
    DragonTokenizedStrategy tokenizedStrategyImplementation;
    string public name = "Test Mock Strategy";
    uint256 public maxReportDelay = 9;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // using this address to represent native ETH

    function setUp() public {
        _configure(true, "eth");

        moduleImplementation = new MockStrategy();
        yieldSource = new MockYieldSource(ETH);
        tokenizedStrategyImplementation = new DragonTokenizedStrategy();
        temps = _testTemps(
            address(moduleImplementation),
            abi.encode(
                address(tokenizedStrategyImplementation),
                ETH,
                address(yieldSource),
                management,
                keeper,
                dragonRouter,
                maxReportDelay,
                name,
                regenGovernance
            )
        );
        module = DragonTokenizedStrategy(payable(temps.module));

        operator = temps.safe;
    }

    /// @dev tests if initial params are set correctly.
    function testInitialize() public view {
        assertTrue(ITokenizedStrategy(address(module)).management() == management);
        assertTrue(ITokenizedStrategy(address(module)).keeper() == keeper);
        assertTrue(ITokenizedStrategy(address(module)).operator() == operator);
        assertTrue(ITokenizedStrategy(address(module)).dragonRouter() == dragonRouter);
    }

    // DEMO: A dragon is able to toggle the feature switch to enable deposits by others
    function test_dragonCanToggleDragonMode() public {
        // Non-dragon can't toggle
        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(TokenizedStrategy__NotOperator.selector));
        module.toggleDragonMode(false);

        // Non-dragon can't deposit
        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(TokenizedStrategy__NotOperator.selector));
        module.deposit(1e18, randomUser);

        // Dragon can toggle
        vm.prank(operator);
        module.toggleDragonMode(false);
        assertFalse(module.isDragonOnly(), "Should exit dragon mode");

        // Non-dragon can deposit
        uint x = 10;
        uint y = 9;
        assertEq(x, y + 1, "x should be greater than y");
        vm.deal(temps.safe, x * 1e18);
        vm.prank(randomUser);
        module.deposit(y * 1e18, randomUser);

        // Toggle back
        vm.prank(operator);
        module.toggleDragonMode(true);
        assertTrue(module.isDragonOnly(), "Should enter dragon mode");

        // Non-dragon can't deposit
        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(TokenizedStrategy__NotOperator.selector));
        module.deposit(1 ether, randomUser);
    }

    // DEMO: A non-safe user can deposit(withLockup) when dragon mode is off
    function test_nonSafeUserCanDepositWhenDragonModeOff() public {
        // Toggle dragon mode off to allow non-safe deposits
        vm.prank(operator);
        module.toggleDragonMode(false);

        uint256 depositAmount = 1e18;
        vm.deal(temps.safe, depositAmount * 2);

        // Use different receivers for each deposit type
        address depositReceiver = makeAddr("depositReceiver");
        address depositWithLockupReceiver = makeAddr("lockupReceiver");

        vm.startPrank(randomUser);
        // Regular deposit to depositReceiver
        module.deposit(depositAmount, depositReceiver);

        // Lockup deposit to lockupReceiver
        uint256 lockupDuration = 91 days;
        module.depositWithLockup(depositAmount, depositWithLockupReceiver, lockupDuration);
        vm.stopPrank();

        // Verify balances
        assertEq(module.balanceOf(depositReceiver), depositAmount, "Regular deposit failed");
        assertEq(module.balanceOf(depositWithLockupReceiver), depositAmount, "Lockup deposit failed");

        // Verify lockup applied only to lockupReceiver
        (, uint256 lockedShares, , , ) = module.getUserLockupInfo(depositWithLockupReceiver);
        assertEq(lockedShares, depositAmount, "Lockup not enforced");
    }
}
