// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
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
    IWhitelist public allocationMechanismWhitelist;

    uint256 public constant MAX_BUMP_TIP = 1000e18;
    uint256 public constant MAX_CLAIM_FEE = 500;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 100e18;
    uint256 public constant REWARD_DURATION = 30 days;

    event StakerDeploy(
        address indexed deployer,
        address indexed admin,
        address indexed stakerAddress,
        bytes32 salt,
        RegenStakerFactory.RegenStakerVariant variant
    );

    function setUp() public {
        admin = address(0x1);
        deployer1 = address(0x2);
        deployer2 = address(0x3);

        rewardsToken = new MockERC20(18);
        stakeToken = new MockERC20Staking(18);
        earningPowerCalculator = new MockEarningPowerCalculator();

        stakerWhitelist = new Whitelist();
        contributionWhitelist = new Whitelist();
        allocationMechanismWhitelist = new Whitelist();

        // Deploy the factory with both variants' bytecode (this test contract is the deployer)
        bytes memory regenStakerBytecode = type(RegenStaker).creationCode;
        bytes memory noDelegationBytecode = type(RegenStakerWithoutDelegateSurrogateVotes).creationCode;
        factory = new RegenStakerFactory(regenStakerBytecode, noDelegationBytecode);

        vm.label(address(factory), "RegenStakerFactory");
        vm.label(address(rewardsToken), "RewardsToken");
        vm.label(address(stakeToken), "StakeToken");
        vm.label(admin, "Admin");
        vm.label(deployer1, "Deployer1");
        vm.label(deployer2, "Deployer2");
    }

    function getRegenStakerBytecode() internal pure returns (bytes memory) {
        return type(RegenStaker).creationCode;
    }

    function testCreateStaker() public {
        bytes32 salt = keccak256("TEST_STAKER_SALT");

        // Build constructor params and bytecode for prediction
        bytes memory constructorParams = abi.encode(
            rewardsToken,
            stakeToken,
            earningPowerCalculator,
            MAX_BUMP_TIP,
            admin,
            REWARD_DURATION,
            MAX_CLAIM_FEE,
            MINIMUM_STAKE_AMOUNT,
            stakerWhitelist,
            contributionWhitelist,
            allocationMechanismWhitelist
        );
        bytes memory bytecode = bytes.concat(getRegenStakerBytecode(), constructorParams);

        vm.startPrank(deployer1);
        address predictedAddress = factory.predictStakerAddress(salt, deployer1, bytecode);

        vm.expectEmit(true, true, true, true);
        emit StakerDeploy(
            deployer1,
            admin,
            predictedAddress,
            salt,
            RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION
        );

        address stakerAddress = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                allocationMechanismWhitelist: allocationMechanismWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            getRegenStakerBytecode()
        );
        vm.stopPrank();

        assertTrue(stakerAddress != address(0), "Staker address should not be zero");

        RegenStaker staker = RegenStaker(stakerAddress);
        assertEq(address(staker.REWARD_TOKEN()), address(rewardsToken), "Rewards token should be set correctly");
        assertEq(address(staker.STAKE_TOKEN()), address(stakeToken), "Stake token should be set correctly");
        assertEq(staker.minimumStakeAmount(), MINIMUM_STAKE_AMOUNT, "Minimum stake amount should be set correctly");
    }

    function testCreateMultipleStakers() public {
        bytes32 salt1 = keccak256("FIRST_STAKER_SALT");
        bytes32 salt2 = keccak256("SECOND_STAKER_SALT");

        vm.startPrank(deployer1);
        address firstStaker = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                allocationMechanismWhitelist: allocationMechanismWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt1,
            getRegenStakerBytecode()
        );

        address secondStaker = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                allocationMechanismWhitelist: allocationMechanismWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP + 100,
                maxClaimFee: MAX_CLAIM_FEE + 50,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT + 50e18,
                rewardDuration: REWARD_DURATION
            }),
            salt2,
            getRegenStakerBytecode()
        );
        vm.stopPrank();

        assertTrue(firstStaker != secondStaker, "Stakers should have different addresses");
    }

    function testCreateStakersForDifferentDeployers() public {
        bytes32 salt1 = keccak256("DEPLOYER1_SALT");
        bytes32 salt2 = keccak256("DEPLOYER2_SALT");

        vm.prank(deployer1);
        address staker1 = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                allocationMechanismWhitelist: allocationMechanismWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt1,
            getRegenStakerBytecode()
        );

        vm.prank(deployer2);
        address staker2 = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                allocationMechanismWhitelist: allocationMechanismWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt2,
            getRegenStakerBytecode()
        );

        assertTrue(staker1 != staker2, "Stakers should have different addresses");
    }

    function testDeterministicAddressing() public {
        bytes32 salt = keccak256("DETERMINISTIC_SALT");

        // Build constructor params and bytecode for prediction
        bytes memory constructorParams = abi.encode(
            rewardsToken,
            stakeToken,
            earningPowerCalculator,
            MAX_BUMP_TIP,
            admin,
            REWARD_DURATION,
            MAX_CLAIM_FEE,
            MINIMUM_STAKE_AMOUNT,
            stakerWhitelist,
            contributionWhitelist,
            allocationMechanismWhitelist
        );
        bytes memory bytecode = bytes.concat(getRegenStakerBytecode(), constructorParams);

        vm.prank(deployer1);
        address predictedAddress = factory.predictStakerAddress(salt, deployer1, bytecode);

        vm.prank(deployer1);
        address actualAddress = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: stakerWhitelist,
                contributionWhitelist: contributionWhitelist,
                allocationMechanismWhitelist: allocationMechanismWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            getRegenStakerBytecode()
        );

        assertEq(predictedAddress, actualAddress, "Predicted address should match actual address");
    }

    function testCreateStakerWithNullWhitelists() public {
        bytes32 salt = keccak256("NULL_WHITELIST_SALT");

        vm.prank(deployer1);
        address stakerAddress = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerWhitelist: IWhitelist(address(0)),
                contributionWhitelist: IWhitelist(address(0)),
                allocationMechanismWhitelist: allocationMechanismWhitelist,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                maxClaimFee: MAX_CLAIM_FEE,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            getRegenStakerBytecode()
        );

        assertTrue(stakerAddress != address(0), "Staker should be created with null whitelists");

        RegenStaker staker = RegenStaker(stakerAddress);
        assertEq(
            address(staker.stakerWhitelist()),
            address(0),
            "Staker whitelist should be null when address(0) is passed"
        );
        assertEq(
            address(staker.contributionWhitelist()),
            address(0),
            "Contribution whitelist should be null when address(0) is passed"
        );
    }
}
