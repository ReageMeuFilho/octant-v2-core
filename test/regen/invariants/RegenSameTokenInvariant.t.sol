// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenSameTokenHandler } from "./RegenSameTokenHandler.t.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract RegenSameTokenInvariant is StdInvariant, Test {
    RegenStakerWithoutDelegateSurrogateVotes public staker;
    MockERC20 public token;
    Whitelist public whitelist;
    RegenEarningPowerCalculator public earningPowerCalculator;
    address public admin = address(0xA);
    address public notifier = address(0xB);
    address public user = address(0xC);
    RegenSameTokenHandler public handler;

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
            0,
            IWhitelist(address(0)),
            IWhitelist(address(0)),
            whitelist
        );

        vm.prank(admin);
        staker.setRewardNotifier(notifier, true);

        handler = new RegenSameTokenHandler(staker, token, admin, notifier, user);
        targetContract(address(handler));
    }

    function invariant_SameTokenBalanceMeetsRequired() public view {
        // If reward token equals stake token, require: balance >= totalStaked
        if (address(staker.REWARD_TOKEN()) == address(staker.STAKE_TOKEN())) {
            assertGe(token.balanceOf(address(staker)), staker.totalStaked());
        }
    }
}
