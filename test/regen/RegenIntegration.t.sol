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

        assertApproxEqAbs(claimedAmount, REWARD_AMOUNT, 1e18, "Staker should receive full reward"); // Allow 1 token diff
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

        assertApproxEqAbs(claimedAmount, REWARD_AMOUNT / 2, 1e18, "Late staker should receive half reward");
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

        assertApproxEqAbs(claimedAmount1, REWARD_AMOUNT / 2, 1e18, "Mid-period claim should be half reward");

        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2); // To end of period

        vm.startPrank(staker);
        uint256 claimedAmount2 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqAbs(claimedAmount2, REWARD_AMOUNT / 2, 1e18, "Second claim should be remaining half");
        assertApproxEqAbs(claimedAmount1 + claimedAmount2, REWARD_AMOUNT, 2e18, "Total claimed should be full reward");
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

        assertApproxEqAbs(claimedA, expectedA, 1e18, "Staker A wrong amount");
        assertApproxEqAbs(claimedB, expectedB, 1e18, "Staker B wrong amount");
        assertApproxEqAbs(claimedA + claimedB, REWARD_AMOUNT, 2e18, "Total claimed wrong for staggered");
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

        assertApproxEqAbs(claimedA, expectedA, 1e18, "Staker A (1x stake) wrong amount");
        assertApproxEqAbs(claimedB, expectedB, 1e18, "Staker B (2x stake) wrong amount");
        assertApproxEqAbs(claimedA + claimedB, REWARD_AMOUNT, 2e18, "Total claimed wrong for different amounts");
    }
}
