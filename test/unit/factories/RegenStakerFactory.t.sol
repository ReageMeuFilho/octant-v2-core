// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockEarningPowerCalculator } from "test/mocks/MockEarningPowerCalculator.sol";

contract RegenStakerFactoryTest is Test {
    RegenStakerFactory public factory;

    IERC20 public rewardsToken;
    IERC20Staking public stakeToken;
    IEarningPowerCalculator public earningPowerCalculator;

    address public admin;
    address public deployer1;
    address public deployer2;

    IWhitelist public stakerWhitelist;
    IWhitelist public contributionWhitelist;

    uint256 public constant MAX_BUMP_TIP = 1000e18;
    uint256 public constant MAX_CLAIM_FEE = 500;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 100e18;
    uint256 public constant REWARD_DURATION = 0; // 0 defaults to 30 days

    function setUp() public {
        admin = address(0x1);
        deployer1 = address(0x2);
        deployer2 = address(0x3);

        rewardsToken = new MockERC20(18);
        stakeToken = new MockERC20Staking(18);
        earningPowerCalculator = new MockEarningPowerCalculator();

        stakerWhitelist = new Whitelist();
        contributionWhitelist = new Whitelist();

        factory = new RegenStakerFactory();

        vm.label(address(factory), "RegenStakerFactory");
        vm.label(address(rewardsToken), "RewardsToken");
        vm.label(address(stakeToken), "StakeToken");
        vm.label(admin, "Admin");
        vm.label(deployer1, "Deployer1");
        vm.label(deployer2, "Deployer2");
    }

    function testCreateStaker() public {
        bytes32 salt = keccak256("TEST_STAKER_SALT");

        vm.startPrank(deployer1);
        address predictedAddress = factory.predictStakerAddress(salt);

        vm.expectEmit(true, true, true, true);
        emit StakerDeploy(
            deployer1,
            admin,
            predictedAddress,
            address(rewardsToken),
            address(stakeToken),
            MAX_BUMP_TIP,
            MAX_CLAIM_FEE,
            MINIMUM_STAKE_AMOUNT,
            salt
        );
        address stakerAddress = factory.createStaker(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt
        );
        vm.stopPrank();

        assertTrue(stakerAddress != address(0), "Staker address should not be zero");

        RegenStakerFactory.StakerInfo[] memory stakerInfos = factory.getStakersByDeployer(deployer1);
        assertEq(stakerInfos.length, 1, "Should have one staker");
        assertEq(stakerInfos[0].deployerAddress, deployer1, "Deployer address should match");
        assertEq(stakerInfos[0].admin, admin, "Admin address should match");
        assertEq(stakerInfos[0].rewardsToken, address(rewardsToken), "Rewards token should match");
        assertEq(stakerInfos[0].stakeToken, address(stakeToken), "Stake token should match");
        assertEq(stakerInfos[0].maxBumpTip, MAX_BUMP_TIP, "Max bump tip should match");
        assertEq(stakerInfos[0].maxClaimFee, MAX_CLAIM_FEE, "Max claim fee should match");
        assertEq(stakerInfos[0].minimumStakeAmount, MINIMUM_STAKE_AMOUNT, "Minimum stake amount should match");
        assertTrue(stakerInfos[0].timestamp > 0, "Timestamp should be set");

        RegenStaker staker = RegenStaker(stakerAddress);
        assertEq(address(staker.REWARD_TOKEN()), address(rewardsToken), "Rewards token should be set correctly");
        assertEq(address(staker.STAKE_TOKEN()), address(stakeToken), "Stake token should be set correctly");
        assertEq(staker.minimumStakeAmount(), MINIMUM_STAKE_AMOUNT, "Minimum stake amount should be set correctly");
    }

    function testCreateMultipleStakersPerDeployer() public {
        bytes32 salt1 = keccak256("FIRST_STAKER_SALT");
        bytes32 salt2 = keccak256("SECOND_STAKER_SALT");

        vm.startPrank(deployer1);
        address firstStaker = factory.createStaker(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt1
        );

        address secondStaker = factory.createStaker(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP + 100,
                maxClaimFee: MAX_CLAIM_FEE + 50,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT + 50e18,
                rewardDuration: REWARD_DURATION
            }),
            salt2
        );
        vm.stopPrank();

        assertTrue(firstStaker != secondStaker, "Stakers should have different addresses");

        RegenStakerFactory.StakerInfo[] memory stakerInfos = factory.getStakersByDeployer(deployer1);
        assertEq(stakerInfos.length, 2, "Should have two stakers");

        assertEq(stakerInfos[0].deployerAddress, deployer1, "First staker deployer should match");
        assertEq(stakerInfos[0].maxBumpTip, MAX_BUMP_TIP, "First staker max bump tip should match");

        assertEq(stakerInfos[1].deployerAddress, deployer1, "Second staker deployer should match");
        assertEq(stakerInfos[1].maxBumpTip, MAX_BUMP_TIP + 100, "Second staker max bump tip should match");
        assertEq(stakerInfos[1].maxClaimFee, MAX_CLAIM_FEE + 50, "Second staker max claim fee should match");
        assertEq(
            stakerInfos[1].minimumStakeAmount,
            MINIMUM_STAKE_AMOUNT + 50e18,
            "Second staker minimum stake should match"
        );
    }

    function testCreateStakersForDifferentDeployers() public {
        bytes32 salt1 = keccak256("DEPLOYER1_SALT");
        bytes32 salt2 = keccak256("DEPLOYER2_SALT");

        vm.prank(deployer1);
        address staker1 = factory.createStaker(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt1
        );

        vm.prank(deployer2);
        address staker2 = factory.createStaker(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt2
        );

        assertTrue(staker1 != staker2, "Stakers should have different addresses");

        RegenStakerFactory.StakerInfo[] memory staker1Infos = factory.getStakersByDeployer(deployer1);
        RegenStakerFactory.StakerInfo[] memory staker2Infos = factory.getStakersByDeployer(deployer2);

        assertEq(staker1Infos.length, 1, "Deployer1 should have one staker");
        assertEq(staker2Infos.length, 1, "Deployer2 should have one staker");

        assertEq(staker1Infos[0].deployerAddress, deployer1, "First deployer should match");
        assertEq(staker2Infos[0].deployerAddress, deployer2, "Second deployer should match");
    }

    function testDeterministicAddressing() public {
        bytes32 salt = keccak256("DETERMINISTIC_SALT");

        vm.prank(deployer1);
        address predictedAddress = factory.predictStakerAddress(salt);

        vm.prank(deployer1);
        address actualAddress = factory.createStaker(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt
        );

        assertEq(predictedAddress, actualAddress, "Predicted address should match actual address");
    }

    function testCreateStakerWithNullWhitelists() public {
        bytes32 salt = keccak256("NULL_WHITELIST_SALT");

        vm.prank(deployer1);
        address stakerAddress = factory.createStaker(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: IWhitelist(address(0)), // null staker whitelist
                contributionWhitelist: IWhitelist(address(0)), // null contribution whitelist
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt
        );

        assertTrue(stakerAddress != address(0), "Staker should be created with null whitelists");

        RegenStaker staker = RegenStaker(stakerAddress);
        assertTrue(
            address(staker.stakerWhitelist()) != address(0),
            "Staker whitelist should be deployed automatically"
        );
        assertTrue(
            address(staker.contributionWhitelist()) != address(0),
            "Contribution whitelist should be deployed automatically"
        );
    }

    function testGetStakersByDeployerEmptyArray() public view {
        RegenStakerFactory.StakerInfo[] memory stakerInfos = factory.getStakersByDeployer(deployer1);
        assertEq(stakerInfos.length, 0, "Should return empty array for deployer with no stakers");
    }
}

event StakerDeploy(
    address indexed deployer,
    address indexed admin,
    address indexed stakerAddress,
    address rewardsToken,
    address stakeToken,
    uint256 maxBumpTip,
    uint256 maxClaimFee,
    uint256 minimumStakeAmount,
    bytes32 salt
);
