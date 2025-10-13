// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { Staker } from "staker/Staker.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { AccessControl } from "src/utils/AccessControl.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { OctantQFMechanism } from "src/mechanisms/mechanism/OctantQFMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";

/// @title Cantina Competition September 2025 – Finding 127 Fix
/// @notice Proves the PROPER architectural fix: contribution whitelist at TAM signup, not RegenStaker
/// @dev This is where voting power is CREATED, so this is where access control belongs
contract Cantina127Fix is Test {
    // Contracts
    RegenStaker public regenStaker;
    MockERC20Staking public stakeToken;
    MockERC20 public rewardToken;
    Whitelist public stakerWhitelist;
    Whitelist public regenContributionWhitelist; // RegenStaker's (now redundant)
    AccessControl public tamContributionWhitelist; // TAM's (the RIGHT place)
    Whitelist public allocationWhitelist;
    Whitelist public earningPowerWhitelist;
    OctantQFMechanism public allocationMechanism;
    AllocationMechanismFactory public allocationFactory;

    // Actors
    address public admin = makeAddr("admin");
    address public alice; // The delisted depositor
    uint256 public alicePk;
    address public bob; // The whitelisted claimer
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
        regenContributionWhitelist = new Whitelist(); // RegenStaker's
        tamContributionWhitelist = new AccessControl(AccessControl.Mode.ALLOWLIST); // TAM's (ALLOWLIST mode)
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

        // THE FIX: Set contribution whitelist on TAM (where voting power is created)
        TokenizedAllocationMechanism(address(allocationMechanism)).setContributionWhitelist(tamContributionWhitelist);

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
            regenContributionWhitelist, // RegenStaker's whitelist (now redundant but kept for compat)
            allocationWhitelist
        );
        regenStaker.setRewardNotifier(rewardNotifier, true);
        vm.stopPrank();

        // Fund accounts
        stakeToken.mint(alice, STAKE_AMOUNT);
        rewardToken.mint(rewardNotifier, REWARD_AMOUNT);
    }

    /// @notice Test that TAM-level whitelist blocks delisted users via ALL paths
    /// @dev This is the PROPER fix - control at the point of power creation
    function testFix_TAMWhitelistBlocksAllPaths() public {
        // Setup: Alice whitelisted everywhere initially
        vm.startPrank(admin);
        stakerWhitelist.addToWhitelist(alice);
        regenContributionWhitelist.addToWhitelist(alice); // RegenStaker's (still checked by contribute())
        regenContributionWhitelist.addToWhitelist(bob); // Bob too for contribute() path
        tamContributionWhitelist.addToWhitelist(alice); // TAM's (the REAL enforcement)
        tamContributionWhitelist.addToWhitelist(bob);
        earningPowerWhitelist.addToWhitelist(alice);
        vm.stopPrank();

        // Alice stakes
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

        uint256 aliceRewards = regenStaker.unclaimedReward(depositId);
        assertGe(aliceRewards, CONTRIBUTION_AMOUNT);

        // Admin delists Alice from BOTH whitelists (layered defense)
        vm.startPrank(admin);
        regenContributionWhitelist.removeFromWhitelist(alice); // RegenStaker check (fund source)
        tamContributionWhitelist.removeFromWhitelist(alice); // TAM check (for claim->signup path)
        vm.stopPrank();

        // PATH 1: Try contribute() via Bob (whitelisted claimer)
        // Should FAIL because Alice (deposit.owner, fund source) is not whitelisted
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _getSignupDigest(bob, address(regenStaker), CONTRIBUTION_AMOUNT, 0, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPk, digest);

        vm.prank(bob);
        vm.expectRevert(); // Will revert with NotWhitelisted from RegenStaker (checking deposit.owner = Alice)
        regenStaker.contribute(depositId, address(allocationMechanism), CONTRIBUTION_AMOUNT, deadline, v, r, s);

        // PATH 2: Try claim → direct signup (the bypass path)
        // Should ALSO FAIL because Alice is not on TAM whitelist
        vm.prank(alice);
        uint256 claimed = regenStaker.claimReward(depositId);
        assertGt(claimed, 0);

        // Alice now has tokens, tries to signup directly
        vm.startPrank(alice);
        rewardToken.approve(address(allocationMechanism), claimed);
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.ContributorNotWhitelisted.selector, alice));
        TokenizedAllocationMechanism(address(allocationMechanism)).signup(claimed);
        vm.stopPrank();
    }

    /// @notice Test that AccessControl works in BLOCKLIST mode
    function testFix_TAMWithBlocklistMode() public {
        // Create a NEW TAM with blocklist mode
        vm.startPrank(admin);
        AccessControl tamBlocklist = new AccessControl(AccessControl.Mode.BLOCKLIST);

        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(rewardToken)),
            name: "Test Blocklist QF",
            symbol: "TBQF",
            votingDelay: 1,
            votingPeriod: 30 days,
            quorumShares: 1,
            timelockDelay: 1,
            gracePeriod: 7 days,
            owner: admin
        });
        address mechAddr = allocationFactory.deployQuadraticVotingMechanism(config, 1, 1);
        OctantQFMechanism blocklistMechanism = OctantQFMechanism(payable(mechAddr));

        // Set BLOCKLIST mode whitelist
        TokenizedAllocationMechanism(address(blocklistMechanism)).setContributionWhitelist(tamBlocklist);

        // Block Alice specifically
        tamBlocklist.addToWhitelist(alice); // In BLOCKLIST mode, this BLOCKS alice
        vm.stopPrank();

        // Verify: Alice is blocked, Bob is allowed
        assertFalse(tamBlocklist.isWhitelisted(alice), "Alice should be blocked");
        assertTrue(tamBlocklist.isWhitelisted(bob), "Bob should be allowed (not on blocklist)");

        // Setup staking
        vm.startPrank(admin);
        stakerWhitelist.addToWhitelist(alice);
        stakerWhitelist.addToWhitelist(bob);
        earningPowerWhitelist.addToWhitelist(alice);
        earningPowerWhitelist.addToWhitelist(bob);
        allocationWhitelist.addToWhitelist(address(blocklistMechanism));
        vm.stopPrank();

        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, alice);
        vm.stopPrank();

        // Rewards
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + 15 days);

        // Alice claims
        vm.prank(alice);
        uint256 claimed = regenStaker.claimReward(depositId);

        // Alice tries to signup - should FAIL (she's on the blocklist)
        vm.startPrank(alice);
        rewardToken.approve(address(blocklistMechanism), claimed);
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.ContributorNotWhitelisted.selector, alice));
        TokenizedAllocationMechanism(address(blocklistMechanism)).signup(claimed);
        vm.stopPrank();

        // Bob can signup (not on blocklist)
        rewardToken.mint(bob, CONTRIBUTION_AMOUNT);
        vm.startPrank(bob);
        rewardToken.approve(address(blocklistMechanism), CONTRIBUTION_AMOUNT);
        TokenizedAllocationMechanism(address(blocklistMechanism)).signup(CONTRIBUTION_AMOUNT);
        vm.stopPrank();

        assertGt(
            TokenizedAllocationMechanism(address(blocklistMechanism)).votingPower(bob),
            0,
            "Bob should have voting power"
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
