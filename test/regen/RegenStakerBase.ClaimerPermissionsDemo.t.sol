// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { Staker } from "staker/Staker.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockEarningPowerCalculator } from "test/mocks/MockEarningPowerCalculator.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { OctantQFMechanism } from "src/mechanisms/mechanism/OctantQFMechanism.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";

/// @title RegenStakerBase Claimer Permissions Demonstration
/// @notice Demonstrates that claimers have intended staking permissions through compounding
/// @dev This test suite validates the documented behavior that claimers can:
///      1. Claim rewards on behalf of the owner
///      2. Compound rewards (increasing stake) when REWARD_TOKEN == STAKE_TOKEN
///      This is INTENDED BEHAVIOR as documented in REG-019
contract RegenStakerBaseClaimerPermissionsDemoTest is Test {
    RegenStaker public regenStaker;
    MockERC20Staking public token; // Same token for stake and reward
    MockEarningPowerCalculator public earningPowerCalculator;
    OctantQFMechanism public allocationMechanism;
    Whitelist public stakerWhitelist;
    Whitelist public allocationWhitelist;

    address public admin = makeAddr("admin");
    address public owner = makeAddr("owner");
    address public claimer;
    uint256 private claimerPk;
    address public delegatee = makeAddr("delegatee");

    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant REWARD_AMOUNT = 1000e18;
    uint128 public constant REWARD_DURATION = 30 days;

    Staker.DepositIdentifier public depositId;

    function setUp() public {
        // Deploy infrastructure
        token = new MockERC20Staking(18);
        earningPowerCalculator = new MockEarningPowerCalculator();

        // Deploy real allocation mechanism (OctantQFMechanism) using shared implementation
        TokenizedAllocationMechanism impl = new TokenizedAllocationMechanism();
        AllocationConfig memory cfg = AllocationConfig({
            asset: IERC20(address(token)),
            name: "TestAlloc",
            symbol: "TA",
            votingDelay: 1,
            votingPeriod: 30 days,
            quorumShares: 1,
            timelockDelay: 1,
            gracePeriod: 100,
            owner: admin
        });
        allocationMechanism = new OctantQFMechanism(address(impl), cfg, 1, 1, address(0));

        // Deploy whitelists
        vm.startPrank(admin);
        stakerWhitelist = new Whitelist();
        allocationWhitelist = new Whitelist();

        // Setup whitelists
        stakerWhitelist.addToWhitelist(owner);
        (claimer, claimerPk) = makeAddrAndKey("claimer");
        stakerWhitelist.addToWhitelist(claimer);
        allocationWhitelist.addToWhitelist(address(allocationMechanism));
        vm.stopPrank();

        // Deploy RegenStaker with same token for stake/reward (enables compounding)
        vm.prank(admin);
        regenStaker = new RegenStaker(
            IERC20(address(token)), // rewardsToken
            token, // stakeToken
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            REWARD_DURATION,
            0, // maxClaimFee
            1e18, // minimumStakeAmount
            IWhitelist(address(stakerWhitelist)),
            IWhitelist(address(stakerWhitelist)),
            IWhitelist(address(allocationWhitelist))
        );

        // Fund and create deposit with claimer designation
        token.mint(owner, STAKE_AMOUNT);
        token.mint(address(regenStaker), REWARD_AMOUNT);

        vm.startPrank(owner);
        token.approve(address(regenStaker), STAKE_AMOUNT);
        depositId = regenStaker.stake(STAKE_AMOUNT, delegatee, claimer);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(admin);
        regenStaker.setRewardNotifier(admin, true);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Accumulate rewards
        vm.warp(block.timestamp + REWARD_DURATION / 2);
    }

    /// @notice Demonstrates that claimers CAN claim rewards - INTENDED BEHAVIOR
    function testDemonstrate_ClaimerCanClaimRewards() public {
        // Claimer successfully claims rewards
        vm.prank(claimer);
        uint256 claimedAmount = regenStaker.claimReward(depositId);

        // Verify rewards were claimed
        assertGt(claimedAmount, 0, "claims rewards");
        assertEq(token.balanceOf(claimer), claimedAmount, "Rewards sent to claimer");
    }

    /// @notice Demonstrates that claimers CAN compound rewards - INTENDED BEHAVIOR
    /// @dev This increases the deposit's stake amount, which is the documented behavior
    function testDemonstrate_ClaimerCanCompoundRewards() public {
        (uint96 stakeBefore, , , , , , ) = regenStaker.deposits(depositId);

        // Claimer compounds rewards (claims + restakes in one operation)
        vm.prank(claimer);
        uint256 compoundedAmount = regenStaker.compoundRewards(depositId);

        (uint96 stakeAfter, , , , , , ) = regenStaker.deposits(depositId);

        // Verify stake increased through compounding
        assertGt(compoundedAmount, 0, "compounded");
        assertEq(stakeAfter - stakeBefore, compoundedAmount);
    }

    /// @notice Demonstrates the permission boundaries - claimers CANNOT withdraw
    function testDemonstrate_ClaimerCannotWithdraw() public {
        vm.prank(claimer);
        vm.expectRevert(); // Claimer lacks withdrawal permission
        regenStaker.withdraw(depositId, 10e18);
    }

    /// @notice Demonstrates that claimers CAN contribute when on contribution whitelist
    function testDemonstrate_ClaimerCanContributeIfWhitelisted() public {
        // Progress time to accrue rewards
        vm.warp(block.timestamp + REWARD_DURATION / 4);

        // Prepare EIP-712 signature for signupOnBehalfWithSignature(user=claimer, payer=regenStaker)
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(claimer);
        uint256 amount = 1e18;
        uint256 deadline = block.timestamp + 1 days;
        bytes32 typeHash = keccak256(
            bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)")
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, claimer, address(regenStaker), amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimerPk, digest);

        uint256 mechanismBalanceBefore = token.balanceOf(address(allocationMechanism));

        // Claimer contributes unclaimed rewards to the real allocation mechanism
        vm.prank(claimer);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            amount,
            deadline,
            v,
            r,
            s
        );

        // Verify contribution succeeded
        assertEq(contributed, amount);
        assertEq(token.balanceOf(address(allocationMechanism)) - mechanismBalanceBefore, amount);
    }

    /// @notice Demonstrates owner control - can revoke claimer at any time
    function testDemonstrate_OwnerCanRevokeClaimer() public {
        address newClaimer = makeAddr("newClaimer");

        // Owner changes claimer
        vm.prank(admin);
        stakerWhitelist.addToWhitelist(newClaimer);

        vm.prank(owner);
        regenStaker.alterClaimer(depositId, newClaimer);

        // Old claimer no longer has access
        vm.prank(claimer);
        vm.expectRevert(); // No longer authorized
        regenStaker.claimReward(depositId);

        // New claimer has access
        vm.prank(newClaimer);
        uint256 claimed = regenStaker.claimReward(depositId);
        assertGt(claimed, 0, "New claimer can claim");
    }
}
