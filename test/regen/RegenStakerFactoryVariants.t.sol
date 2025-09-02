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
 * @notice Tests for the RegenStakerFactory contract explicit variant deployment
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

        bytes memory permitCode = type(RegenStakerWithoutDelegateSurrogateVotes).creationCode;
        bytes memory stakingCode = type(RegenStaker).creationCode;
        factory = new RegenStakerFactory(stakingCode, permitCode);

        basicToken = new MockERC20(18);
        permitToken = new MockERC20Permit(18);
        stakingToken = new MockERC20Staking(18);

        stakerWhitelist = new Whitelist();
        contributionWhitelist = new Whitelist();
        allocationMechanismWhitelist = new Whitelist();

        calculator = new RegenEarningPowerCalculator(ADMIN, stakerWhitelist);

        vm.stopPrank();
    }

    function test_CreateStakerWithoutDelegation_WithBasicERC20_Success() public {
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

        address stakerAddress = factory.createStakerWithoutDelegation(params, bytes32(uint256(1)), permitCode);

        assertTrue(stakerAddress != address(0));
        assertTrue(stakerAddress.code.length > 0);
    }

    function test_CreateStakerWithoutDelegation_WithPermitToken_Success() public {
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

        address stakerAddress = factory.createStakerWithoutDelegation(params, bytes32(uint256(2)), permitCode);

        assertTrue(stakerAddress != address(0));
        assertTrue(stakerAddress.code.length > 0);
    }

    function test_CreateStakerWithDelegation_WithStakingToken_Success() public {
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

        bytes memory stakingCode = type(RegenStaker).creationCode;

        address stakerAddress = factory.createStakerWithDelegation(params, bytes32(uint256(3)), stakingCode);

        assertTrue(stakerAddress != address(0));
        assertTrue(stakerAddress.code.length > 0);
    }

    function test_CreateStakerWithDelegation_WithBasicToken_Success() public {
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

        bytes memory stakingCode = type(RegenStaker).creationCode;

        address stakerAddress = factory.createStakerWithDelegation(params, bytes32(uint256(4)), stakingCode);

        assertTrue(stakerAddress != address(0));
        assertTrue(stakerAddress.code.length > 0);
    }

    function test_RevertIf_CreateStakerNoDelegation_WithInvalidBytecode() public {
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

        bytes memory wrongCode = type(RegenStaker).creationCode; // Using with-delegation code for without-delegation variant

        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerFactory.UnauthorizedBytecode.selector,
                RegenStakerFactory.RegenStakerVariant.WITHOUT_DELEGATION,
                keccak256(wrongCode),
                factory.canonicalBytecodeHash(RegenStakerFactory.RegenStakerVariant.WITHOUT_DELEGATION)
            )
        );

        factory.createStakerWithoutDelegation(params, bytes32(uint256(5)), wrongCode);
    }

    function test_RevertIf_CreateStakerERC20Staking_WithInvalidBytecode() public {
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

        bytes memory wrongCode = type(RegenStakerWithoutDelegateSurrogateVotes).creationCode; // Using without-delegation code for with-delegation variant

        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerFactory.UnauthorizedBytecode.selector,
                RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION,
                keccak256(wrongCode),
                factory.canonicalBytecodeHash(RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION)
            )
        );

        factory.createStakerWithDelegation(params, bytes32(uint256(6)), wrongCode);
    }

    function test_RevertIf_CreateStaker_WithEmptyBytecode() public {
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

        vm.expectRevert(RegenStakerFactory.InvalidBytecode.selector);
        factory.createStakerWithoutDelegation(params, bytes32(uint256(7)), "");

        vm.expectRevert(RegenStakerFactory.InvalidBytecode.selector);
        factory.createStakerWithDelegation(params, bytes32(uint256(8)), "");
    }

    function test_CanonicalBytecodeHashes_SetCorrectly() public view {
        bytes32 noDelegationHash = factory.canonicalBytecodeHash(
            RegenStakerFactory.RegenStakerVariant.WITHOUT_DELEGATION
        );
        bytes32 erc20StakingHash = factory.canonicalBytecodeHash(RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION);

        assertTrue(noDelegationHash != bytes32(0));
        assertTrue(erc20StakingHash != bytes32(0));
        assertTrue(noDelegationHash != erc20StakingHash);
    }

    function test_PredictStakerAddress_WorksCorrectly() public view {
        bytes32 salt = bytes32(uint256(100));
        address deployer = address(0x123);

        // Create constructor params to build bytecode
        bytes memory constructorParams = abi.encode(
            basicToken,
            basicToken,
            calculator,
            MAX_BUMP_TIP,
            ADMIN,
            MIN_REWARD_DURATION,
            MAX_CLAIM_FEE,
            0, // minimumStakeAmount
            stakerWhitelist,
            contributionWhitelist,
            allocationMechanismWhitelist
        );

        // Build bytecode with constructor params (using WITH_DELEGATION variant)
        bytes memory bytecode = bytes.concat(type(RegenStaker).creationCode, constructorParams);

        address predicted = factory.predictStakerAddress(salt, deployer, bytecode);
        assertTrue(predicted != address(0));
    }
}
