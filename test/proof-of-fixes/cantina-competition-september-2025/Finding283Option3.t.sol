// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { OctantTestBase } from "test/proof-of-concepts/OctantTestBase.t.sol";
import { Staker } from "staker/Staker.sol";

/// @title Cantina Competition September 2025 – Option 3 Fix
/// @notice Verifies backlog rewards increase the streaming rate once earning power returns.
contract Finding283Option3 is OctantTestBase {
    uint256 internal constant REWARD_AMOUNT = 10_000 ether;
    uint256 internal constant STAKE_AMOUNT = 1_000 ether;
    uint256 internal constant IDLE_WINDOW = 10 days;

    function testFix_BacklogAdjustsRewardRate() public {
        setUp();

        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);

        vm.prank(rewardNotifier);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);

        uint256 initialRate = regenStaker.scaledRewardRate();
        uint256 initialEnd = regenStaker.rewardEndTime();

        vm.warp(block.timestamp + IDLE_WINDOW);

        stakeToken.mint(alice, STAKE_AMOUNT);
        vm.startPrank(alice);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        assertEq(regenStaker.rewardEndTime(), initialEnd, "rewardEndTime should not move");

        uint256 remaining = initialEnd - block.timestamp;
        uint256 expectedRate = (initialRate * remaining + initialRate * IDLE_WINDOW) / remaining;

        assertEq(regenStaker.scaledRewardRate(), expectedRate, "scaledRewardRate should incorporate backlog");
        assertEq(regenStaker.unclaimedReward(depositId), 0, "no immediate rewards before new rate accrues");
    }
}
