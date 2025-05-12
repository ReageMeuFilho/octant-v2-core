pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { RegenStaker, NotWhitelisted } from "../../src/regen/RegenStaker.sol";
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

    function test_staker_whitelist_is_set() public view {
        assertEq(address(regenStaker.stakerWhitelist()), address(stakerWhitelist));
    }

    function test_contribution_whitelist_is_set() public view {
        assertEq(address(regenStaker.contributionWhitelist()), address(contributorWhitelist));
    }

    function test_earning_power_whitelist_is_set() public view {
        assertEq(
            address(IWhitelistedEarningPowerCalculator(address(regenStaker.earningPowerCalculator())).whitelist()),
            address(earningPowerWhitelist)
        );
    }

    function test_earning_power_calculator_is_set() public view {
        assertEq(address(regenStaker.earningPowerCalculator()), address(calculator));
    }

    function test_staker_whitelist_disabled_allows_non_whitelisted_staking() public {
        // First verify that non-admin cannot set the whitelist
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(); // Should revert with Staker__Unauthorized
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
            abi.encodeWithSelector(NotWhitelisted.selector, regenStaker.stakerWhitelist(), nonWhitelistedUser)
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

    function test_contribution_whitelist_disabled_allows_non_whitelisted_contribution() public {
        // First verify that non-admin cannot set the whitelist
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(); // Should revert with Staker__Unauthorized
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
                NotWhitelisted.selector,
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

    function test_earning_power_whitelist_disabled_allows_non_whitelisted_earning_power() public {
        // First verify that non-admin cannot set the whitelist
        address nonAdmin = makeAddr("nonAdmin");
        vm.startPrank(nonAdmin);
        vm.expectRevert(); // Should revert with OwnableUnauthorizedAccount
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
}
