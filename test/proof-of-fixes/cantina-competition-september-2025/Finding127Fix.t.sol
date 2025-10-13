// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { Staker } from "staker/Staker.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { OctantQFMechanism } from "src/mechanisms/mechanism/OctantQFMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";

/// @title Cantina Competition September 2025 – Finding 127 Fix
/// @notice Proves that contribute() now prevents delisted owners from using whitelisted claimers as proxies
/// @dev Tests the fix that checks both msg.sender AND deposit.owner against contributionWhitelist
contract Cantina127Fix is Test {
    // Contracts
    RegenStaker public regenStaker;
    MockERC20Staking public stakeToken;
    MockERC20 public rewardToken;
    Whitelist public stakerWhitelist;
    Whitelist public contributionWhitelist;
    Whitelist public allocationWhitelist;
    Whitelist public earningPowerWhitelist;
    OctantQFMechanism public allocationMechanism;
    AllocationMechanismFactory public allocationFactory;

    // Actors
    address public admin = makeAddr("admin");
    address public alice; // The delisted depositor
    uint256 public alicePk;
    address public bob; // The whitelisted claimer/accomplice
    uint256 public bobPk;
    address public rewardNotifier = makeAddr("rewardNotifier");

    // Constants
    uint256 internal constant STAKE_AMOUNT = 100 ether;
    uint256 internal constant REWARD_AMOUNT = 50 ether;
    uint256 internal constant CONTRIBUTION_AMOUNT = 10 ether;

    function setUp() public {
        (alice, alicePk) = makeAddrAndKey("alice");
        (bob, bobPk) = makeAddrAndKey("bob");

        vm.startPrank(admin);
        // Deploy tokens and whitelists
        stakeToken = new MockERC20Staking(18);
        rewardToken = new MockERC20(18);
        stakerWhitelist = new Whitelist();
        contributionWhitelist = new Whitelist();
        allocationWhitelist = new Whitelist();
        earningPowerWhitelist = new Whitelist();

        // Deploy Allocation Mechanism
        allocationFactory = new AllocationMechanismFactory();
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(rewardToken)),
            name: "Test QF",
            symbol: "TQF",
            votingDelay: 1,
            votingPeriod: 30 days,
            quorumShares: 1,
            timelockDelay: 1,
            gracePeriod: 7 days,
            owner: admin
        });
        address mechAddr = allocationFactory.deployQuadraticVotingMechanism(config, 1, 1);
        allocationMechanism = OctantQFMechanism(payable(mechAddr));
        allocationWhitelist.addToWhitelist(address(allocationMechanism));

        // Deploy RegenStaker
        RegenEarningPowerCalculator calc = new RegenEarningPowerCalculator(admin, earningPowerWhitelist);
        regenStaker = new RegenStaker(
            rewardToken,
            stakeToken,
            calc,
            0, // maxBumpTip
            admin,
            30 days, // reward duration
            0, // minimumStakeAmount
            stakerWhitelist,
            contributionWhitelist,
            allocationWhitelist
        );
        regenStaker.setRewardNotifier(rewardNotifier, true);
        vm.stopPrank();

        // Fund accounts
        stakeToken.mint(alice, STAKE_AMOUNT);
        rewardToken.mint(rewardNotifier, REWARD_AMOUNT);
    }

    /// @notice Test that delisted owner cannot use whitelisted claimer to contribute (THE FIX)
    function testFix_DelistedOwnerCannotContributeThroughWhitelistedClaimer() public {
        // Setup: Both Alice and Bob are initially whitelisted
        vm.startPrank(admin);
        stakerWhitelist.addToWhitelist(alice);
        contributionWhitelist.addToWhitelist(alice);
        contributionWhitelist.addToWhitelist(bob);
        earningPowerWhitelist.addToWhitelist(alice);
        vm.stopPrank();

        // Alice stakes and sets Bob as her claimer
        vm.startPrank(alice);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, alice, bob);
        vm.stopPrank();

        // Verify Bob is the claimer
        (, , , , address claimer, , ) = regenStaker.deposits(depositId);
        assertEq(claimer, bob, "Bob should be the claimer");

        // Rewards accrue
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + 15 days);

        uint256 aliceRewards = regenStaker.unclaimedReward(depositId);
        assertGe(aliceRewards, CONTRIBUTION_AMOUNT, "Alice should have enough rewards");

        // Admin delists Alice from contributing
        vm.prank(admin);
        contributionWhitelist.removeFromWhitelist(alice);

        assertFalse(contributionWhitelist.isWhitelisted(alice), "Alice should be delisted");
        assertTrue(contributionWhitelist.isWhitelisted(bob), "Bob must remain whitelisted");

        // THE FIX: Bob (whitelisted) tries to contribute for Alice's (delisted) deposit
        // This should now REVERT because deposit.owner (Alice) is not whitelisted
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _getSignupDigest(bob, address(regenStaker), CONTRIBUTION_AMOUNT, 0, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPk, digest);

        vm.prank(bob);
        vm.expectRevert(); // Should revert with NotWhitelisted error
        regenStaker.contribute(depositId, address(allocationMechanism), CONTRIBUTION_AMOUNT, deadline, v, r, s);
    }

    /// @notice Test that contributions still work when both owner and caller are whitelisted
    function testFix_ContributeWorksWhenBothOwnerAndCallerWhitelisted() public {
        // Setup: Both Alice and Bob are whitelisted
        vm.startPrank(admin);
        stakerWhitelist.addToWhitelist(alice);
        contributionWhitelist.addToWhitelist(alice);
        contributionWhitelist.addToWhitelist(bob);
        earningPowerWhitelist.addToWhitelist(alice);
        vm.stopPrank();

        // Alice stakes and sets Bob as her claimer
        vm.startPrank(alice);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, alice, bob);
        vm.stopPrank();

        // Rewards accrue
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + 15 days);

        uint256 aliceRewardsBefore = regenStaker.unclaimedReward(depositId);
        assertGe(aliceRewardsBefore, CONTRIBUTION_AMOUNT);

        // Bob contributes on behalf of Alice - should succeed because BOTH are whitelisted
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _getSignupDigest(bob, address(regenStaker), CONTRIBUTION_AMOUNT, 0, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPk, digest);

        vm.prank(bob);
        regenStaker.contribute(depositId, address(allocationMechanism), CONTRIBUTION_AMOUNT, deadline, v, r, s);

        // Verify contribution succeeded
        uint256 aliceRewardsAfter = regenStaker.unclaimedReward(depositId);
        assertEq(aliceRewardsAfter, aliceRewardsBefore - CONTRIBUTION_AMOUNT, "Rewards should be debited");
        assertEq(
            rewardToken.balanceOf(address(allocationMechanism)),
            CONTRIBUTION_AMOUNT,
            "Mechanism should receive tokens"
        );
    }

    function _getSignupDigest(
        address user,
        address payer,
        uint256 deposit,
        uint256 nonce,
        uint256 deadline
    ) internal returns (bytes32) {
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        bytes32 typeHash = keccak256(
            "Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, user, payer, deposit, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
