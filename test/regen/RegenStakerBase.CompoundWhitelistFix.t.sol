// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { Staker } from "staker/Staker.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";

/// @title Tests for REG-008 Compound Rewards Whitelist Fix
/// @notice Validates that the whitelist bypass vulnerability in compoundRewards is properly fixed
/// @dev Addresses REG-008 (OSU-919) - Missing depositor whitelist check when claimer calls compoundRewards
contract RegenStakerBaseCompoundWhitelistFixTest is Test {
    RegenStaker public staker;
    MockERC20Staking public stakeToken;
    RegenEarningPowerCalculator public earningPowerCalculator;
    Whitelist public stakerWhitelist;
    Whitelist public earningPowerWhitelist;
    Whitelist public allocationWhitelist;

    address public admin = makeAddr("admin");
    address public notifier = makeAddr("notifier");
    address public depositor = makeAddr("depositor");
    address public whitelistedClaimer = makeAddr("whitelistedClaimer");
    address public nonWhitelistedClaimer = makeAddr("nonWhitelistedClaimer");
    address public delegatee = makeAddr("delegatee");

    uint256 constant INITIAL_BALANCE = 10_000e18;
    uint256 constant STAKE_AMOUNT = 1000e18;
    uint256 constant REWARD_AMOUNT = 500e18;

    event StakeDeposited(
        address indexed depositor,
        Staker.DepositIdentifier indexed depositId,
        uint256 amount,
        uint256 earningPower
    );

    function setUp() public {
        // Deploy tokens
        stakeToken = new MockERC20Staking(18);

        // Deploy whitelists
        stakerWhitelist = new Whitelist();
        earningPowerWhitelist = new Whitelist();
        allocationWhitelist = new Whitelist();

        // Deploy earning power calculator
        earningPowerCalculator = new RegenEarningPowerCalculator(admin, IWhitelist(address(earningPowerWhitelist)));

        // Deploy staker with same token for staking and rewards (to enable compounding)
        staker = new RegenStaker(
            IERC20(address(stakeToken)), // rewards token (same as stake)
            stakeToken, // stake token
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            30 days, // rewardDuration
            0, // maxClaimFee
            0, // minimumStakeAmount
            IWhitelist(address(stakerWhitelist)),
            IWhitelist(address(0)), // no contribution whitelist
            allocationWhitelist
        );

        // Setup notifier
        vm.prank(admin);
        staker.setRewardNotifier(notifier, true);

        // Fund users
        stakeToken.mint(depositor, INITIAL_BALANCE);
        stakeToken.mint(whitelistedClaimer, INITIAL_BALANCE);
        stakeToken.mint(nonWhitelistedClaimer, INITIAL_BALANCE);
        stakeToken.mint(notifier, INITIAL_BALANCE);
    }

    /// @notice Test whitelisted owner + whitelisted claimer (should work)
    function test_whitelistedOwnerWhitelistedClaimer() public {
        // Whitelist both depositor and claimer
        stakerWhitelist.addToWhitelist(depositor);
        stakerWhitelist.addToWhitelist(whitelistedClaimer);
        earningPowerWhitelist.addToWhitelist(depositor);

        // Depositor stakes with whitelisted claimer
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, whitelistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();

        // Advance time to earn rewards
        vm.warp(block.timestamp + 15 days);

        // Whitelisted claimer can compound for whitelisted depositor
        vm.prank(whitelistedClaimer);
        uint256 compounded = staker.compoundRewards(depositId);

        assertGt(compounded, 0, "Should have compounded rewards");
    }

    /// @notice Test non-whitelisted owner + whitelisted claimer (should fail - the fix)
    function test_nonWhitelistedOwnerWhitelistedClaimer() public {
        // Initially whitelist depositor to create deposit
        stakerWhitelist.addToWhitelist(depositor);
        stakerWhitelist.addToWhitelist(whitelistedClaimer);
        earningPowerWhitelist.addToWhitelist(depositor);

        // Depositor stakes with whitelisted claimer
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, whitelistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Remove depositor from whitelist (e.g., compliance issue)
        stakerWhitelist.removeFromWhitelist(depositor);
        assertFalse(stakerWhitelist.isWhitelisted(depositor));
        assertTrue(stakerWhitelist.isWhitelisted(whitelistedClaimer));

        // Whitelisted claimer CANNOT compound for non-whitelisted depositor (the fix)
        vm.prank(whitelistedClaimer);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.NotWhitelisted.selector, stakerWhitelist, depositor));
        staker.compoundRewards(depositId);
    }

    /// @notice Test whitelisted owner calling their own compound (should work)
    function test_whitelistedOwnerSelfCompound() public {
        // Whitelist depositor
        stakerWhitelist.addToWhitelist(depositor);
        earningPowerWhitelist.addToWhitelist(depositor);

        // Depositor stakes with themselves as claimer
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, depositor);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Depositor can compound their own rewards
        vm.prank(depositor);
        uint256 compounded = staker.compoundRewards(depositId);

        assertGt(compounded, 0, "Should have compounded rewards");
    }

    /// @notice Test non-whitelisted owner calling their own compound (should fail)
    function test_nonWhitelistedOwnerSelfCompound() public {
        // Initially whitelist to create deposit
        stakerWhitelist.addToWhitelist(depositor);
        earningPowerWhitelist.addToWhitelist(depositor);

        // Depositor stakes
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, depositor);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Remove depositor from whitelist
        stakerWhitelist.removeFromWhitelist(depositor);

        // Non-whitelisted depositor cannot compound their own rewards
        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.NotWhitelisted.selector, stakerWhitelist, depositor));
        staker.compoundRewards(depositId);
    }

    /// @notice Test whitelisted owner + non-whitelisted claimer (should work)
    function test_whitelistedOwnerNonWhitelistedClaimer() public {
        // Whitelist only depositor, not the claimer
        stakerWhitelist.addToWhitelist(depositor);
        earningPowerWhitelist.addToWhitelist(depositor);
        assertFalse(stakerWhitelist.isWhitelisted(nonWhitelistedClaimer));

        // Depositor stakes with non-whitelisted claimer
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, nonWhitelistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Non-whitelisted claimer CAN compound for whitelisted depositor
        // The implementation only checks that the deposit owner is whitelisted
        vm.prank(nonWhitelistedClaimer);
        uint256 compounded = staker.compoundRewards(depositId);
        assertGt(compounded, 0, "Should have compounded rewards");
    }

    /// @notice Test that legitimate compound operations still work after fix
    function test_legitimateCompoundStillWorks() public {
        // Setup multiple whitelisted users
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        stakeToken.mint(alice, INITIAL_BALANCE);
        stakeToken.mint(bob, INITIAL_BALANCE);

        stakerWhitelist.addToWhitelist(alice);
        stakerWhitelist.addToWhitelist(bob);
        earningPowerWhitelist.addToWhitelist(alice);
        earningPowerWhitelist.addToWhitelist(bob);

        // Alice stakes with Bob as claimer
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier aliceDeposit = staker.stake(STAKE_AMOUNT, delegatee, bob);
        vm.stopPrank();

        // Bob stakes with Alice as claimer
        vm.startPrank(bob);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier bobDeposit = staker.stake(STAKE_AMOUNT, delegatee, alice);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Bob can compound Alice's deposit
        vm.prank(bob);
        uint256 aliceCompounded = staker.compoundRewards(aliceDeposit);
        assertGt(aliceCompounded, 0, "Bob should compound Alice's rewards");

        // Alice can compound Bob's deposit
        vm.prank(alice);
        uint256 bobCompounded = staker.compoundRewards(bobDeposit);
        assertGt(bobCompounded, 0, "Alice should compound Bob's rewards");
    }

    /// @notice Test unauthorized claimer cannot compound
    function test_unauthorizedClaimerCannotCompound() public {
        address unauthorizedUser = makeAddr("unauthorized");

        // Whitelist depositor
        stakerWhitelist.addToWhitelist(depositor);
        stakerWhitelist.addToWhitelist(unauthorizedUser);
        earningPowerWhitelist.addToWhitelist(depositor);

        // Depositor stakes with whitelistedClaimer (not unauthorizedUser)
        stakerWhitelist.addToWhitelist(whitelistedClaimer);
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, whitelistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Unauthorized user (not owner, not claimer) cannot compound
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                Staker.Staker__Unauthorized.selector,
                bytes32("not claimer or owner"),
                unauthorizedUser
            )
        );
        staker.compoundRewards(depositId);
    }

    /// @notice Test scenario where depositor is removed then re-added to whitelist
    function test_depositorRemovedThenReaddedToWhitelist() public {
        // Whitelist both
        stakerWhitelist.addToWhitelist(depositor);
        stakerWhitelist.addToWhitelist(whitelistedClaimer);
        earningPowerWhitelist.addToWhitelist(depositor);

        // Create deposit
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, whitelistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 10 days);

        // Remove depositor from whitelist
        stakerWhitelist.removeFromWhitelist(depositor);

        // Claimer cannot compound while depositor is not whitelisted
        vm.prank(whitelistedClaimer);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.NotWhitelisted.selector, stakerWhitelist, depositor));
        staker.compoundRewards(depositId);

        // Re-add depositor to whitelist
        stakerWhitelist.addToWhitelist(depositor);

        // Now claimer can compound again
        vm.prank(whitelistedClaimer);
        uint256 compounded = staker.compoundRewards(depositId);
        assertGt(compounded, 0, "Should compound after re-whitelisting");
    }

    /// @notice Fuzz test various scenarios
    function testFuzz_compoundWhitelistChecks(
        bool ownerWhitelisted,
        bool claimerWhitelisted,
        bool callerIsOwner
    ) public {
        // Setup based on fuzz inputs
        if (ownerWhitelisted) {
            stakerWhitelist.addToWhitelist(depositor);
            earningPowerWhitelist.addToWhitelist(depositor);
        }
        if (claimerWhitelisted) {
            stakerWhitelist.addToWhitelist(whitelistedClaimer);
        }

        // Skip if neither is whitelisted (can't create deposit)
        if (!ownerWhitelisted) return;

        // Create deposit
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(
            STAKE_AMOUNT,
            delegatee,
            callerIsOwner ? depositor : whitelistedClaimer
        );
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Remove owner from whitelist for testing
        if (!ownerWhitelisted) {
            stakerWhitelist.removeFromWhitelist(depositor);
        }

        // Determine who is calling and expected result
        address caller = callerIsOwner ? depositor : whitelistedClaimer;

        // The implementation only checks that the deposit owner is whitelisted
        // It doesn't matter if the claimer is whitelisted or not
        bool shouldSucceed = ownerWhitelisted;

        // Execute compound
        if (shouldSucceed) {
            vm.prank(caller);
            uint256 compounded = staker.compoundRewards(depositId);
            assertGt(compounded, 0, "Should compound successfully");
        } else {
            vm.prank(caller);
            vm.expectRevert(
                abi.encodeWithSelector(RegenStakerBase.NotWhitelisted.selector, stakerWhitelist, depositor)
            );
            staker.compoundRewards(depositId);
        }
    }

    // ============ Helper Functions ============

    function _addRewards() internal {
        vm.startPrank(notifier);
        stakeToken.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
    }
}
