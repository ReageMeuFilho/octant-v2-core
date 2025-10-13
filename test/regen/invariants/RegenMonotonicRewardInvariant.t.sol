// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenMonotonicRewardHandler } from "./RegenMonotonicRewardHandler.t.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

/// @title Invariant test for monotonic reward property
/// @notice Verifies that totalRewards is monotonically non-decreasing
/// @dev Tests the property: totalRewards can only increase or stay the same, never decrease
contract RegenMonotonicRewardInvariant is StdInvariant, Test {
    RegenStakerWithoutDelegateSurrogateVotes public staker;
    MockERC20 public token;
    Whitelist public whitelist;
    RegenEarningPowerCalculator public earningPowerCalculator;
    address public admin = address(0xA);
    address public notifier = address(0xB);
    address public user = address(0xC);
    RegenMonotonicRewardHandler public handler;

    function setUp() public {
        token = new MockERC20(18);
        whitelist = new Whitelist();
        whitelist.addToWhitelist(user);
        earningPowerCalculator = new RegenEarningPowerCalculator(admin, IWhitelist(address(whitelist)));

        staker = new RegenStakerWithoutDelegateSurrogateVotes(
            IERC20(address(token)),
            IERC20(address(token)),
            earningPowerCalculator,
            0,
            admin,
            30 days,
            0,
            IWhitelist(address(0)),
            IWhitelist(address(0)),
            whitelist
        );

        vm.prank(admin);
        staker.setRewardNotifier(notifier, true);

        handler = new RegenMonotonicRewardHandler(staker, token, admin, notifier, user);
        targetContract(address(handler));
    }

    /// @notice Invariant: totalRewards is monotonically non-decreasing
    /// @dev After any action, totalRewards must be >= previous totalRewards
    /// @dev This ensures rewards cannot be clawed back once notified
    function invariant_TotalRewardsMonotonicallyIncreasing() public view {
        uint256 currentTotalRewards = staker.totalRewards();
        uint256 previousTotalRewards = handler.previousTotalRewards();

        assertGe(currentTotalRewards, previousTotalRewards, "totalRewards decreased: rewards cannot be clawed back");
    }
}
