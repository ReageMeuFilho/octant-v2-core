// SPDX-License-Identifier: MIT
// Tests are named according to https://github.com/ScopeLift/scopelint/blob/1857e3940bfe92ac5a136827374f4b27ff083971/src/check/validators/test_names.rs#L106-L143
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
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol"; // For Staker__Unauthorized if Ownable error is used
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IGrantRound } from "../../src/regen/IGrantRound.sol";

contract RegenIntegrationTest is Test {
    RegenStaker regenStaker;
    RegenEarningPowerCalculator calculator;
    Whitelist stakerWhitelist;
    Whitelist contributorWhitelist;
    Whitelist earningPowerWhitelist;
    MockERC20 rewardToken;
    MockERC20Staking stakeToken;

    uint256 public constant REWARD_AMOUNT = 30_000_000 * 1e18; // 30M tokens
    uint256 public constant STAKE_AMOUNT = 1_000 * 1e18; // 1K tokens
    uint256 public constant REWARD_PERIOD_DURATION = 30 days;
    uint256 public constant MIN_ASSERT_TOLERANCE = 1; // 1e-20 is the smallest relative error that can be detected. https://book.getfoundry.sh/reference/ds-test?highlight=approx#assertapproxeqrel
    uint256 public constant MAX_BUMP_TIP = 1e18; // Maximum tip allowed for bumping earning power
    uint256 public constant MAX_CLAIM_FEE = 1e18; // Maximum fee for claiming rewards
    address public immutable ADMIN = makeAddr("admin");

    function setUp() public {
        vm.startPrank(ADMIN);

        // Deploy mock tokens
        rewardToken = new MockERC20();
        stakeToken = new MockERC20Staking();

        // Deploy three whitelists
        stakerWhitelist = new Whitelist();
        contributorWhitelist = new Whitelist();
        earningPowerWhitelist = new Whitelist();

        // Deploy the calculator
        calculator = new RegenEarningPowerCalculator(ADMIN, earningPowerWhitelist);

        // Deploy the staker
        regenStaker = new RegenStaker(
            IERC20(address(rewardToken)),
            IERC20Staking(address(stakeToken)),
            ADMIN,
            stakerWhitelist,
            contributorWhitelist,
            calculator,
            MAX_BUMP_TIP,
            MAX_CLAIM_FEE
        );

        // Make this contract a reward notifier
        regenStaker.setRewardNotifier(ADMIN, true);
        vm.stopPrank();
    }

    function test_Constructor_InitializesWhitelistsToNewIfAddressZero() public {
        // Deploy RegenStaker with address(0) for both whitelist parameters
        RegenStaker localRegenStaker = new RegenStaker(
            IERC20(address(rewardToken)),
            IERC20Staking(address(stakeToken)),
            ADMIN,
            Whitelist(address(0)), // _stakerWhitelist
            Whitelist(address(0)), // _contributionWhitelist
            calculator,
            MAX_BUMP_TIP,
            MAX_CLAIM_FEE
        );

        // Assert that the whitelists are not address(0) but new Whitelist instances
        assertTrue(
            address(localRegenStaker.stakerWhitelist()) != address(0),
            "Staker whitelist should be a new instance, not address(0)"
        );
        assertTrue(
            address(localRegenStaker.contributionWhitelist()) != address(0),
            "Contribution whitelist should be a new instance, not address(0)"
        );

        // When RegenStaker does `new Whitelist()`, RegenStaker is the msg.sender for that sub-call,
        // and the Whitelist constructor sets msg.sender as its owner.
        assertEq(
            Ownable(address(localRegenStaker.stakerWhitelist())).owner(),
            address(localRegenStaker),
            "Owner of new staker whitelist incorrect"
        );
        assertEq(
            Ownable(address(localRegenStaker.contributionWhitelist())).owner(),
            address(localRegenStaker),
            "Owner of new contrib whitelist incorrect"
        );
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

    function test_NonAdminCannotSetStakerWhitelist() public {
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.setStakerWhitelist(Whitelist(address(0)));
        vm.stopPrank();
    }

    function test_NonAdminCannotSetContributionWhitelist() public {
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.setContributionWhitelist(Whitelist(address(0)));
        vm.stopPrank();
    }

    function test_NonAdminCannotSetEarningPowerWhitelist() public {
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonAdmin));
        calculator.setWhitelist(Whitelist(address(0)));
        vm.stopPrank();
    }

    function test_AllowsStakingIfStakerWhitelistDisabled_RevertIf_ActiveAndUserNotWhitelisted() public {
        address nonWhitelistedUser = makeAddr("nonWhitelistedUser");

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

        vm.prank(ADMIN);
        regenStaker.setStakerWhitelist(Whitelist(address(0))); // Disables the whitelist
        assertEq(address(regenStaker.stakerWhitelist()), address(0));

        // Try staking again with the same non-whitelisted user. This should succeed.
        vm.startPrank(nonWhitelistedUser);
        regenStaker.stake(50, nonWhitelistedUser);

        vm.stopPrank();
    }

    function test_AllowsContributionIfContributorWhitelistDisabled_RevertIf_ActiveAndUserNotWhitelisted() public {
        // Setup a contributor who is whitelisted for staking but NOT for contributing
        address contributor = makeAddr("contributorNotWhitelistedForContributing");
        address mockGrantRound = makeAddr("mockGrantRound");

        // Whitelist contributor for staking and earning power, but NOT for contributing
        address[] memory contributorArr = new address[](1);
        contributorArr[0] = contributor;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(contributorArr);
        earningPowerWhitelist.addToWhitelist(contributorArr);
        // Note: We do NOT add to contributorWhitelist
        vm.stopPrank();

        // Create deposit and earn rewards
        stakeToken.mint(contributor, STAKE_AMOUNT);
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(contributor);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, contributor);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);

        // Warp to accumulate rewards
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Setup mock calls for the grant round to avoid external call issues
        uint256 contributionAmount = 1e16;
        uint256[] memory prefs = new uint256[](1);
        prefs[0] = 1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = contributionAmount;

        vm.mockCall(
            mockGrantRound,
            abi.encodeWithSignature("signup(uint256,address,bytes32)", contributionAmount, contributor, bytes32(0)),
            abi.encode(uint256(1))
        );
        vm.mockCall(
            mockGrantRound,
            abi.encodeWithSignature("vote(uint256,uint256)", prefs[0], weights[0]),
            abi.encode()
        );

        // Verify contribution whitelist is active and contributor is not on it
        assertTrue(
            address(regenStaker.contributionWhitelist()) != address(0),
            "Contribution whitelist should be active"
        );
        assertFalse(
            regenStaker.contributionWhitelist().isWhitelisted(contributor),
            "Contributor should not be whitelisted for contributing"
        );

        // Try contributing while not whitelisted for contributing (should revert)
        vm.startPrank(contributor);
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStaker.NotWhitelisted.selector,
                regenStaker.contributionWhitelist(),
                contributor
            )
        );
        regenStaker.contribute(depositId, mockGrantRound, contributor, contributionAmount, bytes32(0));
        vm.stopPrank();

        // Disable the contribution whitelist
        vm.prank(ADMIN);
        regenStaker.setContributionWhitelist(Whitelist(address(0)));

        // Verify whitelist is disabled
        assertEq(address(regenStaker.contributionWhitelist()), address(0), "Whitelist should be disabled");

        // Try contributing again - should succeed now
        vm.prank(contributor);
        regenStaker.contribute(depositId, mockGrantRound, contributor, contributionAmount, bytes32(0));
    }

    function test_GrantsEarningPowerToNewUserIfEarningPowerWhitelistDisabled() public {
        // Setup two users - one whitelisted, one not
        address whitelistedUser = makeAddr("whitelistedUser");
        address nonWhitelistedUser = makeAddr("nonWhitelistedUser");

        // Mint tokens to both users
        stakeToken.mint(whitelistedUser, 1000);
        stakeToken.mint(nonWhitelistedUser, 1000);

        // Whitelist the first user for staking and earning power
        address[] memory users = new address[](1);
        users[0] = whitelistedUser;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(users);
        earningPowerWhitelist.addToWhitelist(users);

        // Also whitelist the non-whitelisted user for staking (but not for earning power)
        users[0] = nonWhitelistedUser;
        stakerWhitelist.addToWhitelist(users);
        vm.stopPrank();

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

        vm.prank(ADMIN);
        IWhitelistedEarningPowerCalculator(address(calculator)).setWhitelist(Whitelist(address(0)));

        // Verify whitelist is now address(0)
        assertEq(
            address(IWhitelistedEarningPowerCalculator(address(regenStaker.earningPowerCalculator())).whitelist()),
            address(0)
        );

        // Check if existing nonWhitelistedUser automatically gets earning power after disabling whitelist
        uint256 nonWhitelistedEarningPowerAfterDisable = regenStaker.depositorTotalEarningPower(nonWhitelistedUser);
        assertEq(
            nonWhitelistedEarningPowerAfterDisable,
            0,
            "Existing non-whitelisted user does not automatically get earning power"
        );

        // We need to bump the earning power for the existing deposit to update it
        // Get the deposit ID for nonWhitelistedUser
        Staker.DepositIdentifier nonWhitelistedDepositId = Staker.DepositIdentifier.wrap(1); // nonWhitelistedUser's deposit is the second one (ID 1)

        vm.prank(ADMIN); // Use admin to avoid tip requirements
        regenStaker.bumpEarningPower(nonWhitelistedDepositId, ADMIN, 0); // No tip needed when admin bumps

        // Check earning power after bumping
        uint256 nonWhitelistedEarningPowerAfterBump = regenStaker.depositorTotalEarningPower(nonWhitelistedUser);
        assertEq(
            nonWhitelistedEarningPowerAfterBump,
            1000,
            "After bumping, existing non-whitelisted user should get earning power"
        );

        // Add a new non-whitelisted user to verify they now get earning power without being whitelisted
        address newUser = makeAddr("newUser");
        stakeToken.mint(newUser, 1000);

        // Whitelist for staking only
        users[0] = newUser;
        vm.prank(ADMIN);
        stakerWhitelist.addToWhitelist(users);

        // Stake with the new user
        vm.startPrank(newUser);
        stakeToken.approve(address(regenStaker), 1000);
        regenStaker.stake(1000, newUser);
        vm.stopPrank();

        // Check earning power is granted for new stakes without needing a bump
        uint256 newUserEarningPower = regenStaker.depositorTotalEarningPower(newUser);
        assertEq(
            newUserEarningPower,
            1000,
            "New users should automatically get earning power when whitelist is disabled"
        );
    }

    function test_RevertIf_PauseCalledByNonAdmin() public {
        // Attempt to pause from a non-admin account
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.pause();
        vm.stopPrank();

        // Pause as admin (this contract)
        vm.startPrank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused(), "Contract should be paused");
        vm.stopPrank();
    }

    function test_RevertIf_UnpauseCalledByNonAdmin() public {
        // First, pause the contract as admin
        vm.startPrank(ADMIN);
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
        vm.startPrank(ADMIN);
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
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(users);
        vm.stopPrank();

        // Pause the contract as admin
        vm.startPrank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused(), "Contract should be paused");
        vm.stopPrank();

        // Attempt to stake while paused
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        regenStaker.stake(50, user);
        vm.stopPrank();

        // Unpause the contract for other tests
        vm.startPrank(ADMIN);
        regenStaker.unpause();
        assertFalse(regenStaker.paused(), "Contract should be unpaused");
        vm.stopPrank();
    }

    function test_RevertIf_ContributeWhenPaused() public {
        // --- Setup for contribution ---
        address mockGrantRound = makeAddr("mockGrantRound");
        // Generic mock for signup
        vm.mockCall(
            mockGrantRound,
            abi.encodeWithSignature("signup(uint256,address,bytes32)", uint256(0), address(0), bytes32(0)),
            abi.encode(uint256(1))
        );
        // Generic mock for vote
        vm.mockCall(
            mockGrantRound,
            abi.encodeWithSignature("vote(uint256,uint256)", uint256(0), uint256(0)),
            abi.encode()
        );

        // Create a depositor/contributor
        address contributor = makeAddr("contributor");

        // Mint tokens and approve
        stakeToken.mint(contributor, 1000);
        rewardToken.mint(address(regenStaker), 1e18); // 1e18 reward

        vm.startPrank(contributor);
        stakeToken.approve(address(regenStaker), 1000);

        // Whitelist the contributor for staking, contribution, and earning power
        address[] memory users = new address[](1);
        users[0] = contributor;
        vm.stopPrank(); // Stop contributor prank
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(users);
        contributorWhitelist.addToWhitelist(users);
        earningPowerWhitelist.addToWhitelist(users);
        vm.stopPrank();

        // Stake tokens
        vm.startPrank(contributor);
        Staker.DepositIdentifier depositId = regenStaker.stake(1000, contributor);
        vm.stopPrank();

        // Notify rewards
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(1e18);

        // Fast forward time to accumulate rewards
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);
        vm.stopPrank(); // Stop admin prank after notify/warp
        // --- End Setup ---

        // Pause the contract as admin
        vm.startPrank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused(), "Contract should be paused");
        vm.stopPrank();

        // Attempt to contribute while paused
        vm.startPrank(contributor);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));

        address actualVotingDelegatee = contributor;
        uint256 amountToContribute = 1e12;
        uint256[] memory prefsArray = new uint256[](1);
        prefsArray[0] = 1;
        uint256[] memory weightsArray = new uint256[](1);
        weightsArray[0] = amountToContribute;

        regenStaker.contribute(depositId, mockGrantRound, actualVotingDelegatee, amountToContribute, bytes32(0));
        vm.stopPrank();
    }

    function test_ContinuousReward_SingleStaker_FullPeriod() public {
        address staker = makeAddr("staker");

        // Whitelist staker for staking and earning power
        address[] memory stakers = new address[](1);
        stakers[0] = staker;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(stakers);
        earningPowerWhitelist.addToWhitelist(stakers);
        vm.stopPrank();
        // Staker stakes
        stakeToken.mint(staker, STAKE_AMOUNT);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, staker);
        vm.stopPrank();

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT); // Ensure contract has tokens
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp to end of period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Staker claims reward
        vm.startPrank(staker);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqRel(claimedAmount, REWARD_AMOUNT, MIN_ASSERT_TOLERANCE, "Staker should receive full reward");
    }

    function test_ContinuousReward_SingleStaker_JoinsLate() public {
        address staker = makeAddr("stakerLate");

        // Whitelist staker for staking and earning power
        address[] memory stakers = new address[](1);
        stakers[0] = staker;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(stakers);
        earningPowerWhitelist.addToWhitelist(stakers);
        vm.stopPrank();

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
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

        assertApproxEqRel(
            claimedAmount,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Late staker should receive half reward"
        );
    }

    function test_ContinuousReward_SingleStaker_ClaimsMidPeriod() public {
        address staker = makeAddr("stakerMidClaim");

        address[] memory stakers = new address[](1);
        stakers[0] = staker;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(stakers);
        earningPowerWhitelist.addToWhitelist(stakers);
        vm.stopPrank();

        stakeToken.mint(staker, STAKE_AMOUNT);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, staker);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        vm.startPrank(staker);
        uint256 claimedAmount1 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqRel(
            claimedAmount1,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Mid-period claim should be half reward"
        );

        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2); // To end of period

        vm.startPrank(staker);
        uint256 claimedAmount2 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqRel(
            claimedAmount2,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Second claim should be remaining half"
        );
        assertApproxEqRel(
            claimedAmount1 + claimedAmount2,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE,
            "Total claimed should be full reward"
        );
    }

    function test_ContinuousReward_TwoStakers_StaggeredEntry_ProRataShare() public {
        address stakerA = makeAddr("stakerA_Staggered");
        address stakerB = makeAddr("stakerB_Staggered");

        address[] memory stakers = new address[](2);
        stakers[0] = stakerA;
        stakers[1] = stakerB;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(stakers);
        earningPowerWhitelist.addToWhitelist(stakers);
        vm.stopPrank();

        // Staker A stakes
        stakeToken.mint(stakerA, STAKE_AMOUNT);
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositIdA = regenStaker.stake(STAKE_AMOUNT, stakerA);
        vm.stopPrank();

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
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
        uint256 expectedB = (REWARD_AMOUNT * 2) / 3 / 2;

        assertApproxEqRel(claimedA, expectedA, MIN_ASSERT_TOLERANCE, "Staker A wrong amount");
        assertApproxEqRel(claimedB, expectedB, MIN_ASSERT_TOLERANCE, "Staker B wrong amount");
        assertApproxEqRel(
            claimedA + claimedB,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE * 2,
            "Total claimed wrong for staggered"
        );
    }

    function test_ContinuousReward_TwoStakers_DifferentAmounts_ProRataShare() public {
        address stakerA = makeAddr("stakerA_DiffAmt");
        address stakerB = makeAddr("stakerB_DiffAmt");

        address[] memory stakers = new address[](2);
        stakers[0] = stakerA;
        stakers[1] = stakerB;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(stakers);
        earningPowerWhitelist.addToWhitelist(stakers);
        vm.stopPrank();

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
        vm.startPrank(ADMIN);
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

        assertApproxEqRel(claimedA, expectedA, MIN_ASSERT_TOLERANCE, "Staker A (1x stake) wrong amount");
        assertApproxEqRel(claimedB, expectedB, MIN_ASSERT_TOLERANCE, "Staker B (2x stake) wrong amount");
        assertApproxEqRel(
            claimedA + claimedB,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE,
            "Total claimed wrong for different amounts"
        );
    }

    function test_TimeWeightedReward_NoEarningIfStakedButNotOnEarningWhitelist() public {
        address stakerNoEarn = makeAddr("stakerNoEarn");

        // Whitelist for staking ONLY, not for earning power
        address[] memory stakerArr = new address[](1);
        stakerArr[0] = stakerNoEarn;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(stakerArr);
        vm.stopPrank();
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
        vm.startPrank(ADMIN);
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
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(stakerArr);
        earningPowerWhitelist.addToWhitelist(stakerArr); // Admin (this) is owner of earningPowerWhitelist
        vm.stopPrank();

        // Staker stakes
        stakeToken.mint(staker, STAKE_AMOUNT);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, staker);
        vm.stopPrank();

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN); // Admin context
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank(); // Admin context ends for notify

        // Warp half period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Admin removes staker from earningPowerWhitelist
        vm.startPrank(ADMIN); // Admin context for whitelist removal and bump
        earningPowerWhitelist.removeFromWhitelist(stakerArr);
        // Admin (or anyone) bumps earning power to reflect the change
        // The calculator's getNewEarningPower should return (0, true)
        regenStaker.bumpEarningPower(depositId, ADMIN, 0); // Tip to admin, tip amount 0
        vm.stopPrank(); // Admin context ends

        assertFalse(earningPowerWhitelist.isWhitelisted(staker), "Staker should be removed from earning whitelist");
        assertEq(regenStaker.depositorTotalEarningPower(staker), 0, "Staker should have 0 earning power");

        // Warp to end of original period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Staker claims reward
        vm.startPrank(staker);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        // Expected: rewards for the first half of the period only
        assertApproxEqRel(
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
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(stakerArrA);
        earningPowerWhitelist.addToWhitelist(stakerArrA);

        address[] memory stakerArrB = new address[](1);
        stakerArrB[0] = stakerB;
        stakerWhitelist.addToWhitelist(stakerArrB);
        earningPowerWhitelist.addToWhitelist(stakerArrB);
        vm.stopPrank();

        // Staker A stakes
        stakeToken.mint(stakerA, STAKE_AMOUNT);
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositIdA = regenStaker.stake(STAKE_AMOUNT, stakerA);
        vm.stopPrank();

        // Admin notifies first reward part
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT); // Mint total for both parts
        vm.startPrank(ADMIN);
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
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT_PART_2);
        vm.stopPrank();

        // Warp for the full new reward period duration
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

        assertApproxEqRel(
            claimedA,
            expectedA,
            MIN_ASSERT_TOLERANCE,
            "Staker A claimed amount incorrect after multiple notifications"
        );
        assertApproxEqRel(
            claimedB,
            expectedB,
            MIN_ASSERT_TOLERANCE,
            "Staker B claimed amount incorrect after multiple notifications"
        );
        assertApproxEqRel(
            claimedA + claimedB,
            REWARD_AMOUNT, // Total original reward
            MIN_ASSERT_TOLERANCE,
            "Total claimed does not match total rewards notified"
        );
    }

    function test_StakeDeposit_MultipleDepositsSingleUser() public {
        address user = makeAddr("multiDepositUser");

        // Whitelist user
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        vm.stopPrank();

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
        vm.startPrank(ADMIN);
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
        assertApproxEqRel(claimed1, REWARD_AMOUNT / 2, MIN_ASSERT_TOLERANCE, "Claimed amount for deposit 1 incorrect");
        assertApproxEqRel(claimed2, REWARD_AMOUNT / 2, MIN_ASSERT_TOLERANCE, "Claimed amount for deposit 2 incorrect");
        assertApproxEqRel(claimed1 + claimed2, REWARD_AMOUNT, MIN_ASSERT_TOLERANCE, "Total claimed incorrect");
    }

    function test_StakeDeposit_StakeMore_UpdatesBalanceAndRewards() public {
        address user = makeAddr("stakeMoreUser");
        uint256 initialStake = STAKE_AMOUNT / 2;
        uint256 additionalStake = STAKE_AMOUNT / 2;

        // Whitelist user
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        vm.stopPrank();

        // Mint tokens
        stakeToken.mint(user, initialStake + additionalStake);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), initialStake + additionalStake);

        // Initial stake
        Staker.DepositIdentifier depositId = regenStaker.stake(initialStake, user);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), initialStake);
        assertEq(regenStaker.depositorTotalEarningPower(user), initialStake);

        // Setup and stake otherStaker BEFORE notifying rewards
        address otherStaker = makeAddr("otherStakerForStakeMore");
        address[] memory otherStakerArr = new address[](1);
        otherStakerArr[0] = otherStaker;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(otherStakerArr);
        earningPowerWhitelist.addToWhitelist(otherStakerArr);
        vm.stopPrank();
        stakeToken.mint(otherStaker, STAKE_AMOUNT);
        vm.startPrank(otherStaker);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        regenStaker.stake(STAKE_AMOUNT, otherStaker);
        vm.stopPrank();

        // Notify rewards
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
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

        uint256 totalEpPhase1 = initialStake + STAKE_AMOUNT;
        uint256 earningsUserPhase1 = ((REWARD_AMOUNT / 2) * initialStake) / totalEpPhase1;

        uint256 totalEpPhase2 = (initialStake + additionalStake) + STAKE_AMOUNT;
        uint256 earningsUserPhase2 = ((REWARD_AMOUNT / 2) * (initialStake + additionalStake)) / totalEpPhase2;

        uint256 expectedUserRewards = earningsUserPhase1 + earningsUserPhase2;

        assertApproxEqRel(
            claimedAmount,
            expectedUserRewards,
            MIN_ASSERT_TOLERANCE,
            "Claimed amount after stakeMore incorrect"
        );
    }

    function test_StakeWithdraw_PartialWithdraw_ReducesBalanceAndImpactsRewards() public {
        address user = makeAddr("partialWithdrawUser");
        address otherStaker = makeAddr("otherStakerForWithdraw");
        uint256 withdrawAmount = STAKE_AMOUNT / 4;
        uint256 otherStakerAmount = STAKE_AMOUNT / 2; // Other staker has half the stake

        // Whitelist both users
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);

        userArr[0] = otherStaker;
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        vm.stopPrank();

        // First user stakes
        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        // Second user stakes
        stakeToken.mint(otherStaker, otherStakerAmount);
        vm.startPrank(otherStaker);
        stakeToken.approve(address(regenStaker), otherStakerAmount);
        Staker.DepositIdentifier otherDepositId = regenStaker.stake(otherStakerAmount, otherStaker);
        vm.stopPrank();

        // Notify rewards
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp half period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Calculate expected rewards for first half
        uint256 totalEpPhase1 = STAKE_AMOUNT + otherStakerAmount;
        uint256 userSharePhase1 = (STAKE_AMOUNT * 1e18) / totalEpPhase1; // Using 1e18 for precision
        uint256 expectedUserPhase1 = ((REWARD_AMOUNT / 2) * userSharePhase1) / 1e18;

        // Partial withdraw for main user
        vm.startPrank(user);
        regenStaker.withdraw(depositId, withdrawAmount);
        vm.stopPrank();

        // Verify balances after withdrawal
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

        // Calculate expected rewards for second half (with reduced stake)
        uint256 totalEpPhase2 = (STAKE_AMOUNT - withdrawAmount) + otherStakerAmount;
        uint256 userSharePhase2 = ((STAKE_AMOUNT - withdrawAmount) * 1e18) / totalEpPhase2;
        uint256 expectedUserPhase2 = ((REWARD_AMOUNT / 2) * userSharePhase2) / 1e18;

        uint256 expectedTotalUserRewards = expectedUserPhase1 + expectedUserPhase2;

        // Claim rewards for main user
        vm.startPrank(user);
        uint256 claimedAfterWithdraw = regenStaker.claimReward(depositId);
        vm.stopPrank();

        // Claim rewards for other staker (just to verify total)
        vm.startPrank(otherStaker);
        uint256 claimedByOtherStaker = regenStaker.claimReward(otherDepositId);
        vm.stopPrank();

        // Verify main user's rewards
        assertApproxEqRel(
            claimedAfterWithdraw,
            expectedTotalUserRewards,
            1e7, // Higher tolerance to account for division rounding
            "User rewards after partial withdraw incorrect"
        );

        // Verify total rewards claimed match the total distributed
        assertApproxEqRel(
            claimedAfterWithdraw + claimedByOtherStaker,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE,
            "Total claimed rewards should match total reward amount"
        );
    }

    function test_StakeWithdraw_FullWithdraw_BalanceZero_ClaimsAccrued_NoFutureRewards() public {
        address user = makeAddr("fullWithdrawUser");

        // Whitelist and stake
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        vm.stopPrank();
        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        // Notify rewards
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
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
        assertApproxEqRel(
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
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(arrA);
        earningPowerWhitelist.addToWhitelist(arrA);
        address[] memory arrB = new address[](1);
        arrB[0] = stakerB;
        stakerWhitelist.addToWhitelist(arrB);
        earningPowerWhitelist.addToWhitelist(arrB);
        vm.stopPrank();

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
        vm.startPrank(ADMIN);
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
        assertApproxEqRel(
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
        assertApproxEqRel(
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
        assertApproxEqRel(
            claimedB_total,
            expected_claimedB_total,
            MIN_ASSERT_TOLERANCE,
            "Staker B total claim incorrect"
        ); // Higher tolerance for sum

        uint256 totalClaimedRewards = claimedA_period1 + claimedA_period2 + claimedB_total;
        assertApproxEqRel(
            totalClaimedRewards,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE,
            "Overall total rewards claimed mismatch"
        );
    }

    function test_RewardClaiming_ClaimByDesignatedClaimer_Succeeds() public {
        address owner = makeAddr("depositOwner");
        address designatedClaimer = makeAddr("designatedClaimer");

        // Whitelist owner for staking and earning power
        address[] memory ownerArr = new address[](1);
        ownerArr[0] = owner;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(ownerArr);
        earningPowerWhitelist.addToWhitelist(ownerArr);
        vm.stopPrank();

        // Owner stakes
        stakeToken.mint(owner, STAKE_AMOUNT);
        vm.startPrank(owner);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, owner);

        // Owner designates designatedClaimer as the claimer for the deposit
        regenStaker.alterClaimer(depositId, designatedClaimer);
        vm.stopPrank(); // Stop owner's prank

        (, , , , address retrievedClaimer, , ) = regenStaker.deposits(depositId);
        assertEq(retrievedClaimer, designatedClaimer, "Claimer not set correctly");

        // Admin notifies reward
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Warp to mid-period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Designated claimer claims reward
        uint256 initialBalanceClaimer = rewardToken.balanceOf(designatedClaimer);
        vm.startPrank(designatedClaimer);
        uint256 claimedAmount1 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqRel(
            claimedAmount1,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Claimer did not receive correct first half reward"
        );
        assertEq(
            rewardToken.balanceOf(designatedClaimer),
            initialBalanceClaimer + claimedAmount1,
            "Claimer did not receive tokens for first claim"
        );

        // Warp to end of period
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2);

        // Designated claimer claims reward again
        initialBalanceClaimer = rewardToken.balanceOf(designatedClaimer);
        vm.startPrank(designatedClaimer);
        uint256 claimedAmount2 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqRel(
            claimedAmount2,
            REWARD_AMOUNT / 2,
            MIN_ASSERT_TOLERANCE,
            "Claimer did not receive correct second half reward"
        );
        assertEq(
            rewardToken.balanceOf(designatedClaimer),
            initialBalanceClaimer + claimedAmount2,
            "Claimer did not receive tokens for second claim"
        );

        assertApproxEqRel(
            claimedAmount1 + claimedAmount2,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE,
            "Total claimed by claimer incorrect"
        );
    }

    function test_RewardClaiming_RevertIf_ClaimByNonOwnerNonClaimer() public {
        address owner = makeAddr("depositOwner2");
        address designatedClaimer = makeAddr("designatedClaimer2");
        address unrelatedUser = makeAddr("unrelatedUser");

        // Whitelist owner
        address[] memory ownerArr = new address[](1);
        ownerArr[0] = owner;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(ownerArr);
        earningPowerWhitelist.addToWhitelist(ownerArr);
        vm.stopPrank();

        // Owner stakes and sets designatedClaimer
        stakeToken.mint(owner, STAKE_AMOUNT);
        vm.startPrank(owner);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, owner);
        regenStaker.alterClaimer(depositId, designatedClaimer);
        vm.stopPrank();

        // Notify reward and warp
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Unrelated user attempts to claim
        vm.startPrank(unrelatedUser);
        vm.expectRevert(
            abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not claimer or owner"), unrelatedUser)
        );
        regenStaker.claimReward(depositId);
        vm.stopPrank();
    }

    function test_RewardClaiming_OwnerCanStillClaimAfterDesignatingNewClaimer() public {
        address ownerAddr = makeAddr("depositOwner3");
        address newClaimer = makeAddr("newClaimer3");

        // Whitelist owner
        address[] memory ownerArr = new address[](1);
        ownerArr[0] = ownerAddr;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(ownerArr);
        earningPowerWhitelist.addToWhitelist(ownerArr);
        vm.stopPrank();

        // Owner stakes and sets newClaimer
        stakeToken.mint(ownerAddr, STAKE_AMOUNT);
        vm.startPrank(ownerAddr);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, ownerAddr);
        regenStaker.alterClaimer(depositId, newClaimer);
        vm.stopPrank(); // Stop owner's prank

        // Admin notifies reward and warp
        vm.startPrank(ADMIN);
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT); // Mint tokens to the staker contract
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Original owner attempts to claim
        vm.startPrank(ownerAddr);
        uint256 claimedByOwner = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqRel(
            claimedByOwner,
            REWARD_AMOUNT,
            MIN_ASSERT_TOLERANCE,
            "Owner should be able to claim full reward after designating another claimer"
        );
    }

    function test_RevertIf_NotifyRewardAmount_NotNotifier() public {
        address notNotifier = makeAddr("notNotifier");

        vm.startPrank(notNotifier);
        vm.expectRevert(
            abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not notifier"), notNotifier)
        );
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
    }

    // --- Tests for Security and Integrity Requirements ---

    function test_RevertIf_NotifyRewardAmount_InsufficientContractBalance() public {
        uint256 notifyAmount = 1000e18;

        // Mint a smaller amount to the contract to ensure balance < notifyAmount
        rewardToken.mint(address(regenStaker), notifyAmount / 2);

        // Verify the contract balance is indeed less than the notify amount
        uint256 contractBalance = rewardToken.balanceOf(address(regenStaker));
        assertLt(contractBalance, notifyAmount, "Contract balance should be less than notify amount");

        vm.startPrank(ADMIN);
        // The Staker__InsufficientRewardBalance error is from the base Staker contract.
        vm.expectRevert(Staker.Staker__InsufficientRewardBalance.selector);
        regenStaker.notifyRewardAmount(notifyAmount);
        vm.stopPrank();
    }

    function test_RevertIf_WithdrawWhenPaused() public {
        address user = makeAddr("withdrawPausedUser");
        // Whitelist and stake
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        vm.stopPrank();
        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        // Pause the contract
        vm.startPrank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused(), "Contract should be paused");
        vm.stopPrank();

        // Attempt to withdraw while paused
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        regenStaker.withdraw(depositId, STAKE_AMOUNT / 2);
        vm.stopPrank();
    }

    function test_RevertIf_ClaimRewardWhenPaused() public {
        address user = makeAddr("claimPausedUser");
        // Whitelist, stake, and accrue rewards
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        vm.stopPrank();
        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2); // Accrue some rewards
        // Pause the contract
        regenStaker.pause();
        assertTrue(regenStaker.paused(), "Contract should be paused");
        vm.stopPrank();

        // Attempt to claim reward while paused
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        regenStaker.claimReward(depositId);
        vm.stopPrank();
    }

    // --- Tests for RegenStaker specific branch coverage ---

    function test_RevertIf_Contribute_GrantRoundAddressZero() public {
        address user = makeAddr("contributorUser");
        address votingDelegatee = makeAddr("votingDelegatee");
        uint256 amountToContribute = 100e18;
        uint256[] memory prefs = new uint256[](1);
        prefs[0] = 1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = amountToContribute;

        // Setup: User stakes and has rewards
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        contributorWhitelist.addToWhitelist(userArr);
        vm.stopPrank();

        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        vm.startPrank(user);
        vm.expectRevert(Staker.Staker__InvalidAddress.selector);
        regenStaker.contribute(depositId, address(0), votingDelegatee, amountToContribute, bytes32(0));
        vm.stopPrank();
    }

    function test_RevertIf_Contribute_AmountExceedsUnclaimed() public {
        address user = makeAddr("amountExceedsUser");
        address mockGrantRound = makeAddr("mockGrantRoundAmountExceeds");
        address votingDelegatee = makeAddr("votingDelegateeAmountExceeds");

        uint256[] memory prefs = new uint256[](1);
        prefs[0] = 1;
        // Amount to contribute will be set higher than available rewards.

        // Setup: User stakes, has rewards, on contributor whitelist
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        contributorWhitelist.addToWhitelist(userArr);
        vm.stopPrank();

        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        // Notify a specific amount of rewards
        uint256 actualRewardAvailable = REWARD_AMOUNT / 2; // Make it less than full REWARD_AMOUNT
        rewardToken.mint(address(regenStaker), actualRewardAvailable);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(actualRewardAvailable);
        vm.stopPrank();
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION); // Accrue all of actualRewardAvailable

        // Action: Attempt to contribute more than available
        uint256 amountToContribute = actualRewardAvailable + 100; // Exceeds available
        uint256[] memory weights = new uint256[](1);
        weights[0] = amountToContribute;

        vm.startPrank(user);
        uint256 unclaimed = regenStaker.unclaimedReward(depositId);
        vm.expectRevert(abi.encodeWithSelector(RegenStaker.CantAfford.selector, amountToContribute, unclaimed));
        regenStaker.contribute(depositId, mockGrantRound, votingDelegatee, amountToContribute, bytes32(0));
        vm.stopPrank();
    }

    function test_RevertIf_Contribute_SignUpFailsOrReturnsZero() public {
        address user = makeAddr("signUpFailsUser");
        address mockGrantRound = makeAddr("mockGrantRoundSignUpFails");
        address votingDelegatee = makeAddr("votingDelegateeSignUpFails");
        uint256 amountToContribute = 100e18;
        uint256[] memory prefs = new uint256[](1);
        prefs[0] = 1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = amountToContribute;

        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        contributorWhitelist.addToWhitelist(userArr);
        vm.stopPrank();
        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Mock signup to return 0 (failure) as originally intended for this test
        vm.mockCall(
            mockGrantRound, // This is mockGrantRoundSignUpFails from this test function
            abi.encodeWithSignature("signup(uint256,address,bytes32)", amountToContribute, votingDelegatee, bytes32(0)),
            abi.encode(uint256(0)) // << REVERTED TO 0
        );

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStaker.GrantRoundSignUpFailed.selector,
                mockGrantRound,
                user,
                amountToContribute,
                votingDelegatee
            )
        );
        regenStaker.contribute(depositId, mockGrantRound, votingDelegatee, amountToContribute, bytes32(0));
        vm.stopPrank();
    }

    function test_Contribute_UpdatesEarningPower() public {
        address user = makeAddr("epChangeUser");
        address mockGrantRound = makeAddr("mockGrantRoundEpChange");
        address votingDelegatee = makeAddr("votingDelegateeEpChange");
        uint256 amountToContribute = 1e18; // A smaller amount, ensure it's less than accrued rewards

        uint256[] memory prefs = new uint256[](1);
        prefs[0] = 1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = amountToContribute;

        // Setup: User stakes. Initially, they ARE on the earningPowerWhitelist.
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr); // Whitelisted for EP initially
        contributorWhitelist.addToWhitelist(userArr);
        vm.stopPrank();

        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        // Verify initial deposit earning power is STAKE_AMOUNT
        // Deposit struct: balance, owner, earningPower, delegatee, claimer, rewardPerTokenCheckpoint, scaledUnclaimedRewardCheckpoint
        (, , uint96 initialDepositEP, , , , ) = regenStaker.deposits(depositId);
        assertEq(initialDepositEP, STAKE_AMOUNT, "Initial deposit EP should be STAKE_AMOUNT");
        assertEq(
            regenStaker.depositorTotalEarningPower(user),
            STAKE_AMOUNT,
            "Initial total EP for user should be STAKE_AMOUNT"
        );

        // Setup rewards and let them accrue
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION / 2); // Accrue for half period to have some rewards

        // User should have some unclaimed rewards now
        uint256 unclaimedBefore = regenStaker.unclaimedReward(depositId);
        assertTrue(unclaimedBefore >= amountToContribute, "User should have enough rewards to contribute");

        vm.prank(ADMIN);
        earningPowerWhitelist.removeFromWhitelist(userArr);
        assertFalse(earningPowerWhitelist.isWhitelisted(user), "User should now be OFF earning power whitelist");

        // Mock external calls for contribute
        vm.mockCall(
            mockGrantRound,
            abi.encodeWithSignature("signup(uint256,address,bytes32)", amountToContribute, votingDelegatee, bytes32(0)),
            abi.encode(uint256(1))
        );
        vm.mockCall(
            mockGrantRound,
            abi.encodeWithSignature("vote(uint256,uint256)", prefs[0], weights[0]),
            abi.encode()
        );

        uint256 expectedNewEP = 0; // Calculator should now return 0 as EP because user is no longer whitelisted

        uint256 globalEpBefore = regenStaker.totalEarningPower();
        // uint256 userTotalEpBefore = regenStaker.depositorTotalEarningPower(user); // Removed this variable

        vm.startPrank(user);
        regenStaker.contribute(depositId, mockGrantRound, votingDelegatee, amountToContribute, bytes32(0));
        vm.stopPrank();

        // Verify deposit's earning power was updated to expectedNewEP (0)
        (, , uint96 finalDepositEP, , , , ) = regenStaker.deposits(depositId);
        assertEq(finalDepositEP, expectedNewEP, "Deposit EP should have been updated to 0 during contribute");

        assertEq(
            regenStaker.depositorTotalEarningPower(user),
            expectedNewEP,
            "Total EP for user should be updated to 0"
        );
        // Global total EP should decrease by the user's previous earning power (which was initialDepositEP, effectively STAKE_AMOUNT for this user)
        assertEq(
            regenStaker.totalEarningPower(),
            globalEpBefore - initialDepositEP,
            "Global total EP should reflect the decrease"
        );
    }

    // --- Tests for newly identified unhit branches ---

    function test_RevertIf_Withdraw_NotOwner() public {
        address owner = makeAddr("ownerWithdrawNotOwner");
        address notOwner = makeAddr("notOwnerWithdrawNotOwner");

        // Whitelist owner for staking and earning power
        address[] memory ownerArr = new address[](1);
        ownerArr[0] = owner;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(ownerArr);
        earningPowerWhitelist.addToWhitelist(ownerArr);
        vm.stopPrank();

        // Owner stakes
        stakeToken.mint(owner, STAKE_AMOUNT);
        vm.startPrank(owner);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, owner);
        vm.stopPrank();

        // NotOwner attempts to withdraw
        vm.startPrank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not owner"), notOwner));
        regenStaker.withdraw(depositId, STAKE_AMOUNT / 2);
        vm.stopPrank();
    }

    function test_RevertIf_Contribute_AmountLessThanFee() public {
        address contributor = makeAddr("contributorLessThanFee");
        address mockGrantRound = makeAddr("mockGrantRoundLessThanFee");
        address feeCollector = makeAddr("feeCollectorLessThanFee");
        address votingDelegatee = contributor;

        // Setup deposit
        stakeToken.mint(contributor, STAKE_AMOUNT);
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        address[] memory contributorArr = new address[](1);
        contributorArr[0] = contributor;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(contributorArr);
        earningPowerWhitelist.addToWhitelist(contributorArr);
        contributorWhitelist.addToWhitelist(contributorArr);
        vm.stopPrank();

        vm.startPrank(contributor);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, contributor);
        vm.stopPrank();

        // Notify rewards and warp
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        uint256 availableRewards = regenStaker.unclaimedReward(depositId);
        assertTrue(availableRewards > 0, "Should have some rewards");

        // Set a fee that is valid and respected by MAX_CLAIM_FEE
        uint256 feeAmount = _min(1e17, regenStaker.MAX_CLAIM_FEE()); // e.g., 0.1 tokens, ensure it's valid
        assertTrue(feeAmount > 0, "Fee amount for test must be positive and valid");

        uint256 amountToContribute = feeAmount - 1; // Try to contribute less than the fee

        assertTrue(
            availableRewards >= amountToContribute,
            "Available rewards should cover attempted gross contribution"
        );

        vm.startPrank(ADMIN);
        Staker.ClaimFeeParameters memory feeParams = Staker.ClaimFeeParameters({
            feeAmount: SafeCast.toUint96(feeAmount),
            feeCollector: feeCollector
        });
        regenStaker.setClaimFeeParameters(feeParams);
        vm.stopPrank();

        uint256[] memory prefs = new uint256[](1);
        prefs[0] = 1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = amountToContribute;

        vm.startPrank(contributor);
        vm.expectRevert(abi.encodeWithSelector(RegenStaker.CantAfford.selector, feeAmount, amountToContribute));
        regenStaker.contribute(depositId, mockGrantRound, votingDelegatee, amountToContribute, bytes32(0));
        vm.stopPrank();
    }

    function test_RevertIf_SetClaimFeeParameters_FeeCollectorZeroAndFeeNonZero() public {
        uint256 validFeeAmount = _min(10e18, regenStaker.MAX_CLAIM_FEE()); // Ensure validFeeAmount respects MAX_CLAIM_FEE
        assertTrue(validFeeAmount > 0, "Test requires a non-zero feeAmount that is valid.");

        vm.startPrank(ADMIN);
        Staker.ClaimFeeParameters memory feeParams = Staker.ClaimFeeParameters({
            feeAmount: SafeCast.toUint96(validFeeAmount),
            feeCollector: address(0) // Zero address for fee collector
        });
        vm.expectRevert(Staker.Staker__InvalidClaimFeeParameters.selector); // Now using the defined error
        regenStaker.setClaimFeeParameters(feeParams);
        vm.stopPrank();
    }

    // Helper to get private key - in a real scenario, use specific private keys
    uint256 constant payerPrivateKey = 0xBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBAD1;
    uint256 constant stakerUserPrivateKey = 0xBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBAD2;

    function test_PermitAndStake_EnforcesStakerWhitelist() public {
        address stakerUser = makeAddr("stakerPermitAndStake");
        uint256 permitAmount = STAKE_AMOUNT;

        // Mint tokens to stakerUser
        stakeToken.mint(stakerUser, permitAmount);

        // Ensure stakerWhitelist is active and stakerUser is NOT on it
        assertTrue(address(regenStaker.stakerWhitelist()) != address(0), "Staker whitelist should be active.");
        assertFalse(
            regenStaker.stakerWhitelist().isWhitelisted(stakerUser),
            "StakerUser should NOT be on staker whitelist."
        );

        // Verify regular stake reverts for non-whitelisted user
        vm.startPrank(stakerUser);
        stakeToken.approve(address(regenStaker), permitAmount);
        vm.expectRevert(
            abi.encodeWithSelector(RegenStaker.NotWhitelisted.selector, regenStaker.stakerWhitelist(), stakerUser)
        );
        regenStaker.stake(permitAmount, stakerUser);
        vm.stopPrank();
    }

    function test_Stake_UsesSurrogateDelegatee() public {
        address stakerAddress = makeAddr("stakerForSurrogate");
        address delegatee = makeAddr("delegateeForSurrogate");

        // Whitelist staker for staking and earning power
        address[] memory stakerArr = new address[](1);
        stakerArr[0] = stakerAddress;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(stakerArr);
        earningPowerWhitelist.addToWhitelist(stakerArr);
        vm.stopPrank();

        // Staker stakes with a delegatee
        stakeToken.mint(stakerAddress, STAKE_AMOUNT);
        vm.startPrank(stakerAddress);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, delegatee);
        vm.stopPrank();

        // Check the actual delegatee of the deposit
        (, , , address actualDelegatee, , , ) = regenStaker.deposits(depositId);
        assertEq(actualDelegatee, delegatee, "Deposit should be delegated to the specified delegatee");

        // Verify that a surrogate contract has been deployed for the delegatee
        address surrogateAddress = address(regenStaker.surrogates(delegatee));
        assertTrue(surrogateAddress != address(0), "Surrogate contract should be deployed");

        // Verify that the stake tokens have been transferred to the surrogate contract
        assertEq(
            stakeToken.balanceOf(surrogateAddress),
            STAKE_AMOUNT,
            "Stake tokens should be transferred to surrogate"
        );

        // Make a second stake with the same delegatee and verify it uses the same surrogate
        stakeToken.mint(stakerAddress, STAKE_AMOUNT);
        vm.startPrank(stakerAddress);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        regenStaker.stake(STAKE_AMOUNT, delegatee); // Remove variable assignment
        vm.stopPrank();

        // Verify same surrogate is used
        address secondSurrogateAddress = address(regenStaker.surrogates(delegatee));
        assertEq(surrogateAddress, secondSurrogateAddress, "Should reuse existing surrogate for same delegatee");
        assertEq(
            stakeToken.balanceOf(surrogateAddress),
            STAKE_AMOUNT * 2,
            "Surrogate should now hold tokens from both stakes"
        );

        // Test with a different delegatee to ensure a new surrogate is created
        address newDelegatee = makeAddr("newDelegatee");
        stakeToken.mint(stakerAddress, STAKE_AMOUNT);
        vm.startPrank(stakerAddress);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        regenStaker.stake(STAKE_AMOUNT, newDelegatee); // Remove variable assignment
        vm.stopPrank();

        // Verify a new surrogate was created for the new delegatee
        address newSurrogateAddress = address(regenStaker.surrogates(newDelegatee));
        assertTrue(newSurrogateAddress != address(0), "New surrogate should be created for new delegatee");
        assertTrue(
            newSurrogateAddress != surrogateAddress,
            "New surrogate should be different from original surrogate"
        );
        assertEq(stakeToken.balanceOf(newSurrogateAddress), STAKE_AMOUNT, "New surrogate should hold staked tokens");
    }

    function test_RevertIf_SetRewardNotifier_NotAdmin() public {
        address newNotifier = makeAddr("newNotifier");
        address notAdmin = makeAddr("notAdminForNotifier");

        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), notAdmin));
        regenStaker.setRewardNotifier(newNotifier, true);
        vm.stopPrank();

        // Verify admin can set it
        vm.startPrank(ADMIN);
        regenStaker.setRewardNotifier(newNotifier, true);
        assertTrue(regenStaker.isRewardNotifier(newNotifier), "Admin should be able to set new notifier");
        vm.stopPrank();
    }

    function test_RevertIf_SetClaimFeeParameters_FeeTooHigh() public {
        address feeCollector = makeAddr("feeCollectorFeeTooHigh");
        uint256 maxFee = regenStaker.MAX_CLAIM_FEE();
        uint256 tooHighFee = maxFee + 1;

        vm.startPrank(ADMIN);
        Staker.ClaimFeeParameters memory feeParams = Staker.ClaimFeeParameters({
            feeAmount: SafeCast.toUint96(tooHighFee),
            feeCollector: feeCollector
        });
        vm.expectRevert(Staker.Staker__InvalidClaimFeeParameters.selector); // Now using the defined error
        regenStaker.setClaimFeeParameters(feeParams);
        vm.stopPrank();
    }

    function test_RevertIf_BumpEarningPower_TipTooHigh() public {
        address tipReceiver = makeAddr("tipReceiverForBumpTip");

        // Create mock address that will attempt bumping with excessive tip
        address bumper = makeAddr("bumper");

        // We don't need to do any whitelist setups or stake operations
        // Just call bumpEarningPower directly with an excessive tip amount

        // Create any arbitrary deposit ID - it doesn't matter for this test
        // since we'll hit the tip validation before any deposit access
        Staker.DepositIdentifier depositId = Staker.DepositIdentifier.wrap(0);

        // Calculate an excessive tip (just over the limit)
        uint256 excessiveTip = regenStaker.maxBumpTip() + 1;

        // This should fail with InvalidTip immediately before any other checks
        vm.startPrank(bumper);
        vm.expectRevert(Staker.Staker__InvalidTip.selector);
        regenStaker.bumpEarningPower(depositId, tipReceiver, excessiveTip);
        vm.stopPrank();
    }

    function test_DepositorTotalStaked_IsAccessible() public {
        address user = makeAddr("user");
        uint256 firstStake = 500e18;
        uint256 secondStake = 300e18;

        // Whitelist user
        address[] memory users = new address[](1);
        users[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(users);
        earningPowerWhitelist.addToWhitelist(users);
        vm.stopPrank();

        // Setup and first stake
        stakeToken.mint(user, firstStake + secondStake);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), firstStake + secondStake);
        regenStaker.stake(firstStake, user);

        // Verify first stake
        assertEq(regenStaker.depositorTotalStaked(user), firstStake);

        // Second stake and verify total
        regenStaker.stake(secondStake, user);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), firstStake + secondStake);
    }

    function testFuzz_Contribute_CorrectNetAmountUsedWithVariableFees(uint96 feeAmount) public {
        // Bound fee amount to be within valid range (0 to MAX_CLAIM_FEE)
        feeAmount = uint96(bound(uint256(feeAmount), 0, regenStaker.MAX_CLAIM_FEE()));

        address user = makeAddr("fuzzFeeUser");
        address mockGrantRound = makeAddr("mockGrantRoundFuzzFee");
        address votingDelegatee = makeAddr("votingDelegateeFuzzFee");
        address feeCollector = makeAddr("feeCollectorFuzzFee");

        // Use a sufficiently large amount to contribute
        uint256 amountToContributeGross = 1_000_000e18;
        uint256 expectedAmountToGrantRoundNet = amountToContributeGross - feeAmount;

        // Set up contribution preferences
        uint256[] memory prefs = new uint256[](1);
        prefs[0] = 1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = expectedAmountToGrantRoundNet; // Weight should equal net amount

        // Setup user & deposit
        address[] memory userArr = new address[](1);
        userArr[0] = user;
        vm.startPrank(ADMIN);
        stakerWhitelist.addToWhitelist(userArr);
        earningPowerWhitelist.addToWhitelist(userArr);
        contributorWhitelist.addToWhitelist(userArr);
        vm.stopPrank();

        stakeToken.mint(user, STAKE_AMOUNT);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(STAKE_AMOUNT, user);
        vm.stopPrank();

        // Setup rewards with ample amount
        rewardToken.mint(address(regenStaker), REWARD_AMOUNT);
        vm.startPrank(ADMIN);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);

        // Set the fee parameters with our fuzzed fee amount
        Staker.ClaimFeeParameters memory feeParams = Staker.ClaimFeeParameters({
            feeAmount: feeAmount,
            feeCollector: feeCollector // Use a real address for any non-zero fee
        });
        regenStaker.setClaimFeeParameters(feeParams);
        vm.stopPrank();

        // Accrue rewards
        vm.warp(block.timestamp + REWARD_PERIOD_DURATION);

        // Record fee collector's initial balance
        uint256 collectorInitialBalance = rewardToken.balanceOf(feeCollector);

        // Mock external calls
        vm.mockCall(
            mockGrantRound,
            abi.encodeWithSignature(
                "signup(uint256,address,bytes32)",
                expectedAmountToGrantRoundNet,
                votingDelegatee,
                bytes32(0)
            ),
            abi.encode(uint256(1))
        );

        // Perform the contribution
        vm.startPrank(user);
        uint256 returnedAmount = regenStaker.contribute(
            depositId,
            mockGrantRound,
            votingDelegatee,
            amountToContributeGross,
            bytes32(0)
        );
        vm.stopPrank();

        // Verify returned amount is the correct net amount
        assertEq(returnedAmount, expectedAmountToGrantRoundNet, "Returned net amount incorrect");

        // Verify fee collector received the correct fee amount
        if (feeAmount > 0) {
            assertEq(
                rewardToken.balanceOf(feeCollector) - collectorInitialBalance,
                feeAmount,
                "Fee collector received incorrect fee amount"
            );
        } else {
            assertEq(
                rewardToken.balanceOf(feeCollector),
                collectorInitialBalance,
                "Fee collector balance should not change for zero fee"
            );
        }
    }

    // Helper function for minimum of two uints
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
