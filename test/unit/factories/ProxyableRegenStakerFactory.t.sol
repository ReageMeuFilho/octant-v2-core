// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { ProxyableRegenStaker } from "src/regen/ProxyableRegenStaker.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";

contract MockERC20 is IERC20 {
    function totalSupply() external pure returns (uint256) {
        return 0;
    }
    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }
    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }
    function approve(address, uint256) external pure returns (bool) {
        return true;
    }
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}

contract MockERC20Staking is MockERC20, IERC20Staking {
    function delegate(address) external {}
    function delegates(address) external pure returns (address) {
        return address(0);
    }
    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external {}
    function nonces(address) external pure returns (uint256) {
        return 0;
    }
    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        return bytes32(0);
    }
}

contract MockEarningPowerCalculator is IEarningPowerCalculator {
    function getEarningPower(uint256 amount, address, address) external pure returns (uint256) {
        return amount;
    }

    function getNewEarningPower(uint256 amount, address, address, uint256) external pure returns (uint256, bool) {
        return (amount, false);
    }
}

contract ProxyableRegenStakerFactoryTest is Test {
    ProxyableRegenStaker public implementation;
    RegenStakerFactory public factory;

    MockERC20Staking public rewardToken;
    MockERC20Staking public stakeToken;
    MockEarningPowerCalculator public earningPowerCalculator;

    address public admin = makeAddr("admin");
    uint256 public constant MAX_BUMP_TIP = 1e18;
    uint256 public constant MAX_CLAIM_FEE = 1e17;
    uint256 public constant MIN_STAKE_AMOUNT = 1e18;
    uint256 public constant REWARD_DURATION = 30 days;

    function setUp() public {
        // Deploy mock contracts
        rewardToken = new MockERC20Staking();
        stakeToken = new MockERC20Staking();
        earningPowerCalculator = new MockEarningPowerCalculator();

        // Deploy implementation and factory
        implementation = new ProxyableRegenStaker();
        factory = new RegenStakerFactory(address(implementation));
    }

    function test_DeployProxyStaker() public {
        RegenStakerFactory.CreateStakerParams memory params = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(rewardToken)),
            stakeToken: stakeToken,
            admin: admin,
            stakerWhitelist: IWhitelist(address(0)),
            contributionWhitelist: IWhitelist(address(0)),
            allocationMechanismWhitelist: IWhitelist(address(0)),
            earningPowerCalculator: earningPowerCalculator,
            maxBumpTip: MAX_BUMP_TIP,
            maxClaimFee: MAX_CLAIM_FEE,
            minimumStakeAmount: MIN_STAKE_AMOUNT,
            rewardDuration: REWARD_DURATION
        });

        bytes32 salt = keccak256("test-salt");

        address stakerProxy = factory.createStaker(params, salt);

        // Verify deployment
        assertTrue(stakerProxy != address(0));
        assertEq(stakerProxy.code.length, MINIMAL_PROXY_BYTECODE_SIZE); // ~44 bytes minimal proxy bytecode

        // Verify initialization
        ProxyableRegenStaker staker = ProxyableRegenStaker(stakerProxy);
        assertEq(staker.admin(), admin);
        assertEq(address(staker.getRewardToken()), address(rewardToken));
        assertEq(address(staker.getStakeToken()), address(stakeToken));
        assertEq(staker.getMaxClaimFee(), MAX_CLAIM_FEE);
        assertEq(staker.rewardDuration(), REWARD_DURATION);
        assertEq(staker.minimumStakeAmount(), MIN_STAKE_AMOUNT);
    }

    function test_PredictStakerAddress() public {
        RegenStakerFactory.CreateStakerParams memory params = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(rewardToken)),
            stakeToken: stakeToken,
            admin: admin,
            stakerWhitelist: IWhitelist(address(0)),
            contributionWhitelist: IWhitelist(address(0)),
            allocationMechanismWhitelist: IWhitelist(address(0)),
            earningPowerCalculator: earningPowerCalculator,
            maxBumpTip: MAX_BUMP_TIP,
            maxClaimFee: MAX_CLAIM_FEE,
            minimumStakeAmount: MIN_STAKE_AMOUNT,
            rewardDuration: REWARD_DURATION
        });

        bytes32 salt = keccak256("prediction-test");

        // Predict address before deployment
        address predicted = factory.predictStakerAddress(salt);

        // Deploy and compare
        address actual = factory.createStaker(params, salt);

        assertEq(predicted, actual);
    }

    function test_DeterministicDeployment() public {
        RegenStakerFactory.CreateStakerParams memory params = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(rewardToken)),
            stakeToken: stakeToken,
            admin: admin,
            stakerWhitelist: IWhitelist(address(0)),
            contributionWhitelist: IWhitelist(address(0)),
            allocationMechanismWhitelist: IWhitelist(address(0)),
            earningPowerCalculator: earningPowerCalculator,
            maxBumpTip: MAX_BUMP_TIP,
            maxClaimFee: MAX_CLAIM_FEE,
            minimumStakeAmount: MIN_STAKE_AMOUNT,
            rewardDuration: REWARD_DURATION
        });

        bytes32 salt = keccak256("deterministic-test");

        // Deploy first instance
        address firstDeploy = factory.createStaker(params, salt);

        // Try to deploy again with same salt (should revert)
        vm.expectRevert();
        factory.createStaker(params, salt);

        // Deploy with different sender should produce different address
        vm.prank(makeAddr("different-sender"));
        address differentSenderDeploy = factory.createStaker(params, salt);

        assertTrue(firstDeploy != differentSenderDeploy);
    }

    function test_MultipleProxiesShareImplementation() public {
        RegenStakerFactory.CreateStakerParams memory params1 = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(rewardToken)),
            stakeToken: stakeToken,
            admin: admin,
            stakerWhitelist: IWhitelist(address(0)),
            contributionWhitelist: IWhitelist(address(0)),
            allocationMechanismWhitelist: IWhitelist(address(0)),
            earningPowerCalculator: earningPowerCalculator,
            maxBumpTip: MAX_BUMP_TIP,
            maxClaimFee: MAX_CLAIM_FEE,
            minimumStakeAmount: MIN_STAKE_AMOUNT,
            rewardDuration: REWARD_DURATION
        });

        RegenStakerFactory.CreateStakerParams memory params2 = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(rewardToken)),
            stakeToken: stakeToken,
            admin: makeAddr("admin2"),
            stakerWhitelist: IWhitelist(address(0)),
            contributionWhitelist: IWhitelist(address(0)),
            allocationMechanismWhitelist: IWhitelist(address(0)),
            earningPowerCalculator: earningPowerCalculator,
            maxBumpTip: MAX_BUMP_TIP * 2,
            maxClaimFee: MAX_CLAIM_FEE,
            minimumStakeAmount: MIN_STAKE_AMOUNT * 2,
            rewardDuration: REWARD_DURATION
        });

        // Deploy two different proxies
        address proxy1 = factory.createStaker(params1, keccak256("proxy1"));
        address proxy2 = factory.createStaker(params2, keccak256("proxy2"));

        // Verify they're different instances
        assertTrue(proxy1 != proxy2);

        // Verify they have different configurations
        ProxyableRegenStaker staker1 = ProxyableRegenStaker(proxy1);
        ProxyableRegenStaker staker2 = ProxyableRegenStaker(proxy2);

        assertEq(staker1.admin(), admin);
        assertEq(staker2.admin(), makeAddr("admin2"));
        assertEq(staker1.minimumStakeAmount(), MIN_STAKE_AMOUNT);
        assertEq(staker2.minimumStakeAmount(), MIN_STAKE_AMOUNT * 2);

        // Verify they use the same reward token (both set to same value)
        assertEq(address(staker1.getRewardToken()), address(staker2.getRewardToken()));
    }

    function test_GasBenchmark() public {
        RegenStakerFactory.CreateStakerParams memory params = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(rewardToken)),
            stakeToken: stakeToken,
            admin: admin,
            stakerWhitelist: IWhitelist(address(0)),
            contributionWhitelist: IWhitelist(address(0)),
            allocationMechanismWhitelist: IWhitelist(address(0)),
            earningPowerCalculator: earningPowerCalculator,
            maxBumpTip: MAX_BUMP_TIP,
            maxClaimFee: MAX_CLAIM_FEE,
            minimumStakeAmount: MIN_STAKE_AMOUNT,
            rewardDuration: REWARD_DURATION
        });

        // Benchmark multiple deployments
        uint256 totalGas = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 gasBefore = gasleft();
            factory.createStaker(params, keccak256(abi.encode("benchmark", i)));
            uint256 gasUsed = gasBefore - gasleft();
            totalGas += gasUsed;
        }

        uint256 averageGas = totalGas / 5;

        // For comparison, full contract deployment would be ~3M+ gas
        // Proxy deployment should be <300k gas each (much more efficient than full deployment)
        assertTrue(averageGas < 300000, "Proxy deployment should be very gas efficient");
    }

    function test_ImplementationCannotBeInitialized() public {
        // Try to initialize the implementation contract directly (should fail)
        vm.expectRevert();
        implementation.initialize(
            IERC20(address(rewardToken)),
            stakeToken,
            MAX_CLAIM_FEE,
            admin,
            IWhitelist(address(0)),
            IWhitelist(address(0)),
            IWhitelist(address(0)),
            earningPowerCalculator,
            MAX_BUMP_TIP,
            MIN_STAKE_AMOUNT,
            REWARD_DURATION
        );
    }
}
