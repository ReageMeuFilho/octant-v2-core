// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Staker } from "staker/Staker.sol";

/// @title Cantina Competition September 2025 – Finding 238 Fix
/// @notice Proves that compoundRewards fails fast with clear error when balance is insufficient
/// @dev Tests the optimization that checks balance before expensive state updates
contract Cantina238Fix is Test {
    RegenStakerWithoutDelegateSurrogateVotes public staker;
    RegenEarningPowerCalculator public calculator;
    Whitelist public stakerWhitelist;
    Whitelist public earningPowerWhitelist;
    Whitelist public allocationMechanismWhitelist;
    MockERC20Staking public sameToken;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public notifier = makeAddr("notifier");

    uint256 internal constant STAKE_AMOUNT = 1000 ether;
    uint256 internal constant REWARD_AMOUNT = 500 ether;
    uint256 internal constant REWARD_DURATION = 30 days;

    function setUp() public {
        // Deploy token (same for staking and rewards)
        sameToken = new MockERC20Staking(18);

        // Deploy whitelists
        stakerWhitelist = new Whitelist();
        earningPowerWhitelist = new Whitelist();
        allocationMechanismWhitelist = new Whitelist();

        // Whitelist alice
        stakerWhitelist.addToWhitelist(alice);
        earningPowerWhitelist.addToWhitelist(alice);

        // Deploy calculator
        calculator = new RegenEarningPowerCalculator(admin, earningPowerWhitelist);

        // Deploy staker (same token for rewards and staking)
        staker = new RegenStakerWithoutDelegateSurrogateVotes(
            IERC20(address(sameToken)),
            IERC20(address(sameToken)),
            calculator,
            0, // maxBumpTip
            admin,
            uint128(REWARD_DURATION),
            0, // minimumStakeAmount
            IWhitelist(stakerWhitelist),
            IWhitelist(address(0)),
            IWhitelist(allocationMechanismWhitelist)
        );

        earningPowerWhitelist.addToWhitelist(address(staker));

        vm.prank(admin);
        staker.setRewardNotifier(notifier, true);
    }

    /// @notice Test that compoundRewards fails fast with clear error when balance is insufficient
    /// @dev This demonstrates the gas optimization from adding early balance check
    function testFix_CompoundFailsFastOnInsufficientBalance() public {
        // Alice stakes
        sameToken.mint(alice, STAKE_AMOUNT);
        vm.startPrank(alice);
        sameToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice);
        vm.stopPrank();

        // For same-token protection, we need: balance >= totalStaked + rewardAmount
        // Current balance after stake: STAKE_AMOUNT (Alice's stake is in surrogate, not main contract)
        // Required: totalStaked(0, surrogates hold it) + rewardAmount
        // So we just need REWARD_AMOUNT in the contract
        sameToken.mint(address(staker), REWARD_AMOUNT);

        // Notify rewards
        vm.prank(notifier);
        staker.notifyRewardAmount(REWARD_AMOUNT);

        // Warp to accrue rewards
        vm.warp(block.timestamp + REWARD_DURATION / 2);

        // Get unclaimed amount
        uint256 unclaimed = staker.unclaimedReward(depositId);
        assertGt(unclaimed, 0, "Should have unclaimed rewards");

        // Maliciously or accidentally drain the contract balance
        // (simulating admin error or accounting bug)
        uint256 currentBalance = sameToken.balanceOf(address(staker));
        vm.prank(address(staker));
        sameToken.transfer(admin, currentBalance);

        // Now contract balance is 0, but user has unclaimed rewards
        assertEq(sameToken.balanceOf(address(staker)), 0, "Contract should have 0 balance");

        // Try to compound - should fail FAST with clear error (before state updates)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.CantAfford.selector, unclaimed, 0));
        staker.compoundRewards(depositId);
    }

    /// @notice Test that normal compounding still works when balance is sufficient
    function testFix_CompoundSucceedsWithSufficientBalance() public {
        // Alice stakes
        sameToken.mint(alice, STAKE_AMOUNT);
        vm.startPrank(alice);
        sameToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice);
        vm.stopPrank();

        // Mint sufficient tokens for rewards (same-token protection needs balance >= reward amount)
        sameToken.mint(address(staker), REWARD_AMOUNT);

        // Notify rewards
        vm.prank(notifier);
        staker.notifyRewardAmount(REWARD_AMOUNT);

        // Warp to accrue rewards
        vm.warp(block.timestamp + REWARD_DURATION);

        // Get balance before
        (, , , , , , uint256 balanceBefore) = staker.deposits(depositId);

        // Compound should succeed
        vm.prank(alice);
        uint256 compounded = staker.compoundRewards(depositId);

        // Verify compounding worked
        assertGt(compounded, 0, "Should have compounded some rewards");
        (, , , , , , uint256 balanceAfter) = staker.deposits(depositId);
        assertGt(balanceAfter, balanceBefore, "Balance should increase after compounding");
    }
}
