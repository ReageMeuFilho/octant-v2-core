// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockERC20Permit } from "test/mocks/MockERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RegenStakerFactoryVariantsTest
 * @notice Tests for the RegenStakerFactory contract variant detection and deployment
 */
contract RegenStakerFactoryVariantsTest is Test {
    RegenStakerFactory factory;
    RegenEarningPowerCalculator calculator;
    Whitelist stakerWhitelist;
    Whitelist contributionWhitelist;
    Whitelist allocationMechanismWhitelist;

    MockERC20 basicToken;
    MockERC20Permit permitToken;
    MockERC20Staking stakingToken;

    address public constant ADMIN = address(0x1);
    uint256 public constant MAX_BUMP_TIP = 1e18;
    uint256 public constant MAX_CLAIM_FEE = 1e18;
    uint256 public constant MIN_REWARD_DURATION = 7 days;

    function setUp() public {
        vm.startPrank(ADMIN);

        // Deploy factory
        factory = new RegenStakerFactory();

        // Deploy test tokens
        basicToken = new MockERC20(18);
        permitToken = new MockERC20Permit(18);
        stakingToken = new MockERC20Staking(18);

        // Deploy whitelists
        stakerWhitelist = new Whitelist();
        contributionWhitelist = new Whitelist();
        allocationMechanismWhitelist = new Whitelist();

        // Deploy calculator
        calculator = new RegenEarningPowerCalculator(ADMIN, stakerWhitelist);

        vm.stopPrank();
    }

    function test_DetectStakerVariant_BasicERC20_ReturnsNO_DELEGATION() public {
        RegenStakerFactory.RegenStakerVariant variant = factory.detectStakerVariant(IERC20(address(basicToken)));
        assertEq(uint256(variant), uint256(RegenStakerFactory.RegenStakerVariant.NO_DELEGATION));
    }

    function test_DetectStakerVariant_PermitToken_ReturnsNO_DELEGATION() public {
        RegenStakerFactory.RegenStakerVariant variant = factory.detectStakerVariant(IERC20(address(permitToken)));
        assertEq(uint256(variant), uint256(RegenStakerFactory.RegenStakerVariant.NO_DELEGATION));
    }

    function test_DetectStakerVariant_StakingToken_ReturnsERC20_STAKING() public {
        RegenStakerFactory.RegenStakerVariant variant = factory.detectStakerVariant(IERC20(address(stakingToken)));
        assertEq(uint256(variant), uint256(RegenStakerFactory.RegenStakerVariant.ERC20_STAKING));
    }

    function test_GetRecommendedVariant_BasicERC20_ReturnsNO_DELEGATION() public view {
        RegenStakerFactory.RegenStakerVariant variant = factory.getRecommendedVariant(IERC20(address(basicToken)));
        assertEq(uint256(variant), uint256(RegenStakerFactory.RegenStakerVariant.NO_DELEGATION));
    }

    function test_GetRecommendedVariant_PermitToken_ReturnsNO_DELEGATION() public view {
        RegenStakerFactory.RegenStakerVariant variant = factory.getRecommendedVariant(IERC20(address(permitToken)));
        assertEq(uint256(variant), uint256(RegenStakerFactory.RegenStakerVariant.NO_DELEGATION));
    }

    function test_GetRecommendedVariant_StakingToken_ReturnsERC20_STAKING() public view {
        RegenStakerFactory.RegenStakerVariant variant = factory.getRecommendedVariant(IERC20(address(stakingToken)));
        assertEq(uint256(variant), uint256(RegenStakerFactory.RegenStakerVariant.ERC20_STAKING));
    }

    function test_CreateStaker_BasicERC20_DeploysNO_DELEGATION() public {
        RegenStakerFactory.CreateStakerParams memory params = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(basicToken)),
            stakeToken: IERC20(address(basicToken)),
            admin: ADMIN,
            stakerWhitelist: stakerWhitelist,
            contributionWhitelist: contributionWhitelist,
            allocationMechanismWhitelist: allocationMechanismWhitelist,
            earningPowerCalculator: calculator,
            maxBumpTip: MAX_BUMP_TIP,
            maxClaimFee: MAX_CLAIM_FEE,
            minimumStakeAmount: 0,
            rewardDuration: MIN_REWARD_DURATION
        });

        bytes memory permitCode = type(RegenStakerWithoutDelegateSurrogateVotes).creationCode;
        bytes memory stakingCode = type(RegenStaker).creationCode;

        (address stakerAddress, RegenStakerFactory.RegenStakerVariant variant) = factory.createStaker(
            params,
            bytes32(uint256(1)),
            permitCode,
            stakingCode
        );

        assertEq(uint256(variant), uint256(RegenStakerFactory.RegenStakerVariant.NO_DELEGATION));
        assertTrue(stakerAddress != address(0));

        // Verify it's actually a RegenStakerWithoutDelegateSurrogateVotes by checking the contract code
        // (This is a basic check - in practice you might verify specific functionality)
        assertTrue(stakerAddress.code.length > 0);
    }

    function test_CreateStaker_PermitToken_DeploysNO_DELEGATION() public {
        RegenStakerFactory.CreateStakerParams memory params = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(permitToken)),
            stakeToken: IERC20(address(permitToken)),
            admin: ADMIN,
            stakerWhitelist: stakerWhitelist,
            contributionWhitelist: contributionWhitelist,
            allocationMechanismWhitelist: allocationMechanismWhitelist,
            earningPowerCalculator: calculator,
            maxBumpTip: MAX_BUMP_TIP,
            maxClaimFee: MAX_CLAIM_FEE,
            minimumStakeAmount: 0,
            rewardDuration: MIN_REWARD_DURATION
        });

        bytes memory permitCode = type(RegenStakerWithoutDelegateSurrogateVotes).creationCode;
        bytes memory stakingCode = type(RegenStaker).creationCode;

        (address stakerAddress, RegenStakerFactory.RegenStakerVariant variant) = factory.createStaker(
            params,
            bytes32(uint256(2)),
            permitCode,
            stakingCode
        );

        assertEq(uint256(variant), uint256(RegenStakerFactory.RegenStakerVariant.NO_DELEGATION));
        assertTrue(stakerAddress != address(0));
        assertTrue(stakerAddress.code.length > 0);
    }

    function test_CreateStaker_StakingToken_DeploysERC20_STAKING() public {
        RegenStakerFactory.CreateStakerParams memory params = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(stakingToken)),
            stakeToken: IERC20(address(stakingToken)),
            admin: ADMIN,
            stakerWhitelist: stakerWhitelist,
            contributionWhitelist: contributionWhitelist,
            allocationMechanismWhitelist: allocationMechanismWhitelist,
            earningPowerCalculator: calculator,
            maxBumpTip: MAX_BUMP_TIP,
            maxClaimFee: MAX_CLAIM_FEE,
            minimumStakeAmount: 0,
            rewardDuration: MIN_REWARD_DURATION
        });

        bytes memory permitCode = type(RegenStakerWithoutDelegateSurrogateVotes).creationCode;
        bytes memory stakingCode = type(RegenStaker).creationCode;

        (address stakerAddress, RegenStakerFactory.RegenStakerVariant variant) = factory.createStaker(
            params,
            bytes32(uint256(3)),
            permitCode,
            stakingCode
        );

        assertEq(uint256(variant), uint256(RegenStakerFactory.RegenStakerVariant.ERC20_STAKING));
        assertTrue(stakerAddress != address(0));
        assertTrue(stakerAddress.code.length > 0);
    }
}
