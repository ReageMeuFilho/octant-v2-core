pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { RegenStaker } from "../../src/regen/RegenStaker.sol";
import { RegenEarningPowerCalculator } from "../../src/regen/RegenEarningPowerCalculator.sol";
import { Whitelist } from "../../src/regen/whitelist/Whitelist.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { IWhitelistedEarningPowerCalculator } from "../../src/regen/IWhitelistedEarningPowerCalculator.sol";
import { Staker } from "staker/Staker.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockERC20Staking } from "../mocks/MockERC20Staking.sol";

// Mock interface for grant round
interface IGrantRound {
    function signUp(uint256 _amount, uint256 _preference) external returns (bool success);
}

contract RegenIntegrationTest is Test {
    RegenStaker regenStaker;
    RegenEarningPowerCalculator calculator;
    Whitelist stakerWhitelist;
    Whitelist contributorWhitelist;
    Whitelist earningPowerWhitelist;
    MockERC20 rewardToken;
    MockERC20Staking stakeToken;

    // --- Constants for Reward Accrual Tests ---
    uint256 private constant REWARD_AMOUNT = 30_000_000 * 1e18; // 30M tokens
    uint256 private constant STAKE_AMOUNT = 1_000 * 1e18; // 1K tokens
    uint256 private constant REWARD_PERIOD_DURATION = 30 days;
    uint256 private constant MIN_ASSERT_TOLERANCE = 1;

    // --- End Constants ---

    function setUp() public {
        // Deploy mock tokens
        rewardToken = new MockERC20();
        stakeToken = new MockERC20Staking();

        // Deploy three whitelists
        stakerWhitelist = new Whitelist();
        contributorWhitelist = new Whitelist();
        earningPowerWhitelist = new Whitelist();

        // Deploy the calculator
        calculator = new RegenEarningPowerCalculator(address(this), earningPowerWhitelist);

        // Deploy the staker
        regenStaker = new RegenStaker(
            IERC20(address(rewardToken)),
            IERC20Staking(address(stakeToken)),
            address(this),
            stakerWhitelist,
            contributorWhitelist,
            calculator
        );

        // Make this contract a reward notifier
        regenStaker.setRewardNotifier(address(this), true);
    }

    function test_StakerWhitelistIsSet() public view {
        assertEq(address(regenStaker.stakerWhitelist()), address(stakerWhitelist));
    }

    function test_ContributionWhitelistIsSet() public view {
        assertEq(address(regenStaker.contributionWhitelist()), address(contributorWhitelist));
    }

    function test_EarningPowerWhitelistIsSet() public view {
        assertEq(
            address(IWhitelistedEarningPowerCalculator(address(regenStaker.earningPowerCalculator())).whitelist()),
            address(earningPowerWhitelist)
        );
    }

    function test_EarningPowerCalculatorIsSet() public view {
        assertEq(address(regenStaker.earningPowerCalculator()), address(calculator));
    }

    function test_AllowsStakingIfStakerWhitelistDisabled_RevertIf_ActiveAndUserNotWhitelisted() public {
        // First verify that non-admin cannot set the whitelist
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.setStakerWhitelist(Whitelist(address(0)));
        vm.stopPrank();

        // Setup a non-whitelisted address
        address nonWhitelistedUser = makeAddr("nonWhitelistedUser");

        // Mint tokens to the user
        stakeToken.mint(nonWhitelistedUser, 100);

        vm.startPrank(nonWhitelistedUser);
        stakeToken.approve(address(regenStaker), 100);

        // First attempt should revert because user is not whitelisted
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStaker.NotWhitelisted.selector,
                regenStaker.stakerWhitelist(),
                nonWhitelistedUser
            )
        );
        regenStaker.stake(50, nonWhitelistedUser);

        vm.stopPrank();

        // Now disable the whitelist as admin (this contract is the admin)
        regenStaker.setStakerWhitelist(Whitelist(address(0)));
        assertEq(address(regenStaker.stakerWhitelist()), address(0));

        // Try staking again with the same non-whitelisted user
        vm.startPrank(nonWhitelistedUser);

        // This time it should succeed without reverting (which is the main thing we're testing)
        regenStaker.stake(50, nonWhitelistedUser);

        vm.stopPrank();
    }

    function test_AllowsContributionIfContributorWhitelistDisabled_RevertIf_ActiveAndUserNotWhitelisted() public {
        // First verify that non-admin cannot set the whitelist
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.setContributionWhitelist(Whitelist(address(0)));
        vm.stopPrank();

        // Create a mock grant round
        address mockGrantRound = makeAddr("mockGrantRound");
        vm.mockCall(mockGrantRound, abi.encodeWithSelector(IGrantRound.signUp.selector), abi.encode(true));

        // First, we need to create a deposit that will earn rewards
        address depositor = makeAddr("depositor");

        // Mint tokens and approve
        stakeToken.mint(depositor, 1000);
        rewardToken.mint(address(regenStaker), 1_000_000_000_000_000_000); // 1e18 - much larger reward amount

        vm.startPrank(depositor);
        stakeToken.approve(address(regenStaker), 1000);

        // Whitelist the depositor for staking
        address[] memory users = new address[](1);
        users[0] = depositor;
        vm.stopPrank();
        stakerWhitelist.addToWhitelist(users);

        // Also add the depositor to the earning power whitelist
        earningPowerWhitelist.addToWhitelist(users);

        // Now stake tokens to create a deposit
        vm.startPrank(depositor);
        Staker.DepositIdentifier depositId = regenStaker.stake(1000, depositor);
        vm.stopPrank();

        // Notify rewards to make the deposit earn rewards
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(1_000_000_000_000_000_000);

        // Fast forward time to accumulate rewards
        vm.warp(block.timestamp + 28 days); // Fast forward almost the entire reward period
        vm.stopPrank();

        // Setup a non-whitelisted contributor (who needs to be the deposit owner or claimer to contribute)
        address nonWhitelistedContributor = makeAddr("nonWhitelistedContributor");

        // Make the non-whitelisted contributor the claimer of the deposit
        vm.startPrank(depositor);
        regenStaker.alterClaimer(depositId, nonWhitelistedContributor);
        vm.stopPrank();

        // The first attempt should revert because user is not contribution-whitelisted
        vm.startPrank(nonWhitelistedContributor);
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStaker.NotWhitelisted.selector,
                regenStaker.contributionWhitelist(),
                nonWhitelistedContributor
            )
        );
        regenStaker.contribute(depositId, mockGrantRound, 1e12, 1);
        vm.stopPrank();

        // Now disable the contribution whitelist as admin (this contract is the admin)
        vm.startPrank(address(this));
        regenStaker.setContributionWhitelist(Whitelist(address(0)));
        assertEq(address(regenStaker.contributionWhitelist()), address(0));
        vm.stopPrank();

        // Try contributing again with the same non-whitelisted contributor
        vm.startPrank(nonWhitelistedContributor);

        // Set up expectation that signUp will be called
        vm.expectCall(mockGrantRound, abi.encodeWithSelector(IGrantRound.signUp.selector, 1e12, 1));

        // This time it should succeed without reverting
        regenStaker.contribute(depositId, mockGrantRound, 1e12, 1);

        vm.stopPrank();
    }

    function test_GrantsEarningPowerToNewUserIfEarningPowerWhitelistDisabled_RevertIf_NonAdminDisablesCalculatorWhitelist()
        public
    {
        // First verify that non-admin cannot set the whitelist
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonAdmin));
        IWhitelistedEarningPowerCalculator(address(calculator)).setWhitelist(Whitelist(address(0)));
        vm.stopPrank();

        // Setup two users - one whitelisted, one not
        address whitelistedUser = makeAddr("whitelistedUser");
        address nonWhitelistedUser = makeAddr("nonWhitelistedUser");

        // Mint tokens to both users
        stakeToken.mint(whitelistedUser, 1000);
        stakeToken.mint(nonWhitelistedUser, 1000);

        // Whitelist the first user for staking and earning power
        address[] memory users = new address[](1);
        users[0] = whitelistedUser;
        stakerWhitelist.addToWhitelist(users);
        earningPowerWhitelist.addToWhitelist(users);

        // Also whitelist the non-whitelisted user for staking (but not for earning power)
        users[0] = nonWhitelistedUser;
        stakerWhitelist.addToWhitelist(users);

        // Have both users stake
        vm.startPrank(whitelistedUser);
        stakeToken.approve(address(regenStaker), 1000);
        regenStaker.stake(1000, whitelistedUser);
        vm.stopPrank();

        vm.startPrank(nonWhitelistedUser);
        stakeToken.approve(address(regenStaker), 1000);
        regenStaker.stake(1000, nonWhitelistedUser);
        vm.stopPrank();

        // Check earning power is different between them
        uint256 whitelistedEarningPower = regenStaker.depositorTotalEarningPower(whitelistedUser);
        uint256 nonWhitelistedEarningPower = regenStaker.depositorTotalEarningPower(nonWhitelistedUser);
        assertEq(whitelistedEarningPower, 1000); // Should have earning power
        assertEq(nonWhitelistedEarningPower, 0); // Should have zero earning power

        // Now disable the earning power whitelist as admin (this contract is the admin)
        // We need to call the calculator directly since it's Ownable and our test contract is the owner
        IWhitelistedEarningPowerCalculator(address(calculator)).setWhitelist(Whitelist(address(0)));

        // Verify whitelist is now address(0)
        assertEq(
            address(IWhitelistedEarningPowerCalculator(address(regenStaker.earningPowerCalculator())).whitelist()),
            address(0)
        );

        // Add a new non-whitelisted user to verify they now get earning power without being whitelisted
        address newUser = makeAddr("newUser");
        stakeToken.mint(newUser, 1000);

        // Whitelist for staking only
        users[0] = newUser;
        stakerWhitelist.addToWhitelist(users);

        // Stake with the new user
        vm.startPrank(newUser);
        stakeToken.approve(address(regenStaker), 1000);
        regenStaker.stake(1000, newUser);
        vm.stopPrank();

        // Check earning power is granted
        uint256 newUserEarningPower = regenStaker.depositorTotalEarningPower(newUser);
        assertEq(newUserEarningPower, 1000); // Should have earning power despite not being on earning power whitelist
    }

    function test_RevertIf_PauseCalledByNonAdmin() public {
        // Attempt to pause from a non-admin account
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.pause();
        vm.stopPrank();

        // Pause as admin (this contract)
        vm.startPrank(address(this));
        regenStaker.pause();
        assertTrue(regenStaker.paused(), "Contract should be paused");
        vm.stopPrank();

        // Unpause as admin to leave in a clean state for other tests
        vm.startPrank(address(this));
        regenStaker.unpause();
        assertFalse(regenStaker.paused(), "Contract should be unpaused");
        vm.stopPrank();
    }

    function test_RevertIf_UnpauseCalledByNonAdmin() public {
        // First, pause the contract as admin
        vm.startPrank(address(this));
        regenStaker.pause();
        assertTrue(regenStaker.paused(), "Contract should be paused before attempting unpause by non-admin");
        vm.stopPrank();

        // Attempt to unpause from a non-admin account
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.unpause();
        vm.stopPrank();

        // Unpause as admin (this contract)
        vm.startPrank(address(this));
        regenStaker.unpause();
        assertFalse(regenStaker.paused(), "Contract should be unpaused by admin");
        vm.stopPrank();
    }

    function test_RevertIf_StakeWhenPaused() public {
        // Setup a user
        address user = makeAddr("user");

        // Mint tokens and approve
        stakeToken.mint(user, 100);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), 100);
        vm.stopPrank();

        // Whitelist user for staking
        address[] memory users = new address[](1);
        users[0] = user;
        stakerWhitelist.addToWhitelist(users);

        // Pause the contract as admin
        vm.startPrank(address(this));
        regenStaker.pause();
        assertTrue(regenStaker.paused(), "Contract should be paused");
        vm.stopPrank();

        // Attempt to stake while paused
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        regenStaker.stake(50, user);
        vm.stopPrank();

        // Unpause the contract for other tests
        vm.startPrank(address(this));
        regenStaker.unpause();
        assertFalse(regenStaker.paused(), "Contract should be unpaused");
        vm.stopPrank();
    }

    function test_RevertIf_ContributeWhenPaused() public {
        // --- Setup for contribution ---
        // Create a mock grant round
        address mockGrantRound = makeAddr("mockGrantRound");
        vm.mockCall(mockGrantRound, abi.encodeWithSelector(IGrantRound.signUp.selector), abi.encode(true));

        // Create a depositor/contributor
        address contributor = makeAddr("contributor");

        // Mint tokens and approve
        stakeToken.mint(contributor, 1000);
        rewardToken.mint(address(regenStaker), 1_000_000_000_000_000_000); // 1e18 reward

        vm.startPrank(contributor);
        stakeToken.approve(address(regenStaker), 1000);

        // Whitelist the contributor for staking, contribution, and earning power
        address[] memory users = new address[](1);
        users[0] = contributor;
        vm.stopPrank(); // Stop contributor prank
        stakerWhitelist.addToWhitelist(users);
        contributorWhitelist.addToWhitelist(users);
        earningPowerWhitelist.addToWhitelist(users);

        // Stake tokens
        vm.startPrank(contributor);
        Staker.DepositIdentifier depositId = regenStaker.stake(1000, contributor);
        vm.stopPrank();

        // Notify rewards
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(1_000_000_000_000_000_000);

        // Fast forward time to accumulate rewards
        vm.warp(block.timestamp + 28 days);
        vm.stopPrank(); // Stop admin prank after notify/warp
        // --- End Setup ---

        // Pause the contract as admin
        vm.startPrank(address(this));
        regenStaker.pause();
        assertTrue(regenStaker.paused(), "Contract should be paused");
        vm.stopPrank();

        // Attempt to contribute while paused
        vm.startPrank(contributor);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        regenStaker.contribute(depositId, mockGrantRound, 1e12, 1);
        vm.stopPrank();

        // Unpause the contract for other tests
        vm.startPrank(address(this));
        regenStaker.unpause();
        assertFalse(regenStaker.paused(), "Contract should be unpaused");
        vm.stopPrank();
    }

    function test_ContinuousReward_SingleStaker_FullPeriod() public {
        address staker = makeAddr("staker");

        // Whitelist staker for staking and earning power
        address[] memory stakers = new address[](1);
        stakers[0] = staker;
        stakerWhitelist.addToWhitelist(stakers);
        earningPowerWhitelist.addToWhitelist(stakers);

        // Staker stakes
        stakeToken.mint(staker, STAKE_AMOUNT);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, staker);
        vm.stopPrank();

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT); // Ensure contract has tokens
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp to end of period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Staker claims reward
        vm.startPrank(staker);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqAbs(claimedAmount, REWARD_AMOUNT, MIN_ASSERT_TOLERANCE, "Staker should receive full reward");
    }

    function test_ContinuousReward_SingleStaker_JoinsLate() public {
        address staker = makeAddr("stakerLate");

        // Whitelist staker for staking and earning power
        address[] memory stakers = new address[](1);
        stakers[0] = staker;
        stakerWhitelist.addToWhitelist(stakers);
        earningPowerWhitelist.addToWhitelist(stakers);

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp to mid-period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Staker stakes late
        stakeToken.mint(staker, STAKE_AMOUNT);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, staker);
        vm.stopPrank();

        // Warp to end of period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Staker claims reward
        vm.startPrank(staker);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqAbs(
            claimedAmount,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Late staker should receive half reward"
        );
    }

    function test_ContinuousReward_SingleStaker_ClaimsMidPeriod() public {
        address staker = makeAddr("stakerMidClaim");

        address[] memory stakers = new address[](1); // Whitelist setup
        stakers[0] = staker;
        stakerWhitelist.addToWhitelist(stakers);
        earningPowerWhitelist.addToWhitelist(stakers);

        stakeToken.mint(staker, STAKE_AMOUNT);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, staker);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        vm.startPrank(staker);
        uint256 claimedAmount1 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqAbs(
            claimedAmount1,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Mid-period claim should be half reward"
        );

        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2); // To end of period

        vm.startPrank(staker);
        uint256 claimedAmount2 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqAbs(
            claimedAmount2,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Second claim should be remaining half"
        );
        assertApproxEqAbs(
            claimedAmount1 + claimedAmount2,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE * 2,
            "Total claimed should be full reward"
        );
    }

    function test_ContinuousReward_TwoStakers_StaggeredEntry_ProRataShare() public {
        address stakerA = makeAddr("stakerA_Staggered");
        address stakerB = makeAddr("stakerB_Staggered");

        address[] memory stakerArrA = new address[](1);
        stakerArrA[0] = stakerA;
        address[] memory stakerArrB = new address[](1);
        stakerArrB[0] = stakerB;
        stakerWhitelist.addToWhitelist(stakerArrA);
        earningPowerWhitelist.addToWhitelist(stakerArrA);
        stakerWhitelist.addToWhitelist(stakerArrB);
        earningPowerWhitelist.addToWhitelist(stakerArrB);

        // Staker A stakes
        stakeToken.mint(stakerA, STAKE_AMOUNT);
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositIdA = regenStaker.stake(STAKE_AMOUNT, stakerA);
        vm.stopPrank();

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp 1/3 period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 3);

        // Staker B stakes
        stakeToken.mint(stakerB, STAKE_AMOUNT);
        vm.startPrank(stakerB);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositIdB = regenStaker.stake(STAKE_AMOUNT, stakerB);
        vm.stopPrank();

        // Warp remaining 2/3 period
        vm.warp(block.timestamp + (REWARD_PERIOD_DURATION * 2) / 3);

        // Claims
        vm.startPrank(stakerA);
        uint256 claimedA = regenStaker.claimReward(depositIdA);
        vm.stopPrank();

        vm.startPrank(stakerB);
        uint256 claimedB = regenStaker.claimReward(depositIdB);
        vm.stopPrank();

        uint256 expectedA = (REWARD_AMOUNT / 3) + ((REWARD_AMOUNT * 2) / 3 / 2);
        uint256 expectedB = ((REWARD_AMOUNT * 2) / 3 / 2);

        assertApproxEqAbs(claimedA, expectedA, MIN_ASSERT_TOLERANCE, "Staker A wrong amount");
        assertApproxEqAbs(claimedB, expectedB, MIN_ASSERT_TOLERANCE, "Staker B wrong amount");
        assertApproxEqAbs(
            claimedA + claimedB,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE * 2,
            "Total claimed wrong for staggered"
        );
    }

    function test_ContinuousReward_TwoStakers_DifferentAmounts_ProRataShare() public {
        address stakerA = makeAddr("stakerA_DiffAmt");
        address stakerB = makeAddr("stakerB_DiffAmt");

        address[] memory stakerArrA = new address[](1);
        stakerArrA[0] = stakerA;
        address[] memory stakerArrB = new address[](1);
        stakerArrB[0] = stakerB;
        stakerWhitelist.addToWhitelist(stakerArrA);
        earningPowerWhitelist.addToWhitelist(stakerArrA);
        stakerWhitelist.addToWhitelist(stakerArrB);
        earningPowerWhitelist.addToWhitelist(stakerArrB);

        // Staker A stakes STAKE_AMOUNT
        stakeToken.mint(stakerA, STAKE_AMOUNT);
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositIdA = regenStaker.stake(STAKE_AMOUNT, stakerA);
        vm.stopPrank();

        // Staker B stakes 2 * STAKE_AMOUNT
        stakeToken.mint(stakerB, STAKE_AMOUNT * 2);
        vm.startPrank(stakerB);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT * 2);
        Staker.DepositIdentifier depositIdB = regenStaker.stake(STAKE_AMOUNT * 2, stakerB);
        vm.stopPrank();

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp full period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Claims
        vm.startPrank(stakerA);
        uint256 claimedA = regenStaker.claimReward(depositIdA);
        vm.stopPrank();

        vm.startPrank(stakerB);
        uint256 claimedB = regenStaker.claimReward(depositIdB);
        vm.stopPrank();

        // Total earning power is effectively 3 units (1 from A, 2 from B)
        uint256 expectedA = REWARD_AMOUNT / 3;
        uint256 expectedB = (REWARD_AMOUNT * 2) / 3;

        assertApproxEqAbs(claimedA, expectedA, MIN_ASSERT_TOLERANCE, "Staker A (1x stake) wrong amount");
        assertApproxEqAbs(claimedB, expectedB, MIN_ASSERT_TOLERANCE, "Staker B (2x stake) wrong amount");
        assertApproxEqAbs(
            claimedA + claimedB,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE * 2,
            "Total claimed wrong for different amounts"
        );
    }

    // --- Tests for specific Time-Weighted Reward Distribution Requirements ---

    function test_TimeWeightedReward_NoEarningIfStakedButNotOnEarningWhitelist() public {
        address stakerNoEarn = makeAddr("stakerNoEarn");

        // Whitelist for staking ONLY, not for earning power
        address[] memory stakerArr = new address[](1);
        stakerArr[0] = stakerNoEarn;
        stakerWhitelist.addToWhitelist(stakerArr);
        // DO NOT add to earningPowerWhitelist

        // Ensure calculator's whitelist is the one we are using (it should be by default from setUp)
        assertEq(
            address(IWhitelistedEarningPowerCalculator(address(calculator)).whitelist()),
            address(earningPowerWhitelist)
        );

        // Staker stakes
        stakeToken.mint(stakerNoEarn, STAKE_AMOUNT);
        vm.startPrank(stakerNoEarn);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, stakerNoEarn);
        vm.stopPrank();

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp to end of period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Staker attempts to claim reward
        vm.startPrank(stakerNoEarn);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertEq(claimedAmount, 0, "Staker not on earning whitelist should earn 0 rewards");
    }

    function test_TimeWeightedReward_EarningStopsIfRemovedFromEarningWhitelistMidPeriod() public {
        address staker = makeAddr("stakerMidRemoval");

        // Whitelist for staking AND earning power initially
        address[] memory stakerArr = new address[](1);
        stakerArr[0] = staker;
        stakerWhitelist.addToWhitelist(stakerArr);
        earningPowerWhitelist.addToWhitelist(stakerArr); // Admin (this) is owner of earningPowerWhitelist

        // Staker stakes
        stakeToken.mint(staker, STAKE_AMOUNT);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, staker);
        vm.stopPrank();

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this)); // Admin context
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank(); // Admin context ends for notify

        // Warp half period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Admin removes staker from earningPowerWhitelist
        vm.startPrank(address(this)); // Admin context for whitelist removal and bump
        earningPowerWhitelist.removeFromWhitelist(stakerArr);
        // Admin (or anyone) bumps earning power to reflect the change
        // The calculator's getNewEarningPower should return (0, true)
        regenStaker.bumpEarningPower(depositId, address(this), 0); // Tip to admin, tip amount 0
        vm.stopPrank(); // Admin context ends

        assertFalse(earningPowerWhitelist.isWhitelisted(staker), "Staker should be removed from earning whitelist");
        // Verify earning power in staker contract is now 0
        // Note: depositorTotalEarningPower is public, but deposit.earningPower is internal.
        // We can infer from the claimed amount or check getNewEarningPower behavior separately.
        // For this test, the final claimed amount is the key.

        // Warp to end of original period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Staker claims reward
        vm.startPrank(staker);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        // Expected: rewards for the first half of the period only
        assertApproxEqAbs(
            claimedAmount,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Staker should only earn for the first half period"
        );
    }

    function test_TimeWeightedReward_RateResetsWithNewRewardNotification() public {
        uint256 REWARD_AMOUNT_PART_1 = REWARD_AMOUNT / 2;
        uint256 REWARD_AMOUNT_PART_2 = REWARD_AMOUNT / 2;

        address stakerA = makeAddr("stakerA_MultiNotify");
        address stakerB = makeAddr("stakerB_MultiNotify");

        // Whitelist stakers A and B
        address[] memory stakerArrA = new address[](1);
        stakerArrA[0] = stakerA;
        stakerWhitelist.addToWhitelist(stakerArrA);
        earningPowerWhitelist.addToWhitelist(stakerArrA);

        address[] memory stakerArrB = new address[](1);
        stakerArrB[0] = stakerB;
        stakerWhitelist.addToWhitelist(stakerArrB);
        earningPowerWhitelist.addToWhitelist(stakerArrB);

        // Staker A stakes
        stakeToken.mint(stakerA, STAKE_AMOUNT);
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositIdA = regenStaker.stake(STAKE_AMOUNT, stakerA);
        vm.stopPrank();

        // Admin notifies first reward part
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT); // Mint total for both parts
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT_PART_1);
        vm.stopPrank();

        // Warp half of the first reward period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Staker B stakes (same amount)
        stakeToken.mint(stakerB, STAKE_AMOUNT);
        vm.startPrank(stakerB);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositIdB = regenStaker.stake(STAKE_AMOUNT, stakerB);
        vm.stopPrank();

        // Admin notifies second reward part
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT_PART_2);
        vm.stopPrank();

        // Warp for the full *new* reward period duration
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Stakers claim
        vm.startPrank(stakerA);
        uint256 claimedA = regenStaker.claimReward(depositIdA);
        vm.stopPrank();

        vm.startPrank(stakerB);
        uint256 claimedB = regenStaker.claimReward(depositIdB);
        vm.stopPrank();

        uint256 earningsA_phase1 = REWARD_AMOUNT_PART_1 / 2;
        uint256 remaining_part1 = REWARD_AMOUNT_PART_1 / 2;
        uint256 total_for_new_period = remaining_part1 + REWARD_AMOUNT_PART_2;
        uint256 earnings_each_phase2 = total_for_new_period / 2;

        uint256 expectedA = earningsA_phase1 + earnings_each_phase2;
        uint256 expectedB = earnings_each_phase2;

        assertApproxEqAbs(
            claimedA,
            expectedA,
            MIN_ASSERT_TOLERANCE,
            "Staker A claimed amount incorrect after multiple notifications"
        );
        assertApproxEqAbs(
            claimedB,
            expectedB,
            MIN_ASSERT_TOLERANCE,
            "Staker B claimed amount incorrect after multiple notifications"
        );
        assertApproxEqAbs(
            claimedA + claimedB,
            REWARD_AMOUNT, // Total original reward
            MIN_ASSERT_TOLERANCE * 2,
            "Total claimed does not match total rewards notified"
        );
    }

    // --- Tests for Stake Deposits and Withdrawals Requirements ---

    function test_StakeDeposit_MultipleDepositsSingleUser() public {
        address user = makeAddr("multiDepositUser");

        // Whitelist user
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);

        // Mint tokens for two stakes
        stakeToken.mint(user, STAKE_AMOUNT * 2);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT * 2);

        // First stake
        Staker.DepositIdentifier depositId1 = regenStaker.stake(STAKE_AMOUNT, user);
        // Second stake
        Staker.DepositIdentifier depositId2 = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), STAKE_AMOUNT * 2, "Total staked incorrect");
        // Assuming earning power is 1:1 with stake amount for simplicity here
        assertEq(regenStaker.depositorTotalEarningPower(user), STAKE_AMOUNT * 2, "Total earning power incorrect");

        // Notify rewards
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp full period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Claim for first deposit
        vm.startPrank(user);
        uint256 claimed1 = regenStaker.claimReward(depositId1);
        // Claim for second deposit
        uint256 claimed2 = regenStaker.claimReward(depositId2);
        vm.stopPrank();

        // Each deposit should get half of the total reward since they staked the same amount for the full period
        assertApproxEqAbs(claimed1, REWARD_AMOUNT / 2, MIN_ASSERT_TOLERANCE, "Claimed amount for deposit 1 incorrect");
        assertApproxEqAbs(claimed2, REWARD_AMOUNT / 2, MIN_ASSERT_TOLERANCE, "Claimed amount for deposit 2 incorrect");
        assertApproxEqAbs(claimed1 + claimed2, REWARD_AMOUNT, MIN_ASSERT_TOLERANCE * 2, "Total claimed incorrect");
    }

    function test_StakeDeposit_StakeMore_UpdatesBalanceAndRewards() public {
        address user = makeAddr("stakeMoreUser");
        uint256 initialStake = STAKE_AMOUNT / 2;
        uint256 additionalStake = STAKE_AMOUNT / 2;

        // Whitelist user
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);

        // Mint tokens
        stakeToken.mint(user, initialStake + additionalStake);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), initialStake + additionalStake);

        // Initial stake
        Staker.DepositIdentifier depositId = regenStaker.stake(initialStake, user);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), initialStake);
        assertEq(regenStaker.depositorTotalEarningPower(user), initialStake);

        // Setup and stake otherStaker BEFORE notifying rewards (MOVED HERE)
        address otherStaker = makeAddr("otherStakerForStakeMore");
        address[] memory otherStakerArr = new address[](1);
        otherStakerArr[0] = otherStaker;
        stakerWhitelist.addToWhitelist(otherStakerArr);
        earningPowerWhitelist.addToWhitelist(otherStakerArr);
        stakeToken.mint(otherStaker, STAKE_AMOUNT);
        vm.startPrank(otherStaker);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        regenStaker.stake(STAKE_AMOUNT, otherStaker);
        vm.stopPrank();

        // Notify rewards
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp half period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Stake more
        vm.startPrank(user);
        regenStaker.stakeMore(depositId, additionalStake);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), initialStake + additionalStake);
        assertEq(regenStaker.depositorTotalEarningPower(user), initialStake + additionalStake);

        // Warp remaining half period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Claim rewards
        vm.startPrank(user);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        // Expected: (REWARD_AMOUNT / 2) * (initialStake / (initialStake)) for first half (as user was only staker)
        // + (REWARD_AMOUNT / 2) * ((initialStake + additionalStake) / (initialStake + additionalStake)) for second half
        // Simplified: (REWARD_AMOUNT / 2) * (1/2 share during first half, relative to total stake then) + (REWARD_AMOUNT / 2) * (total share during second half)
        // If user is the only staker:
        // First half: initialStake was totalEarningPower. User earned (REWARD_AMOUNT / REWARD_PERIOD_DURATION) * (REWARD_PERIOD_DURATION / 2) = REWARD_AMOUNT / 2
        // For this, user\'s share was 1. So user got all of (REWARD_AMOUNT / 2)
        // Second half: (initialStake + additionalStake) was totalEarningPower. User earned (REWARD_AMOUNT / 2)
        // Oh, the base staker contract distributes based on share of totalEarningPower.
        // If this user is the only one, they get all rewards.
        // Reward for 1st half period: (REWARD_AMOUNT / 2) because they had 100% of earning power (initialStake)
        // Reward for 2nd half period: (REWARD_AMOUNT / 2) because they had 100% of earning power (initialStake + additionalStake)
        // This calculation will be simpler if only one staker.

        // If user is sole staker:
        // Reward rate = REWARD_AMOUNT / REWARD_PERIOD_DURATION
        // Earnings 1st half = (REWARD_AMOUNT / REWARD_PERIOD_DURATION) * (REWARD_PERIOD_DURATION / 2) = REWARD_AMOUNT / 2
        // Earnings 2nd half = (REWARD_AMOUNT / REWARD_PERIOD_DURATION) * (REWARD_PERIOD_DURATION / 2) = REWARD_AMOUNT / 2
        // Total = REWARD_AMOUNT
        // This test doesn\'t quite test the pro-rata shift well if there\'s only one user.
        // Let\'s add another staker to make the shares change.

        // Recalculate rewards for \'user\'
        // Total EP phase 1 = initialStake (user) + STAKE_AMOUNT (otherStaker)
        // User share phase 1 = initialStake / (initialStake + STAKE_AMOUNT)
        // Earnings user phase 1 = (REWARD_AMOUNT / 2) * (initialStake / (initialStake + STAKE_AMOUNT))

        // Total EP phase 2 = (initialStake + additionalStake) (user) + STAKE_AMOUNT (otherStaker)
        // User share phase 2 = (initialStake + additionalStake) / ((initialStake + additionalStake) + STAKE_AMOUNT)
        // Earnings user phase 2 = (REWARD_AMOUNT / 2) * ((initialStake + additionalStake) / ((initialStake + additionalStake) + STAKE_AMOUNT))

        uint256 totalEpPhase1 = initialStake + STAKE_AMOUNT;
        uint256 earningsUserPhase1 = ((REWARD_AMOUNT / 2) * initialStake) / totalEpPhase1;

        uint256 totalEpPhase2 = (initialStake + additionalStake) + STAKE_AMOUNT;
        uint256 earningsUserPhase2 = ((REWARD_AMOUNT / 2) * (initialStake + additionalStake)) / totalEpPhase2;

        uint256 expectedUserRewards = earningsUserPhase1 + earningsUserPhase2;

        assertApproxEqAbs(
            claimedAmount,
            expectedUserRewards,
            MIN_ASSERT_TOLERANCE * 2,
            "Claimed amount after stakeMore incorrect"
        );
    }

    function test_StakeWithdraw_PartialWithdraw_ReducesBalanceAndImpactsRewards() public {
        address user = makeAddr("partialWithdrawUser");
        uint256 withdrawAmount = STAKE_AMOUNT / 4;

        // Whitelist and stake
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        // Notify rewards
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp half period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Check claimable before withdraw (user is only staker)
        uint256 claimableBeforeWithdraw = regenStaker.unclaimedReward(depositId);
        assertApproxEqAbs(
            claimableBeforeWithdraw,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Claimable before withdraw incorrect"
        );

        // Partial withdraw
        vm.startPrank(user);
        regenStaker.withdraw(depositId, withdrawAmount);
        vm.stopPrank();

        assertEq(
            regenStaker.depositorTotalStaked(user),
            STAKE_AMOUNT - withdrawAmount,
            "Total staked after partial withdraw incorrect"
        );
        assertEq(
            regenStaker.depositorTotalEarningPower(user),
            STAKE_AMOUNT - withdrawAmount,
            "Total EP after partial withdraw incorrect"
        );

        // Warp remaining half period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Claim rewards
        vm.startPrank(user);
        uint256 claimedAfterWithdraw = regenStaker.claimReward(depositId); // This claims all accumulated
        vm.stopPrank();

        // Expected: REWARD_AMOUNT / 2 (from first half, full stake)
        // + REWARD_AMOUNT / 2 (from second half, reduced stake, but still 100% share if only staker)
        // This logic is simple if user is the only staker. They get all rewards.
        // The important part is that `withdraw` doesn't lose *already accrued* rewards.
        // The `claimReward` call after withdraw should include rewards accrued *before* withdraw.
        // `unclaimedReward` before withdraw was REWARD_AMOUNT / 2.
        // After withdraw, and warping, the new rewards for 2nd half are also REWARD_AMOUNT / 2 (as user is only staker).
        // So total claimed should be REWARD_AMOUNT.

        assertApproxEqAbs(
            claimedAfterWithdraw,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE,
            "Total claimed after partial withdraw incorrect"
        );
    }

    function test_StakeWithdraw_FullWithdraw_BalanceZero_ClaimsAccrued_NoFutureRewards() public {
        address user = makeAddr("fullWithdrawUser");

        // Whitelist and stake
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        // Notify rewards
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp half period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Full withdraw
        vm.startPrank(user);
        regenStaker.withdraw(depositId, STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), 0, "Total staked after full withdraw should be 0");
        assertEq(regenStaker.depositorTotalEarningPower(user), 0, "Total EP after full withdraw should be 0");

        // Claim accrued rewards immediately after withdraw
        vm.startPrank(user);
        uint256 claimedImmediately = regenStaker.claimReward(depositId);
        vm.stopPrank();
        // Should be rewards for the first half
        assertApproxEqAbs(
            claimedImmediately,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Claimed immediately after full withdraw incorrect"
        );

        // Warp remaining half period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Attempt to claim again (should get 0 new rewards)
        vm.startPrank(user);
        uint256 claimedLater = regenStaker.claimReward(depositId);
        vm.stopPrank();
        assertEq(claimedLater, 0, "Should claim 0 rewards later as no stake was present");
    }

    function test_StakeWithdraw_FullWithdrawAndRestake_ResetsTimeAdvantage() public {
        address stakerA = makeAddr("stakerA_WithdrawRestake");
        address stakerB = makeAddr("stakerB_Continuous"); // Stays for full duration

        // Whitelist stakers
        address[] memory arrA = new address[](1);
        arrA[0] = stakerA;
        stakerWhitelist.addToWhitelist(arrA);
        earningPowerWhitelist.addToWhitelist(arrA);
        address[] memory arrB = new address[](1);
        arrB[0] = stakerB;
        stakerWhitelist.addToWhitelist(arrB);
        earningPowerWhitelist.addToWhitelist(arrB);

        // Mint tokens
        stakeToken.mint(stakerA, STAKE_AMOUNT * 2); // For initial stake and re-stake
        stakeToken.mint(stakerB, STAKE_AMOUNT);

        // T0: Staker A and B stake
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositIdA1 = regenStaker.stake(STAKE_AMOUNT, stakerA);
        vm.stopPrank();

        vm.startPrank(stakerB);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositIdB = regenStaker.stake(STAKE_AMOUNT, stakerB);
        vm.stopPrank();

        // Notify rewards
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(address(this));
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp to T1 (1/3 of period)
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 3);

        // T1: Staker A fully withdraws depositIdA1
        vm.startPrank(stakerA);
        regenStaker.withdraw(depositIdA1, STAKE_AMOUNT);
        // Claim rewards from first stake period for A
        uint256 claimedA_period1 = regenStaker.claimReward(depositIdA1);
        vm.stopPrank();

        // Warp to T2 (2/3 of period total, or 1/3 since T1)
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 3);

        // T2: Staker A re-stakes (new deposit)
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT); // Approve for the new stake
        Staker.DepositIdentifier depositIdA2 = regenStaker.stake(STAKE_AMOUNT, stakerA);
        vm.stopPrank();

        // Warp to T_end (remaining 1/3 of period)
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 3);

        // At T_end: Claim rewards for Staker A (depositIdA2) and Staker B (depositIdB)
        vm.startPrank(stakerA);
        uint256 claimedA_period2 = regenStaker.claimReward(depositIdA2);
        vm.stopPrank();

        vm.startPrank(stakerB);
        uint256 claimedB_total = regenStaker.claimReward(depositIdB);
        vm.stopPrank();

        // --- Expected Calculations ---
        // Phase 1 (0 to T1 = 1/3 duration): Staker A and B both staked STAKE_AMOUNT. Total EP = 2 * STAKE_AMOUNT. Each gets 1/2.
        // Reward for phase 1 = REWARD_AMOUNT / 3
        uint256 expected_claimedA_period1 = (REWARD_AMOUNT / 3) / 2;
        assertApproxEqAbs(
            claimedA_period1,
            expected_claimedA_period1,
            MIN_ASSERT_TOLERANCE,
            "Staker A phase 1 claim incorrect"
        );

        // Phase 2 (T1 to T2 = 1/3 duration): Only Staker B staked STAKE_AMOUNT. Total EP = STAKE_AMOUNT. B gets all.
        // Reward for phase 2 = REWARD_AMOUNT / 3
        // Staker B accumulated this entirely.

        // Phase 3 (T2 to T_end = 1/3 duration): Staker A and B both staked STAKE_AMOUNT. Total EP = 2 * STAKE_AMOUNT. Each gets 1/2.
        // Reward for phase 3 = REWARD_AMOUNT / 3
        uint256 expected_claimedA_period2 = (REWARD_AMOUNT / 3) / 2;
        assertApproxEqAbs(
            claimedA_period2,
            expected_claimedA_period2,
            MIN_ASSERT_TOLERANCE,
            "Staker A phase 2 (re-stake) claim incorrect"
        );

        // Total for B: (Phase1_B_share) + (Phase2_B_share) + (Phase3_B_share)
        // Phase1_B_share = (REWARD_AMOUNT / 3) / 2
        // Phase2_B_share = REWARD_AMOUNT / 3 (all of it)
        // Phase3_B_share = (REWARD_AMOUNT / 3) / 2
        uint256 expected_claimedB_total = (REWARD_AMOUNT / 3) / 2 + (REWARD_AMOUNT / 3) + (REWARD_AMOUNT / 3) / 2;
        assertApproxEqAbs(
            claimedB_total,
            expected_claimedB_total,
            MIN_ASSERT_TOLERANCE * 2,
            "Staker B total claim incorrect"
        ); // Higher tolerance for sum

        uint256 totalClaimedRewards = claimedA_period1 + claimedA_period2 + claimedB_total;
        assertApproxEqAbs(
            totalClaimedRewards,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE * 3,
            "Overall total rewards claimed mismatch"
        );
    }
}
