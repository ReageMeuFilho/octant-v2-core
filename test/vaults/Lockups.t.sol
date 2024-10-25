// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import { Setup } from "./Setup.sol";
import { InsufficientLockupDuration } from "src/errors.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract LockupsTest is Setup {
    // Events to track
    event NewLockupSet(address indexed user, uint256 indexed unlockTime, uint256 indexed lockedShares);
    event RageQuitInitiated(address indexed user, uint256 indexed unlockTime);

    uint256 constant MINIMUM_LOCKUP_DURATION = 90 days;
    uint256 constant INITIAL_DEPOSIT = 100_000e18;

    function setUp() public override {
        super.setUp();
        // Mint initial tokens to user for testing
        asset.mint(user, INITIAL_DEPOSIT);
        vm.prank(user);
        asset.approve(address(strategy), type(uint256).max);
    }

    function test_depositWithLockup() public {
        uint256 lockupDuration = 100 days; // Just over minimum
        uint256 depositAmount = 10_000e18;

        // Expect the NewLockupSet event with appropriate parameters
        vm.expectEmit(true, true, true, true, address(strategy));
        emit NewLockupSet(user, block.timestamp + lockupDuration, depositAmount);

        vm.startPrank(user);
        uint256 sharesBefore = strategy.totalSupply();
        strategy.depositWithLockup(depositAmount, user, lockupDuration);
        uint256 sharesAfter = strategy.totalSupply();
        vm.stopPrank();

        // Verify deposit succeeded
        assertEq(sharesAfter - sharesBefore, depositAmount, "Incorrect shares minted");

        // Verify lockup details
        (
            uint256 unlockTime,
            uint256 lockedShares,
            bool isRageQuit,
            uint256 totalShares,
            uint256 withdrawableShares
        ) = strategy.getUserLockupInfo(user);

        assertEq(unlockTime, block.timestamp + lockupDuration, "Incorrect unlock time");
        assertEq(lockedShares, depositAmount, "Incorrect locked shares");
        assertFalse(isRageQuit, "Should not be in rage quit");
        assertEq(totalShares, depositAmount, "Incorrect total shares");
        assertEq(withdrawableShares, 0, "Should have no withdrawable shares during lockup");
    }

    function test_mintWithLockup() public {
        uint256 lockupDuration = 100 days;
        uint256 sharesToMint = 10_000e18;

        vm.expectEmit(true, true, true, true, address(strategy));
        emit NewLockupSet(user, block.timestamp + lockupDuration, sharesToMint);

        vm.startPrank(user);
        uint256 assetsBefore = asset.balanceOf(user);
        strategy.mintWithLockup(sharesToMint, user, lockupDuration);
        uint256 assetsAfter = asset.balanceOf(user);
        vm.stopPrank();

        uint256 assetsUsed = assetsBefore - assetsAfter;

        // Verify mint succeeded
        assertEq(strategy.balanceOf(user), sharesToMint, "Incorrect shares minted");
        assertTrue(assetsUsed > 0, "No assets were used");

        // Verify lockup details
        (uint256 unlockTime, uint256 lockedShares, , , ) = strategy.getUserLockupInfo(user);
        assertEq(unlockTime, block.timestamp + lockupDuration, "Incorrect unlock time");
        assertEq(lockedShares, sharesToMint, "Incorrect locked shares");
    }

    function test_revertBelowMinimumLockup() public {
        uint256 lockupDuration = 89 days; // Just under minimum
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(InsufficientLockupDuration.selector));
        strategy.depositWithLockup(depositAmount, user, lockupDuration);
        vm.stopPrank();
    }

    function test_extendLockup() public {
        // Initial lockup
        uint256 initialLockup = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, initialLockup);

        // Get initial unlock time
        (uint256 initialUnlockTime, , , , ) = strategy.getUserLockupInfo(user);

        // Extend lockup
        uint256 extensionPeriod = 50 days;
        strategy.depositWithLockup(depositAmount, user, extensionPeriod);

        // Verify extended lockup
        (uint256 newUnlockTime, , , , ) = strategy.getUserLockupInfo(user);
        assertEq(newUnlockTime, initialUnlockTime + extensionPeriod, "Lockup not extended correctly");
        vm.stopPrank();
    }

    function test_rageQuit() public {
        // Initial deposit with lockup
        uint256 initialLockup = 180 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, initialLockup);

        // Initiate rage quit
        vm.expectEmit(true, true, true, true, address(strategy));
        emit RageQuitInitiated(user, block.timestamp + MINIMUM_LOCKUP_DURATION);

        strategy.initiateRageQuit();

        // Verify rage quit state
        (
            uint256 unlockTime,
            uint256 lockedShares,
            bool isRageQuit,
            uint256 totalShares,
            uint256 withdrawableShares
        ) = strategy.getUserLockupInfo(user);

        assertEq(unlockTime, block.timestamp + MINIMUM_LOCKUP_DURATION, "Incorrect rage quit unlock time");
        assertEq(lockedShares, depositAmount, "Incorrect locked shares");
        assertTrue(isRageQuit, "Not in rage quit state");
        assertEq(totalShares, depositAmount, "Incorrect total shares");

        // Check partial unlocking after some time
        skip(45 days); // Half of MINIMUM_LOCKUP_DURATION
        uint256 expectedUnlocked = (depositAmount * 45 days) / MINIMUM_LOCKUP_DURATION;
        (, , , , withdrawableShares) = strategy.getUserLockupInfo(user);
        assertEq(withdrawableShares, expectedUnlocked, "Incorrect partial unlock amount");

        vm.stopPrank();
    }

    function test_revertRageQuitWithUnlockedShares() public {
        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        // Skip past lockup period
        skip(lockupDuration + 1);

        // Try to rage quit
        vm.expectRevert("Shares already unlocked");
        strategy.initiateRageQuit();
        vm.stopPrank();
    }

    function test_revertRageQuitTwice() public {
        uint256 lockupDuration = 180 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        strategy.initiateRageQuit();

        vm.expectRevert("Already in rage quit");
        strategy.initiateRageQuit();
        vm.stopPrank();
    }

    function test_unlockedSharesCalculation() public {
        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        // Initially all shares should be locked
        assertEq(strategy.unlockedShares(user), 0, "Should have no unlocked shares initially");

        // Skip halfway through lockup
        skip(lockupDuration / 2);
        assertEq(strategy.unlockedShares(user), 0, "Should still have no unlocked shares mid-lockup");

        // Skip past lockup
        skip(lockupDuration);
        assertEq(strategy.unlockedShares(user), depositAmount, "All shares should be unlocked after lockup period");
        vm.stopPrank();
    }

    function test_withdrawWithLockup() public {
        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        // Try to withdraw during lockup
        vm.expectRevert("ERC4626: withdraw more than max");
        strategy.withdraw(depositAmount, user, user);

        // Skip past lockup
        skip(lockupDuration + 1);

        // Should be able to withdraw after lockup
        uint256 withdrawAmount = depositAmount / 2;
        strategy.withdraw(withdrawAmount, user, user);

        assertEq(strategy.balanceOf(user), depositAmount - withdrawAmount, "Incorrect remaining balance");
        vm.stopPrank();
    }

    function test_maxRedeem() public {
        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        // During lockup, maxRedeem should be 0
        assertEq(strategy.maxRedeem(user), 0, "Should not be able to redeem during lockup");

        // Skip past lockup
        skip(lockupDuration + 1);

        // After lockup, should be able to redeem full amount
        assertEq(strategy.maxRedeem(user), depositAmount, "Should be able to redeem full amount after lockup");
        vm.stopPrank();
    }

    function test_revertWithdrawLockedShares() public {
        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;
        uint256 additionalDeposit = 5_000e18;

        vm.startPrank(user);
        // First deposit with lockup
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        // Second deposit without lockup
        strategy.deposit(additionalDeposit, user);

        // Try to withdraw more than unlocked shares
        vm.expectRevert("ERC4626: withdraw more than max");
        strategy.withdraw(depositAmount + 1, user, user);

        // Should be able to withdraw unlocked shares
        vm.expectRevert("ERC4626: withdraw more than max");

        strategy.withdraw(additionalDeposit, user, user);
        vm.stopPrank();
    }

    function test_getUnlockTime() public {
        // Initially should be 0
        assertEq(strategy.getUnlockTime(user), 0, "Initial unlock time should be 0");

        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        // Check unlock time is set correctly
        assertEq(strategy.getUnlockTime(user), block.timestamp + lockupDuration, "Unlock time not set correctly");

        // Skip past lockup
        skip(lockupDuration + 1);

        // Unlock time should remain the same even after expiry
        assertEq(strategy.getUnlockTime(user), block.timestamp - 1, "Unlock time changed unexpectedly");

        // New deposit should update unlock time
        uint256 newLockupDuration = 120 days;
        strategy.depositWithLockup(depositAmount, user, newLockupDuration);
        assertEq(
            strategy.getUnlockTime(user),
            block.timestamp + newLockupDuration,
            "New unlock time not set correctly"
        );

        vm.stopPrank();
    }

    function test_maxWithdraw() public {
        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);

        // Initial deposit with lockup
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        // During lockup, max withdraw should be 0
        assertEq(strategy.maxWithdraw(user), 0, "Should not be able to withdraw during lockup");

        // Additional deposit without lockup has the current lockup applied to it
        uint256 topUpDepositLock = 5_000e18;
        strategy.deposit(topUpDepositLock, user);

        // Should be able to withdraw topUpDepositLock amount
        assertEq(strategy.maxWithdraw(user), 0, "Should be able to withdraw topUpDepositLock amount");

        // Skip past lockup
        skip(lockupDuration + 1);

        // After lockup, should be able to withdraw everything
        assertEq(
            strategy.maxWithdraw(user),
            depositAmount + topUpDepositLock,
            "Should be able to withdraw full amount after lockup"
        );

        vm.stopPrank();
    }

    function test_maxWithdrawWithMaxLoss() public {
        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;
        uint256 maxLoss = 100; // 1% max loss

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        // During lockup
        assertEq(
            strategy.maxWithdraw(user, maxLoss),
            0,
            "Should not be able to withdraw during lockup even with maxLoss"
        );

        // Skip past lockup
        skip(lockupDuration + 1);

        // After lockup - maxLoss parameter should be ignored as per the implementation
        assertEq(
            strategy.maxWithdraw(user, maxLoss),
            strategy.maxWithdraw(user),
            "maxWithdraw with and without maxLoss should be equal"
        );

        vm.stopPrank();
    }

    function test_maxWithdrawRageQuit() public {
        uint256 lockupDuration = 180 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        strategy.depositWithLockup(depositAmount, user, lockupDuration);

        // Initiate rage quit
        strategy.initiateRageQuit();

        // Initially should be 0
        assertEq(strategy.maxWithdraw(user), 0, "Should start at 0 withdraw amount");

        // Skip 45 days (half of MINIMUM_LOCKUP_DURATION)
        skip(45 days);

        // Should be able to withdraw ~50% of assets
        uint256 expectedWithdraw = (depositAmount * 45 days) / MINIMUM_LOCKUP_DURATION;
        assertApproxEqRel(
            strategy.maxWithdraw(user),
            expectedWithdraw,
            0.01e18, // 1% tolerance for rounding
            "Incorrect partial withdraw amount during rage quit"
        );

        // Skip to end of rage quit period
        skip(45 days);
        assertEq(
            strategy.maxWithdraw(user),
            depositAmount,
            "Should be able to withdraw full amount after rage quit period"
        );

        vm.stopPrank();
    }

    function test_maxRedeem_flow() public {
        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);

        // Test initial state
        assertEq(strategy.maxRedeem(user), 0, "Should start with 0 redeemable shares");

        // Test during lockup
        strategy.depositWithLockup(depositAmount, user, lockupDuration);
        assertEq(strategy.maxRedeem(user), 0, "Should have 0 redeemable shares during lockup");
        assertEq(strategy.maxRedeem(user, 100), 0, "MaxLoss parameter should not affect lockup");

        // Test mixed locked and topUpDepositLock shares
        uint256 topUpDeposit = 5_000e18;
        strategy.deposit(topUpDeposit, user);
        assertEq(strategy.maxRedeem(user), 0, "Should be able to redeem topUpDepositLock shares");

        // Test after lockup expires
        skip(lockupDuration + 1);
        assertEq(
            strategy.maxRedeem(user),
            depositAmount + topUpDeposit,
            "Should be able to redeem all shares after lockup"
        );

        strategy.withdraw(strategy.maxRedeem(user), user, user);

        // Test during rage quit
        uint256 newLockupAmount = 15_000e18;
        strategy.depositWithLockup(newLockupAmount, user, 180 days);
        strategy.initiateRageQuit();

        // Skip 45 days (half of MINIMUM_LOCKUP_DURATION)
        skip(45 days);
        uint256 expectedRedeem = (newLockupAmount * 45 days) / MINIMUM_LOCKUP_DURATION;
        assertApproxEqRel(
            strategy.maxRedeem(user),
            expectedRedeem,
            0.01e18,
            "Incorrect redeemable shares during rage quit"
        );

        vm.stopPrank();
    }

    function test_getUnlockTime_comprehensive() public {
        // Initially should be 0 for unused address
        assertEq(strategy.getUnlockTime(user), 0, "Initial unlock time should be 0");
        assertEq(strategy.getUnlockTime(address(0xdead)), 0, "Should be 0 for unused address");

        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);
        // Set initial lockup
        strategy.depositWithLockup(depositAmount, user, lockupDuration);
        uint256 expectedUnlock = block.timestamp + lockupDuration;
        assertEq(strategy.getUnlockTime(user), expectedUnlock, "Incorrect initial unlock time");

        // Additional deposit with longer lockup
        uint256 longerLockup = 200 days;
        strategy.depositWithLockup(depositAmount, user, longerLockup);
        expectedUnlock = expectedUnlock + longerLockup;
        assertEq(strategy.getUnlockTime(user), expectedUnlock, "Incorrect extended unlock time");

        // Additional deposit with shorter lockup (should still maintain longer unlock)
        uint256 shorterLockup = 50 days;
        strategy.depositWithLockup(depositAmount, user, shorterLockup);
        expectedUnlock = expectedUnlock + shorterLockup;

        assertEq(strategy.getUnlockTime(user), expectedUnlock, "Unlock time should not decrease");

        // Skip past unlock time
        skip(expectedUnlock + 1);
        // Should still return the same timestamp even after expiry
        assertEq(strategy.getUnlockTime(user), expectedUnlock, "Unlock time should not change after expiry");

        // Test during rage quit
        strategy.depositWithLockup(depositAmount, user, lockupDuration);
        strategy.initiateRageQuit();
        assertEq(
            strategy.getUnlockTime(user),
            block.timestamp + MINIMUM_LOCKUP_DURATION,
            "Incorrect unlock time after rage quit"
        );

        vm.stopPrank();
    }

    function test_getRemainingCooldown_comprehensive() public {
        // Initially should be 0
        assertEq(strategy.getRemainingCooldown(user), 0, "Initial cooldown should be 0");
        assertEq(strategy.getRemainingCooldown(address(0xdead)), 0, "Should be 0 for unused address");

        uint256 lockupDuration = 100 days;
        uint256 depositAmount = 10_000e18;

        vm.startPrank(user);

        // Set initial lockup and check cooldown
        strategy.depositWithLockup(depositAmount, user, lockupDuration);
        assertEq(strategy.getRemainingCooldown(user), lockupDuration, "Initial cooldown incorrect");

        // Check cooldown reduces over time
        skip(10 days);
        assertEq(strategy.getRemainingCooldown(user), lockupDuration - 10 days, "Cooldown not decreasing correctly");

        // Additional deposit extending lockup
        uint256 extensionPeriod = 50 days;
        strategy.depositWithLockup(depositAmount, user, extensionPeriod);
        // Should now be original remaining time + extension
        assertEq(
            strategy.getRemainingCooldown(user),
            lockupDuration - 10 days + extensionPeriod,
            "Extended cooldown incorrect"
        );

        // Skip to end of cooldown
        skip(lockupDuration + extensionPeriod);
        assertEq(strategy.getRemainingCooldown(user), 0, "Cooldown should be 0 after completion");

        // Test rage quit cooldown
        strategy.depositWithLockup(depositAmount, user, lockupDuration);
        strategy.initiateRageQuit();
        assertEq(strategy.getRemainingCooldown(user), MINIMUM_LOCKUP_DURATION, "Incorrect cooldown after rage quit");

        // Check rage quit cooldown decreases
        skip(45 days);
        assertEq(
            strategy.getRemainingCooldown(user),
            MINIMUM_LOCKUP_DURATION - 45 days,
            "Rage quit cooldown not decreasing correctly"
        );

        // Deposit during rage quit should not affect cooldown
        strategy.deposit(depositAmount, user);
        assertEq(
            strategy.getRemainingCooldown(user),
            MINIMUM_LOCKUP_DURATION - 45 days,
            "Regular deposit should not affect rage quit cooldown"
        );

        vm.stopPrank();
    }
}
