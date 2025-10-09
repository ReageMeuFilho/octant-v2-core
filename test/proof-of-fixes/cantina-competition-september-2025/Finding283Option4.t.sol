// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { OctantTestBase } from "test/proof-of-concepts/OctantTestBase.t.sol";
import { Staker } from "staker/Staker.sol";

/// @title Cantina Competition September 2025 – Option 4 Fix
/// @notice Validates OG fallback staker accrual and permissionless recovery.
contract Finding283Option4 is OctantTestBase {
    uint256 internal constant REWARD_AMOUNT = 5_000 ether;

    function testFix_OgFallbackRecoverySendsToFeeCollector() public {
        setUp();

        address feeCollector = makeAddr("feeCollector");
        vm.prank(admin);
        regenStaker.setClaimFeeParameters(Staker.ClaimFeeParameters({ feeAmount: 0, feeCollector: feeCollector }));

        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.prank(rewardNotifier);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);

        vm.warp(block.timestamp + regenStaker.rewardDuration());

        address caller = makeAddr("sweeper");
        vm.prank(caller);
        uint256 recovered = regenStaker.recoverOgRewards();

        assertApproxEqAbs(recovered, REWARD_AMOUNT, 1, "recovered amount mismatch");
        assertApproxEqAbs(
            rewardToken.balanceOf(feeCollector),
            REWARD_AMOUNT,
            1,
            "fee collector should receive recovery"
        );
    }
}
