// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import { Setup } from "./Setup.sol";
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
        vm.expectRevert("InsufficientLockupDuration");
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
}

