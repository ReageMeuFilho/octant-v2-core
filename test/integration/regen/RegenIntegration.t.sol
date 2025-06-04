// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Staking } from "lib/staker/src/interfaces/IERC20Staking.sol";
import { IWhitelistedEarningPowerCalculator } from "src/regen/interfaces/IWhitelistedEarningPowerCalculator.sol";
import { Staker } from "lib/staker/src/Staker.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IFundingRound } from "src/regen/interfaces/IFundingRound.sol";

/**
 * @title RegenIntegrationTest
 * @notice Comprehensive integration tests for RegenStaker contract. Due to fixed-point math, higher number of fuzz runs necessary to surface all edge cases.
 * forge-config: default.fuzz.runs = 16384
 */
contract RegenIntegrationTest is Test {
    RegenStaker regenStaker;
    RegenEarningPowerCalculator calculator;
    Whitelist stakerWhitelist;
    Whitelist contributorWhitelist;
    Whitelist earningPowerWhitelist;
    MockERC20 rewardToken;
    MockERC20Staking stakeToken;

    uint256 public constant REWARD_AMOUNT_BASE = 30_000_000;
    uint256 public constant STAKE_AMOUNT_BASE = 1_000;
    uint256 public constant ONE_IN_A_FEMTO = 1e5;
    uint256 public constant ONE_IN_A_PICO = 1e8;
    uint256 public constant ONE_IN_A_NANO = 1e11;
    uint256 public constant ONE_IN_A_MICRO = 1e14;
    uint256 public constant MAX_BUMP_TIP = 1e18;
    uint256 public constant MAX_CLAIM_FEE = 1e18;

    address public immutable ADMIN = makeAddr("admin");
    uint8 public rewardTokenDecimals = 18;
    uint8 public stakeTokenDecimals = 18;

    function getRewardAmount() internal view returns (uint256) {
        return REWARD_AMOUNT_BASE * (10 ** rewardTokenDecimals);
    }

    function getRewardAmount(uint256 baseAmount) internal view returns (uint256) {
        return baseAmount * (10 ** rewardTokenDecimals);
    }

    function getStakeAmount() internal view returns (uint256) {
        return STAKE_AMOUNT_BASE * (10 ** stakeTokenDecimals);
    }

    function getStakeAmount(uint256 baseAmount) internal view returns (uint256) {
        return baseAmount * (10 ** stakeTokenDecimals);
    }

    function whitelistUser(address user, bool forStaking, bool forContributing, bool forEarningPower) internal {
        vm.startPrank(ADMIN);
        if (forStaking) stakerWhitelist.addToWhitelist(user);
        if (forContributing) contributorWhitelist.addToWhitelist(user);
        if (forEarningPower) earningPowerWhitelist.addToWhitelist(user);
        vm.stopPrank();
    }

    function setUp() public virtual {
        rewardTokenDecimals = uint8(bound(vm.randomUint(), 6, 18));
        stakeTokenDecimals = uint8(bound(vm.randomUint(), 6, 18));

        vm.startPrank(ADMIN);

        rewardToken = new MockERC20(rewardTokenDecimals);
        stakeToken = new MockERC20Staking(stakeTokenDecimals);

        stakerWhitelist = new Whitelist();
        contributorWhitelist = new Whitelist();
        earningPowerWhitelist = new Whitelist();

        calculator = new RegenEarningPowerCalculator(ADMIN, earningPowerWhitelist);

        regenStaker = new RegenStaker(
            IERC20(address(rewardToken)),
            IERC20Staking(address(stakeToken)),
            ADMIN,
            stakerWhitelist,
            contributorWhitelist,
            calculator,
            MAX_BUMP_TIP,
            MAX_CLAIM_FEE,
            0
        );

        regenStaker.setRewardNotifier(ADMIN, true);
        vm.stopPrank();
    }

    function testFuzz_Constructor_InitializesAllParametersCorrectly(
        uint256 tipAmount,
        uint256 feeAmount,
        uint256 minimumStakeAmount
    ) public {
        tipAmount = bound(tipAmount, 0, MAX_BUMP_TIP);
        feeAmount = bound(feeAmount, 0, MAX_CLAIM_FEE);
        minimumStakeAmount = bound(minimumStakeAmount, 0, getStakeAmount(1000));

        vm.startPrank(ADMIN);
        RegenStaker localRegenStaker = new RegenStaker(
            IERC20(address(rewardToken)),
            IERC20Staking(address(stakeToken)),
            ADMIN,
            Whitelist(address(0)),
            Whitelist(address(0)),
            calculator,
            tipAmount,
            feeAmount,
            minimumStakeAmount
        );

        assertEq(address(localRegenStaker.REWARD_TOKEN()), address(rewardToken));
        assertEq(address(localRegenStaker.STAKE_TOKEN()), address(stakeToken));
        assertEq(localRegenStaker.admin(), ADMIN);
        assertEq(address(localRegenStaker.earningPowerCalculator()), address(calculator));
        assertEq(localRegenStaker.maxBumpTip(), tipAmount);
        assertEq(localRegenStaker.MAX_CLAIM_FEE(), feeAmount);
        assertEq(localRegenStaker.minimumStakeAmount(), minimumStakeAmount);

        assertTrue(address(localRegenStaker.stakerWhitelist()) != address(0));
        assertTrue(address(localRegenStaker.contributionWhitelist()) != address(0));

        assertEq(Ownable(address(localRegenStaker.stakerWhitelist())).owner(), address(ADMIN));
        assertEq(Ownable(address(localRegenStaker.contributionWhitelist())).owner(), address(ADMIN));

        (uint96 initialFeeAmount, address initialFeeCollector) = localRegenStaker.claimFeeParameters();
        assertEq(initialFeeAmount, 0);
        assertEq(initialFeeCollector, address(0));

        assertEq(localRegenStaker.totalStaked(), 0);
        assertEq(localRegenStaker.totalEarningPower(), 0);
        assertEq(localRegenStaker.REWARD_DURATION(), 30 days);
        vm.stopPrank();
    }

    function testFuzz_Constructor_InitializesAllParametersWithProvidedWhitelists(
        uint256 tipAmount,
        uint256 feeAmount,
        uint256 minimumStakeAmount
    ) public {
        tipAmount = bound(tipAmount, 0, MAX_BUMP_TIP);
        feeAmount = bound(feeAmount, 0, MAX_CLAIM_FEE);
        minimumStakeAmount = bound(minimumStakeAmount, 0, getStakeAmount(1000));

        vm.startPrank(ADMIN);
        Whitelist providedStakerWhitelist = new Whitelist();
        Whitelist providedContributorWhitelist = new Whitelist();

        providedStakerWhitelist.transferOwnership(ADMIN);
        providedContributorWhitelist.transferOwnership(ADMIN);

        RegenStaker localRegenStaker = new RegenStaker(
            IERC20(address(rewardToken)),
            IERC20Staking(address(stakeToken)),
            ADMIN,
            providedStakerWhitelist,
            providedContributorWhitelist,
            calculator,
            tipAmount,
            feeAmount,
            minimumStakeAmount
        );

        assertEq(address(localRegenStaker.REWARD_TOKEN()), address(rewardToken));
        assertEq(address(localRegenStaker.STAKE_TOKEN()), address(stakeToken));
        assertEq(localRegenStaker.admin(), ADMIN);
        assertEq(address(localRegenStaker.earningPowerCalculator()), address(calculator));
        assertEq(localRegenStaker.maxBumpTip(), tipAmount);
        assertEq(localRegenStaker.MAX_CLAIM_FEE(), feeAmount);
        assertEq(localRegenStaker.minimumStakeAmount(), minimumStakeAmount);

        assertEq(address(localRegenStaker.stakerWhitelist()), address(providedStakerWhitelist));
        assertEq(address(localRegenStaker.contributionWhitelist()), address(providedContributorWhitelist));

        assertEq(Ownable(address(localRegenStaker.stakerWhitelist())).owner(), ADMIN);
        assertEq(Ownable(address(localRegenStaker.contributionWhitelist())).owner(), ADMIN);

        (uint96 initialFeeAmount, address initialFeeCollector) = localRegenStaker.claimFeeParameters();
        assertEq(initialFeeAmount, 0);
        assertEq(initialFeeCollector, address(0));

        assertEq(localRegenStaker.totalStaked(), 0);
        assertEq(localRegenStaker.totalEarningPower(), 0);
        assertEq(localRegenStaker.REWARD_DURATION(), 30 days);
        vm.stopPrank();
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

    function testFuzz_SetMinimumStakeAmount(uint256 newMinimum) public {
        newMinimum = bound(newMinimum, 0, getStakeAmount(10000));

        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(newMinimum);

        assertEq(regenStaker.minimumStakeAmount(), newMinimum);
    }

    function testFuzz_RevertIf_NonAdminCannotSetMinimumStakeAmount(address nonAdmin, uint256 newMinimum) public {
        vm.assume(nonAdmin != ADMIN);
        newMinimum = bound(newMinimum, 0, getStakeAmount(10000));

        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.setMinimumStakeAmount(newMinimum);
        vm.stopPrank();
    }

    function testFuzz_RevertIf_StakeBelowMinimum(uint256 minimumAmount, uint256 stakeAmount) public {
        minimumAmount = bound(minimumAmount, getStakeAmount(1), getStakeAmount(1000));
        stakeAmount = bound(stakeAmount, 1, minimumAmount - 1);

        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(minimumAmount);

        address user = makeAddr("user");
        whitelistUser(user, true, false, true);

        stakeToken.mint(user, stakeAmount);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), stakeAmount);
        vm.expectRevert(
            abi.encodeWithSelector(RegenStaker.MinimumStakeAmountNotMet.selector, minimumAmount, stakeAmount)
        );
        regenStaker.stake(stakeAmount, user, user);
        vm.stopPrank();
    }

    function testFuzz_StakeAtOrAboveMinimumSucceeds(uint256 minimumAmountBase, uint256 additionalAmountBase) public {
        minimumAmountBase = bound(minimumAmountBase, 1, 100);
        additionalAmountBase = bound(additionalAmountBase, 0, 100);

        uint256 minimumAmount = getStakeAmount(minimumAmountBase);
        uint256 additionalAmount = getStakeAmount(additionalAmountBase);
        uint256 stakeAmount = minimumAmount + additionalAmount;

        vm.assume(stakeAmount >= minimumAmount);

        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(minimumAmount);

        address user = makeAddr("user");
        whitelistUser(user, true, false, true);

        stakeToken.mint(user, stakeAmount);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, user, user);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), stakeAmount);
        (uint96 depositBalance, , , , , , ) = regenStaker.deposits(depositId);
        assertEq(uint256(depositBalance), stakeAmount);
    }

    function testFuzz_RevertIf_StakeMoreResultsBelowMinimum(
        uint256 minimumAmountBase,
        uint256 withdrawPercent,
        uint256 additionalAmountBase
    ) public {
        minimumAmountBase = bound(minimumAmountBase, 10, 50);
        withdrawPercent = bound(withdrawPercent, 30, 70);
        additionalAmountBase = bound(additionalAmountBase, 1, minimumAmountBase - 1);

        uint256 minimumAmount = getStakeAmount(minimumAmountBase);
        uint256 initialStake = minimumAmount + getStakeAmount(10);
        uint256 withdrawAmount = (initialStake * withdrawPercent) / 100;
        uint256 additionalStake = getStakeAmount(additionalAmountBase);

        uint256 remainingAfterWithdraw = initialStake - withdrawAmount;
        vm.assume(remainingAfterWithdraw < minimumAmount);
        vm.assume(remainingAfterWithdraw + additionalStake < minimumAmount);

        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(minimumAmount);

        address user = makeAddr("user");
        whitelistUser(user, true, false, true);

        stakeToken.mint(user, initialStake + additionalStake);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), initialStake + additionalStake);
        Staker.DepositIdentifier depositId = regenStaker.stake(initialStake, user, user);

        regenStaker.withdraw(depositId, withdrawAmount);

        uint256 expectedFinalBalance = remainingAfterWithdraw + additionalStake;
        vm.expectRevert(
            abi.encodeWithSelector(RegenStaker.MinimumStakeAmountNotMet.selector, minimumAmount, expectedFinalBalance)
        );
        regenStaker.stakeMore(depositId, additionalStake);
        vm.stopPrank();
    }

    function testFuzz_RevertIf_NonAdminCannotSetStakerWhitelist(address nonAdmin) public {
        vm.assume(nonAdmin != ADMIN);
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.setStakerWhitelist(Whitelist(address(0)));
        vm.stopPrank();
    }

    function testFuzz_StakerWhitelist_DisableAllowsStaking(uint256 stakeAmountBase) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        uint256 partialStakeAmount = stakeAmount / 2;

        address user = makeAddr("nonWhitelistedUser");
        stakeToken.mint(user, stakeAmount);

        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), stakeAmount);

        vm.expectRevert(
            abi.encodeWithSelector(RegenStaker.NotWhitelisted.selector, regenStaker.stakerWhitelist(), user)
        );
        regenStaker.stake(partialStakeAmount, user);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.setStakerWhitelist(Whitelist(address(0)));
        assertEq(address(regenStaker.stakerWhitelist()), address(0));

        vm.startPrank(user);
        regenStaker.stake(partialStakeAmount, user);
        vm.stopPrank();
    }

    function testFuzz_ContributionWhitelist_DisableAllowsContribution(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase,
        uint256 contributionAmountBase
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);
        contributionAmountBase = bound(contributionAmountBase, 0, 1_000);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        uint256 contributionAmount = getRewardAmount(contributionAmountBase);

        address contributor = makeAddr("contributor");
        address mockFundingRound = makeAddr("mockFundingRound");

        whitelistUser(contributor, true, false, true);

        stakeToken.mint(contributor, stakeAmount);
        rewardToken.mint(address(regenStaker), rewardAmount);

        vm.startPrank(contributor);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, contributor);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);
        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        if (contributionAmount > 0) {
            (uint96 feeAmount, ) = regenStaker.claimFeeParameters();
            vm.assume(contributionAmount >= uint256(feeAmount));
            uint256 netContribution = contributionAmount - uint256(feeAmount);

            vm.mockCall(
                mockFundingRound,
                abi.encodeWithSignature("signup(uint256,address,bytes32)", netContribution, contributor, bytes32(0)),
                abi.encode(uint256(1))
            );
            vm.mockCall(
                mockFundingRound,
                abi.encodeWithSignature("vote(uint256,uint256)", uint256(1), contributionAmount),
                abi.encode()
            );

            assertTrue(address(regenStaker.contributionWhitelist()) != address(0));
            assertFalse(regenStaker.contributionWhitelist().isWhitelisted(contributor));

            vm.startPrank(contributor);
            vm.expectRevert(
                abi.encodeWithSelector(
                    RegenStaker.NotWhitelisted.selector,
                    regenStaker.contributionWhitelist(),
                    contributor
                )
            );
            regenStaker.contribute(depositId, mockFundingRound, contributor, contributionAmount, bytes32(0));
            vm.stopPrank();
        }

        vm.prank(ADMIN);
        regenStaker.setContributionWhitelist(Whitelist(address(0)));
        assertEq(address(regenStaker.contributionWhitelist()), address(0));

        uint256 unclaimedRewards = regenStaker.unclaimedReward(depositId);
        (uint96 feeUint96, ) = regenStaker.claimFeeParameters();
        uint256 fee = uint256(feeUint96);

        if (contributionAmount == 0) {
            if (fee > 0) {
                vm.expectRevert(abi.encodeWithSelector(RegenStaker.CantAfford.selector, fee, contributionAmount));
                vm.prank(contributor);
                regenStaker.contribute(depositId, mockFundingRound, contributor, contributionAmount, bytes32(0));
            } else {
                vm.mockCall(
                    mockFundingRound,
                    abi.encodeWithSignature("signup(uint256,address,bytes32)", 0, contributor, bytes32(0)),
                    abi.encode(uint256(1))
                );
                vm.mockCall(
                    mockFundingRound,
                    abi.encodeWithSignature("vote(uint256,uint256)", uint256(1), uint256(0)),
                    abi.encode()
                );
                vm.prank(contributor);
                regenStaker.contribute(depositId, mockFundingRound, contributor, contributionAmount, bytes32(0));
            }
        } else {
            vm.assume(contributionAmount <= unclaimedRewards);
            vm.assume(contributionAmount >= fee);

            uint256 netContribution = contributionAmount - fee;

            vm.mockCall(
                mockFundingRound,
                abi.encodeWithSignature("signup(uint256,address,bytes32)", netContribution, contributor, bytes32(0)),
                abi.encode(uint256(1))
            );
            vm.mockCall(
                mockFundingRound,
                abi.encodeWithSignature("vote(uint256,uint256)", uint256(1), netContribution),
                abi.encode()
            );
            vm.prank(contributor);
            regenStaker.contribute(depositId, mockFundingRound, contributor, contributionAmount, bytes32(0));
        }
    }

    function testFuzz_EarningPowerWhitelist_DisableGrantsEarningPower(uint256 stakeAmountBase) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        uint256 stakeAmount = getStakeAmount(stakeAmountBase);

        address whitelistedUser = makeAddr("whitelistedUser");
        address nonWhitelistedUser = makeAddr("nonWhitelistedUser");

        stakeToken.mint(whitelistedUser, stakeAmount);
        stakeToken.mint(nonWhitelistedUser, stakeAmount);

        whitelistUser(whitelistedUser, true, false, true);
        whitelistUser(nonWhitelistedUser, true, false, false);

        vm.startPrank(whitelistedUser);
        stakeToken.approve(address(regenStaker), stakeAmount);
        regenStaker.stake(stakeAmount, whitelistedUser);
        vm.stopPrank();

        vm.startPrank(nonWhitelistedUser);
        stakeToken.approve(address(regenStaker), stakeAmount);
        regenStaker.stake(stakeAmount, nonWhitelistedUser);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalEarningPower(whitelistedUser), stakeAmount);
        assertEq(regenStaker.depositorTotalEarningPower(nonWhitelistedUser), 0);

        vm.prank(ADMIN);
        IWhitelistedEarningPowerCalculator(address(calculator)).setWhitelist(Whitelist(address(0)));

        assertEq(
            address(IWhitelistedEarningPowerCalculator(address(regenStaker.earningPowerCalculator())).whitelist()),
            address(0)
        );

        assertEq(regenStaker.depositorTotalEarningPower(nonWhitelistedUser), 0);

        Staker.DepositIdentifier depositId = Staker.DepositIdentifier.wrap(1);

        vm.prank(ADMIN);
        regenStaker.bumpEarningPower(depositId, ADMIN, 0);

        assertEq(regenStaker.depositorTotalEarningPower(nonWhitelistedUser), stakeAmount);

        address newUser = makeAddr("newUser");
        stakeToken.mint(newUser, stakeAmount);

        whitelistUser(newUser, true, false, false);

        vm.startPrank(newUser);
        stakeToken.approve(address(regenStaker), stakeAmount);
        regenStaker.stake(stakeAmount, newUser);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalEarningPower(newUser), stakeAmount);
    }

    function testFuzz_RevertIf_PauseCalledByNonAdmin(address nonAdmin) public {
        vm.assume(nonAdmin != ADMIN);

        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), nonAdmin));
        regenStaker.pause();
        vm.stopPrank();

        vm.startPrank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused());
        regenStaker.unpause();
        vm.stopPrank();
    }

    function testFuzz_RevertIf_StakeWhenPaused(uint256 stakeAmountBase) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        uint256 stakeAmount = getStakeAmount(stakeAmountBase);

        address user = makeAddr("user");
        whitelistUser(user, true, false, false);

        stakeToken.mint(user, stakeAmount);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), stakeAmount);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused());

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        regenStaker.stake(stakeAmount / 2, user);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.unpause();
        assertFalse(regenStaker.paused());
    }

    function testFuzz_RevertIf_ContributeWhenPaused(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase,
        uint256 contributionAmountBase
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);
        uint256 minContributionAmount = 1;
        uint256 maxContributionAmount = 1_000;
        contributionAmountBase = bound(contributionAmountBase, minContributionAmount, maxContributionAmount);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        uint256 contributionAmount = getRewardAmount(contributionAmountBase);

        address mockFundingRound = makeAddr("mockFundingRound");
        address contributor = makeAddr("contributor");

        vm.mockCall(
            mockFundingRound,
            abi.encodeWithSignature("signup(uint256,address,bytes32)", contributionAmount, address(this), bytes32(0)),
            abi.encode(uint256(1))
        );
        vm.mockCall(
            mockFundingRound,
            abi.encodeWithSignature("vote(uint256,uint256)", uint256(1), contributionAmount),
            abi.encode()
        );

        whitelistUser(contributor, true, true, true);

        stakeToken.mint(contributor, stakeAmount);
        rewardToken.mint(address(regenStaker), rewardAmount);

        vm.startPrank(contributor);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, contributor);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);
        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.prank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused());

        vm.startPrank(contributor);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        regenStaker.contribute(depositId, mockFundingRound, contributor, contributionAmount, bytes32(0));
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.unpause();
        assertFalse(regenStaker.paused());
    }

    function testFuzz_ContinuousReward_SingleStaker_FullPeriod(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 100_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 1_000_000);

        address staker = makeAddr("staker");
        whitelistUser(staker, true, false, true);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        uint256 rewardAmount = getRewardAmount(rewardAmountBase);

        stakeToken.mint(staker, stakeAmount);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, staker);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.startPrank(staker);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqRel(claimedAmount, rewardAmount, ONE_IN_A_NANO);
    }

    function testFuzz_ContinuousReward_SingleStaker_JoinsLate(uint256 joinTimePercent) public {
        uint256 minJoinTime = 1;
        uint256 maxJoinTime = 99;
        joinTimePercent = bound(joinTimePercent, minJoinTime, maxJoinTime);

        address staker = makeAddr("staker");
        whitelistUser(staker, true, false, true);

        uint256 totalRewardAmount = getRewardAmount();
        rewardToken.mint(address(regenStaker), totalRewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(totalRewardAmount);

        uint256 joinTime = (regenStaker.REWARD_DURATION() * joinTimePercent) / 100;
        vm.warp(block.timestamp + joinTime);

        uint256 stakeAmount = getStakeAmount();
        stakeToken.mint(staker, stakeAmount);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, staker);
        vm.stopPrank();

        uint256 remainingTime = regenStaker.REWARD_DURATION() - joinTime;
        vm.warp(block.timestamp + remainingTime);

        vm.startPrank(staker);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        uint256 timeStakedPercent = 100 - joinTimePercent;
        uint256 expectedReward = (totalRewardAmount * timeStakedPercent) / 100;

        assertApproxEqRel(claimedAmount, expectedReward, ONE_IN_A_PICO);
    }

    function testFuzz_ContinuousReward_SingleStaker_ClaimsMidPeriod(uint256 firstClaimTimePercent) public {
        uint256 minClaimTime = 10;
        uint256 maxClaimTime = 90;
        firstClaimTimePercent = bound(firstClaimTimePercent, minClaimTime, maxClaimTime);

        address staker = makeAddr("staker");
        whitelistUser(staker, true, false, true);

        uint256 stakeAmount = getStakeAmount();
        uint256 totalRewardAmount = getRewardAmount();

        stakeToken.mint(staker, stakeAmount);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, staker);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), totalRewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(totalRewardAmount);

        uint256 firstClaimTime = (regenStaker.REWARD_DURATION() * firstClaimTimePercent) / 100;
        vm.warp(block.timestamp + firstClaimTime);

        vm.startPrank(staker);
        uint256 claimedAmount1 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        uint256 expectedFirst = (totalRewardAmount * firstClaimTimePercent) / 100;
        assertApproxEqRel(claimedAmount1, expectedFirst, ONE_IN_A_FEMTO);

        uint256 remainingTime = regenStaker.REWARD_DURATION() - firstClaimTime;
        vm.warp(block.timestamp + remainingTime);

        vm.startPrank(staker);
        uint256 claimedAmount2 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        uint256 remainingTimePercent = 100 - firstClaimTimePercent;
        uint256 expectedSecond = (totalRewardAmount * remainingTimePercent) / 100;

        assertApproxEqRel(claimedAmount2, expectedSecond, ONE_IN_A_FEMTO);
        assertApproxEqRel(claimedAmount1 + claimedAmount2, totalRewardAmount, ONE_IN_A_FEMTO);
    }

    function testFuzz_ContinuousReward_TwoStakers_StaggeredEntry_ProRataShare(uint256 stakerBJoinTimePercent) public {
        uint256 minJoinTime = 5;
        uint256 maxJoinTime = 95;
        stakerBJoinTimePercent = bound(stakerBJoinTimePercent, minJoinTime, maxJoinTime);

        address stakerA = makeAddr("stakerA");
        address stakerB = makeAddr("stakerB");

        whitelistUser(stakerA, true, false, true);
        whitelistUser(stakerB, true, false, true);

        uint256 stakeAmount = getStakeAmount();
        uint256 totalRewardAmount = getRewardAmount();

        stakeToken.mint(stakerA, stakeAmount);
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositIdA = regenStaker.stake(stakeAmount, stakerA);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), totalRewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(totalRewardAmount);

        uint256 stakerBJoinTime = (regenStaker.REWARD_DURATION() * stakerBJoinTimePercent) / 100;
        vm.warp(block.timestamp + stakerBJoinTime);

        stakeToken.mint(stakerB, stakeAmount);
        vm.startPrank(stakerB);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositIdB = regenStaker.stake(stakeAmount, stakerB);
        vm.stopPrank();

        uint256 remainingTime = regenStaker.REWARD_DURATION() - stakerBJoinTime;
        vm.warp(block.timestamp + remainingTime);

        vm.startPrank(stakerA);
        uint256 claimedA = regenStaker.claimReward(depositIdA);
        vm.stopPrank();

        vm.startPrank(stakerB);
        uint256 claimedB = regenStaker.claimReward(depositIdB);
        vm.stopPrank();

        uint256 soloPhaseRewards = (totalRewardAmount * stakerBJoinTimePercent) / 100;
        uint256 sharedPhasePercent = 100 - stakerBJoinTimePercent;
        uint256 sharedPhaseRewards = (totalRewardAmount * sharedPhasePercent) / 100;

        uint256 expectedA = soloPhaseRewards + (sharedPhaseRewards / 2);
        uint256 expectedB = sharedPhaseRewards / 2;

        assertApproxEqRel(claimedA, expectedA, ONE_IN_A_PICO);
        assertApproxEqRel(claimedB, expectedB, ONE_IN_A_PICO);
        assertApproxEqRel(claimedA + claimedB, totalRewardAmount, ONE_IN_A_PICO);
    }

    function testFuzz_ContinuousReward_TwoStakers_DifferentAmounts_ProRataShare(
        uint256 stakerARatio,
        uint256 stakerBRatio
    ) public {
        uint256 minRatio = 1;
        uint256 maxRatio = 10;
        stakerARatio = bound(stakerARatio, minRatio, maxRatio);
        stakerBRatio = bound(stakerBRatio, minRatio, maxRatio);

        address stakerA = makeAddr("stakerA");
        address stakerB = makeAddr("stakerB");

        whitelistUser(stakerA, true, false, true);
        whitelistUser(stakerB, true, false, true);

        uint256 baseStakeAmount = getStakeAmount();
        uint256 ratioScaleFactor = 5;
        uint256 stakeAmountA = (baseStakeAmount * stakerARatio) / ratioScaleFactor;
        uint256 stakeAmountB = (baseStakeAmount * stakerBRatio) / ratioScaleFactor;

        stakeToken.mint(stakerA, stakeAmountA);
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), stakeAmountA);
        Staker.DepositIdentifier depositIdA = regenStaker.stake(stakeAmountA, stakerA);
        vm.stopPrank();

        stakeToken.mint(stakerB, stakeAmountB);
        vm.startPrank(stakerB);
        stakeToken.approve(address(regenStaker), stakeAmountB);
        Staker.DepositIdentifier depositIdB = regenStaker.stake(stakeAmountB, stakerB);
        vm.stopPrank();

        uint256 totalRewardAmount = getRewardAmount();
        rewardToken.mint(address(regenStaker), totalRewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(totalRewardAmount);

        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.startPrank(stakerA);
        uint256 claimedA = regenStaker.claimReward(depositIdA);
        vm.stopPrank();

        vm.startPrank(stakerB);
        uint256 claimedB = regenStaker.claimReward(depositIdB);
        vm.stopPrank();

        uint256 totalStake = stakeAmountA + stakeAmountB;
        uint256 expectedA = (totalRewardAmount * stakeAmountA) / totalStake;
        uint256 expectedB = (totalRewardAmount * stakeAmountB) / totalStake;

        assertApproxEqRel(claimedA, expectedA, ONE_IN_A_FEMTO);
        assertApproxEqRel(claimedB, expectedB, ONE_IN_A_FEMTO);
        assertApproxEqRel(claimedA + claimedB, totalRewardAmount, ONE_IN_A_FEMTO);
    }

    function testFuzz_TimeWeightedReward_NoEarningIfNotOnEarningWhitelist(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);

        address staker = makeAddr("staker");
        whitelistUser(staker, true, false, false);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        uint256 rewardAmount = getRewardAmount(rewardAmountBase);

        stakeToken.mint(staker, stakeAmount);
        vm.startPrank(staker);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, staker);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.startPrank(staker);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertEq(claimedAmount, 0);
    }

    function testFuzz_TimeWeightedReward_EarningStopsIfRemovedFromEarningWhitelistMidPeriod(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);

        address whitelistedStaker = makeAddr("whitelistedStaker");
        address nonWhitelistedStaker = makeAddr("nonWhitelistedStaker");

        whitelistUser(whitelistedStaker, true, false, true);
        whitelistUser(nonWhitelistedStaker, true, false, false);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        stakeToken.mint(whitelistedStaker, stakeAmount);
        stakeToken.mint(nonWhitelistedStaker, stakeAmount);

        vm.startPrank(whitelistedStaker);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier whitelistedDepositId = regenStaker.stake(stakeAmount, whitelistedStaker);
        vm.stopPrank();

        vm.startPrank(nonWhitelistedStaker);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier nonWhitelistedDepositId = regenStaker.stake(stakeAmount, nonWhitelistedStaker);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalEarningPower(whitelistedStaker), stakeAmount);
        assertEq(regenStaker.depositorTotalEarningPower(nonWhitelistedStaker), 0);

        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.startPrank(whitelistedStaker);
        uint256 claimedByWhitelisted = regenStaker.claimReward(whitelistedDepositId);
        vm.stopPrank();

        vm.startPrank(nonWhitelistedStaker);
        uint256 claimedByNonWhitelisted = regenStaker.claimReward(nonWhitelistedDepositId);
        vm.stopPrank();

        assertApproxEqRel(claimedByWhitelisted, rewardAmount, ONE_IN_A_NANO);
        assertEq(claimedByNonWhitelisted, 0);
    }

    function testFuzz_TimeWeightedReward_RateResetsWithNewRewardNotification(
        uint256 rewardPart1Base,
        uint256 rewardPart2Base,
        uint256 stakeAmountBase,
        uint256 stakerBJoinTimePercent
    ) public {
        rewardPart1Base = bound(rewardPart1Base, 1, 50_000);
        rewardPart2Base = bound(rewardPart2Base, 1, 50_000);
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        uint256 minJoinTime = 10;
        uint256 maxJoinTime = 90;
        stakerBJoinTimePercent = bound(stakerBJoinTimePercent, minJoinTime, maxJoinTime);

        address stakerA = makeAddr("stakerA");
        address stakerB = makeAddr("stakerB");

        whitelistUser(stakerA, true, false, true);
        whitelistUser(stakerB, true, false, true);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);

        stakeToken.mint(stakerA, stakeAmount);
        vm.startPrank(stakerA);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositIdA = regenStaker.stake(stakeAmount, stakerA);
        vm.stopPrank();

        uint256 rewardPart1 = getRewardAmount(rewardPart1Base);
        uint256 rewardPart2 = getRewardAmount(rewardPart2Base);
        uint256 totalRewardAmount = rewardPart1 + rewardPart2;

        rewardToken.mint(address(regenStaker), totalRewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardPart1);

        uint256 stakerBJoinTime = (regenStaker.REWARD_DURATION() * stakerBJoinTimePercent) / 100;
        vm.warp(block.timestamp + stakerBJoinTime);

        stakeToken.mint(stakerB, stakeAmount);
        vm.startPrank(stakerB);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositIdB = regenStaker.stake(stakeAmount, stakerB);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardPart2);

        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.startPrank(stakerA);
        uint256 claimedA = regenStaker.claimReward(depositIdA);
        vm.stopPrank();

        vm.startPrank(stakerB);
        uint256 claimedB = regenStaker.claimReward(depositIdB);
        vm.stopPrank();

        uint256 stakerASoloEarnings = (rewardPart1 * stakerBJoinTimePercent) / 100;
        uint256 remainingPart1 = rewardPart1 - stakerASoloEarnings;
        uint256 totalNewPeriodRewards = remainingPart1 + rewardPart2;
        uint256 eachStakerNewPeriodEarnings = totalNewPeriodRewards / 2;

        uint256 expectedA = stakerASoloEarnings + eachStakerNewPeriodEarnings;
        uint256 expectedB = eachStakerNewPeriodEarnings;

        assertApproxEqRel(claimedA, expectedA, ONE_IN_A_NANO);
        assertApproxEqRel(claimedB, expectedB, ONE_IN_A_NANO);
        assertApproxEqRel(claimedA + claimedB, totalRewardAmount, ONE_IN_A_NANO);
    }

    function testFuzz_StakeDeposit_StakeMore_UpdatesBalanceAndRewards(
        uint256 initialStakeRatio,
        uint256 additionalStakeRatio,
        uint256 timingPercent
    ) public {
        initialStakeRatio = bound(initialStakeRatio, 1, 10);
        additionalStakeRatio = bound(additionalStakeRatio, 1, 10);
        timingPercent = bound(timingPercent, 10, 90);

        address user = makeAddr("user");
        whitelistUser(user, true, false, true);

        uint256 baseAmount = getStakeAmount();
        uint256 initialStake = (baseAmount * initialStakeRatio) / 10;
        uint256 additionalStake = (baseAmount * additionalStakeRatio) / 10;

        stakeToken.mint(user, initialStake + additionalStake);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), initialStake + additionalStake);
        Staker.DepositIdentifier depositId = regenStaker.stake(initialStake, user);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), initialStake);
        assertEq(regenStaker.depositorTotalEarningPower(user), initialStake);

        address otherStaker = makeAddr("otherStaker");
        whitelistUser(otherStaker, true, false, true);
        stakeToken.mint(otherStaker, getStakeAmount());
        vm.startPrank(otherStaker);
        stakeToken.approve(address(regenStaker), getStakeAmount());
        regenStaker.stake(getStakeAmount(), otherStaker);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), getRewardAmount());
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(getRewardAmount());

        vm.warp(block.timestamp + (regenStaker.REWARD_DURATION() * timingPercent) / 100);

        vm.startPrank(user);
        regenStaker.stakeMore(depositId, additionalStake);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), initialStake + additionalStake);
        assertEq(regenStaker.depositorTotalEarningPower(user), initialStake + additionalStake);

        vm.warp(
            block.timestamp + regenStaker.REWARD_DURATION() - (regenStaker.REWARD_DURATION() * timingPercent) / 100
        );

        vm.startPrank(user);
        uint256 claimedAmount = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertGt(claimedAmount, 0);
        assertLe(claimedAmount, getRewardAmount());
    }

    function testFuzz_StakeDeposit_MultipleDepositsSingleUser(
        uint256 stakeAmountBase1,
        uint256 stakeAmountBase2,
        uint256 rewardAmountBase
    ) public {
        stakeAmountBase1 = bound(stakeAmountBase1, 1, 10_000);
        stakeAmountBase2 = bound(stakeAmountBase2, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);

        address user = makeAddr("user");
        whitelistUser(user, true, false, true);

        uint256 stakeAmount1 = getStakeAmount(stakeAmountBase1);
        uint256 stakeAmount2 = getStakeAmount(stakeAmountBase2);
        uint256 totalStakeAmount = stakeAmount1 + stakeAmount2;

        stakeToken.mint(user, totalStakeAmount);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), totalStakeAmount);

        Staker.DepositIdentifier depositId1 = regenStaker.stake(stakeAmount1, user);
        Staker.DepositIdentifier depositId2 = regenStaker.stake(stakeAmount2, user);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), totalStakeAmount);
        assertEq(regenStaker.depositorTotalEarningPower(user), totalStakeAmount);

        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.startPrank(user);
        uint256 claimed1 = regenStaker.claimReward(depositId1);
        uint256 claimed2 = regenStaker.claimReward(depositId2);
        vm.stopPrank();

        uint256 expected1 = (rewardAmount * stakeAmount1) / totalStakeAmount;
        uint256 expected2 = (rewardAmount * stakeAmount2) / totalStakeAmount;

        assertApproxEqRel(claimed1, expected1, ONE_IN_A_NANO);
        assertApproxEqRel(claimed2, expected2, ONE_IN_A_NANO);
        assertApproxEqRel(claimed1 + claimed2, rewardAmount, ONE_IN_A_NANO);
    }

    function testFuzz_StakeWithdraw_PartialWithdraw_ReducesBalanceAndImpactsRewards(
        uint256 stakeAmountBase,
        uint256 withdrawRatio,
        uint256 otherStakeRatio,
        uint256 rewardAmountBase
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 100, 10_000);
        withdrawRatio = bound(withdrawRatio, 1, 75);
        otherStakeRatio = bound(otherStakeRatio, 10, 200);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);

        address user = makeAddr("user");
        address otherStaker = makeAddr("otherStaker");

        whitelistUser(user, true, false, true);
        whitelistUser(otherStaker, true, false, true);

        uint256 userStakeAmount = getStakeAmount(stakeAmountBase);
        stakeToken.mint(user, userStakeAmount);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), userStakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(userStakeAmount, user);
        vm.stopPrank();

        uint256 otherStakerAmount = (userStakeAmount * otherStakeRatio) / 100;
        stakeToken.mint(otherStaker, otherStakerAmount);
        vm.startPrank(otherStaker);
        stakeToken.approve(address(regenStaker), otherStakerAmount);
        Staker.DepositIdentifier otherDepositId = regenStaker.stake(otherStakerAmount, otherStaker);
        vm.stopPrank();

        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + regenStaker.REWARD_DURATION() / 2);

        uint256 withdrawAmount = (userStakeAmount * withdrawRatio) / 100;
        vm.startPrank(user);
        regenStaker.withdraw(depositId, withdrawAmount);
        vm.stopPrank();

        uint256 remainingUserStake = userStakeAmount - withdrawAmount;
        assertEq(regenStaker.depositorTotalStaked(user), remainingUserStake);
        assertEq(regenStaker.depositorTotalEarningPower(user), remainingUserStake);

        vm.warp(block.timestamp + regenStaker.REWARD_DURATION() / 2);

        vm.startPrank(user);
        uint256 claimedAfterWithdraw = regenStaker.claimReward(depositId);
        vm.stopPrank();

        vm.startPrank(otherStaker);
        uint256 claimedByOtherStaker = regenStaker.claimReward(otherDepositId);
        vm.stopPrank();

        assertApproxEqRel(claimedAfterWithdraw + claimedByOtherStaker, rewardAmount, ONE_IN_A_NANO);
        assertGt(claimedAfterWithdraw, 0);
        assertGt(claimedByOtherStaker, 0);
    }

    function testFuzz_StakeWithdraw_FullWithdraw_BalanceZero_ClaimsAccrued_NoFutureRewards(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase,
        uint256 withdrawTimePercent
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);
        uint256 minWithdrawTime = 10;
        uint256 maxWithdrawTime = 90;
        withdrawTimePercent = bound(withdrawTimePercent, minWithdrawTime, maxWithdrawTime);

        address user = makeAddr("user");
        whitelistUser(user, true, false, true);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        stakeToken.mint(user, stakeAmount);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, user);
        vm.stopPrank();

        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);

        uint256 withdrawTime = (regenStaker.REWARD_DURATION() * withdrawTimePercent) / 100;
        vm.warp(block.timestamp + withdrawTime);

        vm.startPrank(user);
        regenStaker.withdraw(depositId, stakeAmount);
        vm.stopPrank();

        assertEq(regenStaker.depositorTotalStaked(user), 0);
        assertEq(regenStaker.depositorTotalEarningPower(user), 0);

        vm.startPrank(user);
        uint256 claimedImmediately = regenStaker.claimReward(depositId);
        vm.stopPrank();

        uint256 expectedReward = (rewardAmount * withdrawTimePercent) / 100;
        assertApproxEqRel(claimedImmediately, expectedReward, ONE_IN_A_NANO);

        uint256 remainingTime = regenStaker.REWARD_DURATION() - withdrawTime;
        vm.warp(block.timestamp + remainingTime);

        vm.startPrank(user);
        uint256 claimedLater = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertEq(claimedLater, 0);
    }

    function testFuzz_RewardClaiming_ClaimByDesignatedClaimer_Succeeds(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase,
        uint256 firstClaimTimePercent
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);
        uint256 minClaimTime = 10;
        uint256 maxClaimTime = 90;
        firstClaimTimePercent = bound(firstClaimTimePercent, minClaimTime, maxClaimTime);

        address owner = makeAddr("owner");
        address designatedClaimer = makeAddr("claimer");

        whitelistUser(owner, true, false, true);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        stakeToken.mint(owner, stakeAmount);
        vm.startPrank(owner);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, owner);
        regenStaker.alterClaimer(depositId, designatedClaimer);
        vm.stopPrank();

        (, , , , address retrievedClaimer, , ) = regenStaker.deposits(depositId);
        assertEq(retrievedClaimer, designatedClaimer);

        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);

        uint256 firstClaimTime = (regenStaker.REWARD_DURATION() * firstClaimTimePercent) / 100;
        vm.warp(block.timestamp + firstClaimTime);

        uint256 initialClaimerBalance = rewardToken.balanceOf(designatedClaimer);
        vm.startPrank(designatedClaimer);
        uint256 claimedAmount1 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        uint256 expectedFirst = (rewardAmount * firstClaimTimePercent) / 100;
        assertApproxEqRel(claimedAmount1, expectedFirst, ONE_IN_A_NANO);
        assertEq(rewardToken.balanceOf(designatedClaimer), initialClaimerBalance + claimedAmount1);

        uint256 remainingTime = regenStaker.REWARD_DURATION() - firstClaimTime;
        vm.warp(block.timestamp + remainingTime);

        initialClaimerBalance = rewardToken.balanceOf(designatedClaimer);
        vm.startPrank(designatedClaimer);
        uint256 claimedAmount2 = regenStaker.claimReward(depositId);
        vm.stopPrank();

        uint256 remainingTimePercent = 100 - firstClaimTimePercent;
        uint256 expectedSecond = (rewardAmount * remainingTimePercent) / 100;
        assertApproxEqRel(claimedAmount2, expectedSecond, ONE_IN_A_NANO);
        assertEq(rewardToken.balanceOf(designatedClaimer), initialClaimerBalance + claimedAmount2);

        assertApproxEqRel(claimedAmount1 + claimedAmount2, rewardAmount, ONE_IN_A_NANO);
    }

    function testFuzz_RewardClaiming_RevertIf_ClaimByNonOwnerNonClaimer(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase,
        uint256 seedForAddresses
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);

        address owner = makeAddr(string(abi.encodePacked("owner", seedForAddresses)));
        address designatedClaimer = makeAddr(string(abi.encodePacked("claimer", seedForAddresses)));
        address unrelatedUser = makeAddr(string(abi.encodePacked("unrelated", seedForAddresses)));

        vm.assume(owner != designatedClaimer);
        vm.assume(owner != unrelatedUser);
        vm.assume(designatedClaimer != unrelatedUser);

        whitelistUser(owner, true, false, true);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        stakeToken.mint(owner, stakeAmount);
        vm.startPrank(owner);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, owner);
        regenStaker.alterClaimer(depositId, designatedClaimer);
        vm.stopPrank();

        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);
        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.startPrank(unrelatedUser);
        vm.expectRevert(
            abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not claimer or owner"), unrelatedUser)
        );
        regenStaker.claimReward(depositId);
        vm.stopPrank();
    }

    function testFuzz_RewardClaiming_OwnerCanStillClaimAfterDesignatingNewClaimer(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase,
        uint256 seedForAddresses
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);

        address ownerAddr = makeAddr(string(abi.encodePacked("owner", seedForAddresses)));
        address newClaimer = makeAddr(string(abi.encodePacked("claimer", seedForAddresses)));

        vm.assume(ownerAddr != newClaimer);

        whitelistUser(ownerAddr, true, false, true);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        stakeToken.mint(ownerAddr, stakeAmount);
        vm.startPrank(ownerAddr);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, ownerAddr);
        regenStaker.alterClaimer(depositId, newClaimer);
        vm.stopPrank();

        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);
        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.startPrank(ownerAddr);
        uint256 claimedByOwner = regenStaker.claimReward(depositId);
        vm.stopPrank();

        assertApproxEqRel(claimedByOwner, rewardAmount, ONE_IN_A_PICO);
    }

    function testFuzz_RevertIf_WithdrawWhenPaused(uint256 stakeAmountBase, uint256 withdrawAmountRatio) public {
        uint256 minStake = 100;
        uint256 maxStake = 10_000;
        stakeAmountBase = bound(stakeAmountBase, minStake, maxStake);
        uint256 minWithdrawRatio = 1;
        uint256 maxWithdrawRatio = 90;
        withdrawAmountRatio = bound(withdrawAmountRatio, minWithdrawRatio, maxWithdrawRatio);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        uint256 withdrawAmount = (stakeAmount * withdrawAmountRatio) / 100;
        vm.assume(withdrawAmount > 0);

        address user = makeAddr("user");
        whitelistUser(user, true, false, true);

        stakeToken.mint(user, stakeAmount);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, user);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused());

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        regenStaker.withdraw(depositId, withdrawAmount);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.unpause();
        assertFalse(regenStaker.paused());
    }

    function testFuzz_RevertIf_ClaimRewardWhenPaused(uint256 stakeAmountBase, uint256 rewardAmountBase) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        uint256 rewardAmount = getRewardAmount(rewardAmountBase);

        address user = makeAddr("user");
        whitelistUser(user, true, false, true);

        stakeToken.mint(user, stakeAmount);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, user);
        vm.stopPrank();

        rewardToken.mint(address(regenStaker), rewardAmount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);
        uint256 halfDuration = regenStaker.REWARD_DURATION() / 2;
        vm.warp(block.timestamp + halfDuration);

        vm.prank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused());

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        regenStaker.claimReward(depositId);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.unpause();
        assertFalse(regenStaker.paused());
    }

    function testFuzz_RevertIf_Contribute_GrantRoundAddressZero(
        uint256 stakeAmountBase,
        uint256 rewardAmountBase,
        uint256 contributionAmountBase
    ) public {
        stakeAmountBase = bound(stakeAmountBase, 1, 10_000);
        rewardAmountBase = bound(rewardAmountBase, 1, 100_000);
        contributionAmountBase = bound(contributionAmountBase, 1, 1_000);

        uint256 stakeAmount = getStakeAmount(stakeAmountBase);
        uint256 rewardAmount = getRewardAmount(rewardAmountBase);
        uint256 contributionAmount = getRewardAmount(contributionAmountBase);

        address mockGrantRound = makeAddr("mockGrantRound");
        address contributor = makeAddr("contributor");

        vm.mockCall(
            mockGrantRound,
            abi.encodeWithSignature("signup(uint256,address,bytes32)", contributionAmount, address(this), bytes32(0)),
            abi.encode(uint256(1))
        );
        vm.mockCall(
            mockGrantRound,
            abi.encodeWithSignature("vote(uint256,uint256)", uint256(1), contributionAmount),
            abi.encode()
        );

        whitelistUser(contributor, true, true, true);

        stakeToken.mint(contributor, stakeAmount);
        rewardToken.mint(address(regenStaker), rewardAmount);

        vm.startPrank(contributor);
        stakeToken.approve(address(regenStaker), stakeAmount);
        Staker.DepositIdentifier depositId = regenStaker.stake(stakeAmount, contributor);
        vm.stopPrank();

        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(rewardAmount);
        vm.warp(block.timestamp + regenStaker.REWARD_DURATION());

        vm.prank(ADMIN);
        regenStaker.pause();
        assertTrue(regenStaker.paused());

        vm.startPrank(contributor);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        regenStaker.contribute(depositId, mockGrantRound, contributor, contributionAmount, bytes32(0));
        vm.stopPrank();

        vm.startPrank(ADMIN);
        regenStaker.unpause();
        assertFalse(regenStaker.paused());
    }
}
