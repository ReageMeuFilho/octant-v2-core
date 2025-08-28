// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { Staker } from "staker/Staker.sol";

/**
 * @title REG-007 Withdrawal Lockup Demo
 * @dev Demonstrates withdrawal failure in RegenStakerWithoutDelegateSurrogateVotes
 *
 * VULNERABILITY: User deposits succeed but withdrawals fail permanently
 * ROOT CAUSE: Contract acts as own surrogate but lacks self-approval for transferFrom
 * IMPACT: All user funds permanently locked in contract
 * SEVERITY: High
 */
contract REG007WithdrawalLockupDemoTest is Test {
    RegenStakerWithoutDelegateSurrogateVotes public regenStaker;
    MockERC20Staking public stakeToken;
    address public user = makeAddr("user");
    uint256 public constant STAKE_AMOUNT = 100 ether;

    function setUp() public {
        address admin = makeAddr("admin");
        MockERC20 rewardToken = new MockERC20(18);
        stakeToken = new MockERC20Staking(18);
        Whitelist stakerWhitelist = new Whitelist();
        Whitelist earningPowerWhitelist = new Whitelist();
        RegenEarningPowerCalculator calc = new RegenEarningPowerCalculator(address(this), earningPowerWhitelist);

        regenStaker = new RegenStakerWithoutDelegateSurrogateVotes(
            rewardToken,
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

        stakerWhitelist.addToWhitelist(user);
        earningPowerWhitelist.addToWhitelist(user);
        stakeToken.mint(user, STAKE_AMOUNT);
    }

    function testREG007_DepositSucceedsWithdrawalFails() public {
        // NOTE: This vulnerability has been fixed - the test now verifies proper behavior
        // Deposit succeeds
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, makeAddr("delegatee"), user);

        assertEq(stakeToken.balanceOf(address(regenStaker)), STAKE_AMOUNT);
        assertEq(stakeToken.balanceOf(user), 0);

        // Withdrawal now succeeds - vulnerability has been fixed
        uint256 withdrawAmount = STAKE_AMOUNT / 2;
        regenStaker.withdraw(depositId, withdrawAmount);

        // Verify withdrawal worked properly
        assertEq(stakeToken.balanceOf(user), withdrawAmount);
        assertEq(stakeToken.balanceOf(address(regenStaker)), STAKE_AMOUNT - withdrawAmount);

        vm.stopPrank();
    }

    function testREG007_RootCause() public {
        // Contract acts as its own surrogate
        address surrogate = address(regenStaker.surrogates(makeAddr("any")));
        assertEq(surrogate, address(regenStaker));

        // But has no self-approval for transferFrom
        uint256 selfAllowance = stakeToken.allowance(address(regenStaker), address(regenStaker));
        assertEq(selfAllowance, 0);
    }
}
