// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { Staker } from "staker/Staker.sol";

/**
 * @title REG-008 Compound Whitelist Bypass Demo
 * @dev Demonstrates access control bypass in compoundRewards function
 *
 * VULNERABILITY: Non-whitelisted depositors can increase stake via whitelisted claimers
 * ROOT CAUSE: Missing depositor whitelist check when claimer calls compoundRewards
 * IMPACT: Bypasses access control for previously delisted users
 * SEVERITY: High
 */
contract REG008CompoundWhitelistBypassDemoTest is Test {
    RegenStaker public regenStaker;
    MockERC20Staking public stakeToken;
    Whitelist public stakerWhitelist;

    address public admin = makeAddr("admin");
    address public rewardNotifier = makeAddr("rewardNotifier");
    address public depositor = makeAddr("depositor");
    address public whitelistedClaimer = makeAddr("whitelistedClaimer");

    uint256 public constant STAKE_AMOUNT = 100 ether;
    uint256 public constant REWARD_AMOUNT = 50 ether;

    function setUp() public {
        vm.startPrank(admin);

        stakeToken = new MockERC20Staking(18);
        stakerWhitelist = new Whitelist();
        Whitelist earningPowerWhitelist = new Whitelist();
        RegenEarningPowerCalculator calc = new RegenEarningPowerCalculator(address(this), earningPowerWhitelist);

        regenStaker = new RegenStaker(
            stakeToken,
            stakeToken,
            calc,
            1000,
            admin,
            30 days,
            0,
            0,
            stakerWhitelist,
            new Whitelist(),
            new Whitelist()
        );

        regenStaker.setRewardNotifier(rewardNotifier, true);

        // Initially whitelist both users
        stakerWhitelist.addToWhitelist(depositor);
        stakerWhitelist.addToWhitelist(whitelistedClaimer);
        earningPowerWhitelist.addToWhitelist(depositor);
        earningPowerWhitelist.addToWhitelist(whitelistedClaimer);

        stakeToken.mint(depositor, STAKE_AMOUNT);
        stakeToken.mint(rewardNotifier, REWARD_AMOUNT);

        vm.stopPrank();
    }

    function testREG008_WhitelistBypassViaCompound() public {
        // Step 1: Depositor stakes with whitelisted claimer
        vm.startPrank(depositor);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, makeAddr("delegatee"), whitelistedClaimer);
        vm.stopPrank();

        // Step 2: Start rewards and accumulate some
        vm.startPrank(rewardNotifier);
        stakeToken.approve(address(regenStaker), REWARD_AMOUNT);
        stakeToken.transfer(address(regenStaker), REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);

        // Step 3: Admin removes depositor from whitelist (e.g., compliance issue)
        vm.prank(admin);
        stakerWhitelist.removeFromWhitelist(depositor);

        // Verify depositor is no longer whitelisted
        assertFalse(stakerWhitelist.isWhitelisted(depositor));
        assertTrue(stakerWhitelist.isWhitelisted(whitelistedClaimer));

        // Step 4: FIX VERIFIED - Whitelisted claimer can no longer compound for delisted depositor
        // This now correctly reverts with NotWhitelisted error
        vm.prank(whitelistedClaimer);
        vm.expectRevert(); // Expected to revert with NotWhitelisted
        regenStaker.compoundRewards(depositId);
        
        // Verify balance unchanged - compound was correctly blocked
        uint256 balanceAfter = stakeToken.balanceOf(address(regenStaker.surrogates(makeAddr("delegatee"))));
        assertEq(balanceAfter, STAKE_AMOUNT); // No increase from compounding
    }

    function testREG008_DirectDepositBlockedButCompoundAllowed() public {
        // Setup deposit and rewards
        vm.startPrank(depositor);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, makeAddr("delegatee"), whitelistedClaimer);
        vm.stopPrank();

        vm.startPrank(rewardNotifier);
        stakeToken.approve(address(regenStaker), REWARD_AMOUNT);
        stakeToken.transfer(address(regenStaker), REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);

        // Remove depositor from whitelist
        vm.prank(admin);
        stakerWhitelist.removeFromWhitelist(depositor);

        // Direct staking is correctly blocked
        vm.startPrank(depositor);
        stakeToken.mint(depositor, STAKE_AMOUNT);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);

        vm.expectRevert(); // Should revert due to whitelist check
        regenStaker.stake(STAKE_AMOUNT, makeAddr("delegatee"), depositor);
        vm.stopPrank();

        // FIX VERIFIED - Compound is now also blocked for delisted owner
        // Both direct staking and compounding are now consistently protected
        vm.prank(whitelistedClaimer);
        vm.expectRevert(); // Expected to revert with NotWhitelisted
        regenStaker.compoundRewards(depositId);
    }
}
