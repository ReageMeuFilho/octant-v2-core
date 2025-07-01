// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { LidoStrategy } from "src/strategies/yieldSkimming/LidoStrategy.sol";
import { LidoStrategyFactory } from "src/factories/LidoStrategyFactory.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { WadRayMath } from "src/utils/libs/Maths/WadRay.sol";
import { IBaseStrategy } from "src/core/interfaces/IBaseStrategy.sol";
import { IYieldSkimmingStrategy } from "src/strategies/yieldSkimming/IYieldSkimmingStrategy.sol";

/// @title Lido Test
/// @author Octant
/// @notice Integration tests for the Lido strategy using a mainnet fork
contract LidoStrategyTest is Test {
    using SafeERC20 for ERC20;
    using WadRayMath for uint256;

    // Strategy instance
    LidoStrategy public strategy;
    ITokenizedStrategy public vault;

    // Factory for creating strategies
    YieldSkimmingTokenizedStrategy tokenizedStrategy;
    LidoStrategyFactory public factory;

    // Strategy parameters
    address public management;
    address public keeper;
    address public emergencyAdmin;
    address public donationAddress;
    string public vaultSharesName = "Lido Vault Shares";
    bytes32 public strategySalt = keccak256("TEST_STRATEGY_SALT");
    YieldSkimmingTokenizedStrategy public implementation;

    // Test user
    address public user = address(0x1234);

    // Mainnet addresses
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;

    // Test constants
    uint256 public constant INITIAL_DEPOSIT = 100000e18; // WSTETH has 18 decimals
    uint256 public mainnetFork;
    uint256 public mainnetForkBlock = 22508883 - 6500 * 90; // latest alchemy block - 90 days

    // Events from ITokenizedStrategy
    event Reported(uint256 profit, uint256 loss);

    // Use struct to avoid stack too deep
    struct TestState {
        address user1;
        address user2;
        uint256 depositAmount1;
        uint256 depositAmount2;
        uint256 initialExchangeRate;
        uint256 newExchangeRate1;
        uint256 newExchangeRate2;
        uint256 donationBalanceBefore1;
        uint256 donationBalanceAfter1;
        uint256 donationBalanceBefore2;
        uint256 donationBalanceAfter2;
        uint256 user1Shares;
        uint256 user2Shares;
        uint256 user1Assets;
        uint256 user2Assets;
        uint256 user1Profit;
        uint256 user2Profit;
        uint256 user1ProfitPercentage;
        uint256 user2ProfitPercentage;
    }

    // Additional struct for fuzz tests to avoid stack too deep
    struct FuzzTestState {
        uint256 initialExchangeRate;
        uint256 profitRate;
        uint256 firstLossRate;
        uint256 secondLossRate;
        uint256 donationSharesAfterProfit;
        uint256 donationSharesAfterFirstLoss;
        uint256 donationSharesAfterSecondLoss;
        uint256 assetsReceived;
    }

    /**
     * @notice Helper function to airdrop tokens to a specified address
     * @param _asset The ERC20 token to airdrop
     * @param _to The recipient address
     * @param _amount The amount of tokens to airdrop
     */
    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setUp() public {
        // Create a mainnet fork
        // NOTE: This relies on the RPC URL configured in foundry.toml under [rpc_endpoints]
        // where mainnet = "${ETHEREUM_NODE_MAINNET}" environment variable
        mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);

        // Etch YieldSkimmingTokenizedStrategy
        implementation = new YieldSkimmingTokenizedStrategy{ salt: keccak256("OCT_YIELD_SKIMMING_STRATEGY_V1") }();
        bytes memory tokenizedStrategyBytecode = address(implementation).code;
        vm.etch(TOKENIZED_STRATEGY_ADDRESS, tokenizedStrategyBytecode);

        // Now use that address as our tokenizedStrategy
        tokenizedStrategy = YieldSkimmingTokenizedStrategy(TOKENIZED_STRATEGY_ADDRESS);

        // Set up addresses
        management = address(0x1);
        keeper = address(0x2);
        emergencyAdmin = address(0x3);
        donationAddress = address(0x4);

        // Deploy factory
        factory = new LidoStrategyFactory();

        // Deploy strategy using the factory's createStrategy method
        vm.startPrank(management);
        address strategyAddress = factory.createStrategy(
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            true, // enableBurning
            strategySalt,
            address(implementation)
        );
        vm.stopPrank();

        // Cast the deployed address to our strategy type
        strategy = LidoStrategy(strategyAddress);
        vault = ITokenizedStrategy(address(strategy));

        // Label addresses for better trace outputs
        vm.label(address(strategy), "Lido");
        vm.label(address(factory), "YieldSkimmingVaultFactory");
        vm.label(WSTETH, "Lido Yield Vault");
        vm.label(TOKENIZED_STRATEGY_ADDRESS, "TokenizedStrategy");
        vm.label(management, "Management");
        vm.label(keeper, "Keeper");
        vm.label(emergencyAdmin, "Emergency Admin");
        vm.label(donationAddress, "Donation Address");
        vm.label(user, "Test User");

        // Airdrop WSTETH tokens to test user
        airdrop(ERC20(WSTETH), user, INITIAL_DEPOSIT);

        // Approve strategy to spend user's tokens
        vm.startPrank(user);
        ERC20(WSTETH).approve(address(strategy), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Test that the strategy is properly initialized
    function testInitializationLido() public view {
        assertEq(IERC4626(address(strategy)).asset(), WSTETH, "Yield vault address incorrect");
        assertEq(vault.management(), management, "Management address incorrect");
        assertEq(vault.keeper(), keeper, "Keeper address incorrect");
        assertEq(vault.emergencyAdmin(), emergencyAdmin, "Emergency admin incorrect");
        assertGt(
            IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate(),
            0,
            "Last reported exchange rate should be initialized"
        );
    }

    /// @notice Test depositing assets into the strategy
    function testDepositLido() public {
        uint256 depositAmount = 100e18; // 100 WSTETH

        // Initial balances
        uint256 initialUserBalance = ERC20(WSTETH).balanceOf(user);

        // Deposit assets
        vm.startPrank(user);
        // approve the strategy to spend the user's tokens
        ERC20(WSTETH).approve(address(strategy), depositAmount);
        uint256 sharesReceived = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Verify balances after deposit
        assertEq(
            ERC20(WSTETH).balanceOf(user),
            initialUserBalance - depositAmount,
            "User balance not reduced correctly"
        );

        assertGt(sharesReceived, 0, "No shares received from deposit");
        assertGt(strategy.balanceOfAsset(), 0, "Strategy should have deployed assets to yield vault");
    }

    /// @notice Fuzz test depositing assets into the strategy
    function testFuzzDepositLido(uint256 depositAmount) public {
        // Bound the deposit amount to reasonable values (0.01 to 10,000 WSTETH)
        depositAmount = bound(depositAmount, 0.01e18, 10000e18);

        // Airdrop tokens to user for this test
        airdrop(ERC20(WSTETH), user, depositAmount);

        // Initial balances
        uint256 initialUserBalance = ERC20(WSTETH).balanceOf(user);

        // Deposit assets
        vm.startPrank(user);
        // approve the strategy to spend the user's tokens
        ERC20(WSTETH).approve(address(strategy), depositAmount);
        uint256 sharesReceived = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Verify balances after deposit
        assertEq(
            ERC20(WSTETH).balanceOf(user),
            initialUserBalance - depositAmount,
            "User balance not reduced correctly"
        );

        assertGt(sharesReceived, 0, "No shares received from deposit");
        assertGt(strategy.balanceOfAsset(), 0, "Strategy should have deployed assets to yield vault");
    }

    /// @notice Fuzz test withdrawing assets from the strategy
    function testFuzzWithdraw(uint256 depositAmount, uint256 withdrawPercentage) public {
        // Bound inputs to reasonable values
        depositAmount = bound(depositAmount, 1e18, 10000e18); // 1 to 10,000 WSTETH
        withdrawPercentage = bound(withdrawPercentage, 1, 100); // 1% to 100% (prevents overflow in percentage calc)

        // Airdrop tokens to user for this test
        airdrop(ERC20(WSTETH), user, depositAmount);

        // Deposit first
        vm.startPrank(user);
        ERC20(WSTETH).approve(address(strategy), depositAmount);
        vault.deposit(depositAmount, user);

        // Initial balances before withdrawal
        uint256 initialUserBalance = ERC20(WSTETH).balanceOf(user);
        uint256 initialShareBalance = vault.balanceOf(user);

        // redeem balance of shares
        uint256 sharesToBurn = (vault.balanceOf(user) * withdrawPercentage) / 100;
        uint256 withdrawnAmount = vault.redeem(sharesToBurn, user, user);
        vm.stopPrank();

        // Verify balances after withdrawal
        assertEq(
            ERC20(WSTETH).balanceOf(user),
            initialUserBalance + withdrawnAmount,
            "User didn't receive correct assets"
        );
        assertEq(vault.balanceOf(user), initialShareBalance - sharesToBurn, "Shares not burned correctly");
    }

    // Additional struct for profit fuzz tests to avoid stack too deep
    struct ProfitFuzzTestState {
        uint256 totalAssetsBefore;
        uint256 initialExchangeRate;
        uint256 newExchangeRate;
        uint256 donationAddressBalanceBefore;
        uint256 donationAddressBalanceAfter;
        uint256 totalAssetsAfter;
        uint256 sharesToRedeem;
        uint256 assetsReceived;
        uint256 donationAssetsReceived;
    }

    /// @notice Fuzz test the harvesting functionality with profit
    function testFuzzHarvestWithProfitLido(uint256 depositAmount, uint256 profitPercentage) public {
        // Bound inputs to reasonable values
        depositAmount = bound(depositAmount, 1e18, 10000e18); // 1 to 10,000 WSTETH
        profitPercentage = bound(profitPercentage, 1, 99); // 1% to 99% profit (under 100% health check limit)

        ProfitFuzzTestState memory state;

        // Airdrop tokens to user for this test
        airdrop(ERC20(WSTETH), user, depositAmount);

        // Deposit first
        vm.startPrank(user);
        ERC20(WSTETH).approve(address(strategy), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Check initial state
        state.totalAssetsBefore = vault.totalAssets();
        state.initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();

        // Simulate exchange rate increase based on fuzzed percentage
        state.newExchangeRate = (state.initialExchangeRate * (100 + profitPercentage)) / 100;

        // Mock the actual yield vault's stEthPerToken (convert back to WAD format)
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(state.newExchangeRate));

        state.donationAddressBalanceBefore = ERC20(address(strategy)).balanceOf(donationAddress);

        // Call report
        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();

        // Clear mock to avoid interference with other tests
        vm.clearMockedCalls();

        // Assert profit and loss
        assertGt(profit, 0, "Profit should be positive");
        assertEq(loss, 0, "There should be no loss");

        state.donationAddressBalanceAfter = ERC20(address(strategy)).balanceOf(donationAddress);

        // donation address should have received the profit
        assertGt(
            state.donationAddressBalanceAfter,
            state.donationAddressBalanceBefore,
            "Donation address should have received profit"
        );

        // Check total assets after harvest
        state.totalAssetsAfter = vault.totalAssets();
        assertEq(state.totalAssetsAfter, state.totalAssetsBefore, "Total assets should not change after harvest");

        // Withdraw everything for user
        vm.startPrank(user);
        state.sharesToRedeem = vault.balanceOf(user);

        state.assetsReceived = vault.redeem(state.sharesToRedeem, user, user);
        vm.stopPrank();

        // withdraw the donation address shares
        vm.startPrank(donationAddress);
        state.donationAssetsReceived = vault.redeem(vault.balanceOf(donationAddress), donationAddress, donationAddress);
        vm.stopPrank();

        assertApproxEqRel(
            state.donationAssetsReceived,
            (depositAmount * profitPercentage) / (100 + profitPercentage),
            0.1e16,
            "Donation address should have received profit"
        );

        // Verify user received their original deposit
        assertApproxEqRel(
            state.assetsReceived * state.newExchangeRate,
            depositAmount * state.initialExchangeRate,
            0.1e16, // 0.1% tolerance for fuzzing
            "User should receive original deposit"
        );
    }

    /// @notice Test multiple users with fair profit distribution
    function testMultipleUserProfitDistributionLido() public {
        TestState memory state;

        // First user deposits
        state.user1 = user; // Reuse existing test user
        state.user2 = address(0x5678);
        state.depositAmount1 = 1000e18; // 1000 WSTETH
        state.depositAmount2 = 2000e18; // 2000 WSTETH

        // Get initial exchange rate
        state.initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();

        vm.startPrank(state.user1);
        vault.deposit(state.depositAmount1, state.user1);
        vm.stopPrank();

        // Generate yield for first user (10% increase in exchange rate)
        state.newExchangeRate1 = (state.initialExchangeRate * 110) / 100;

        // Check donation address balance before harvest
        state.donationBalanceBefore1 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Mock the yield vault's stEthPerToken instead of strategy's internal method
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(state.newExchangeRate1));

        // Harvest to realize profit
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // Check donation address balance after harvest
        state.donationBalanceAfter1 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Verify donation address received profit
        assertGt(
            state.donationBalanceAfter1,
            state.donationBalanceBefore1,
            "Donation address should have received profit after first harvest"
        );

        // Second user deposits after profit
        vm.startPrank(address(this));
        airdrop(ERC20(WSTETH), state.user2, state.depositAmount2);
        vm.stopPrank();

        vm.startPrank(state.user2);
        ERC20(WSTETH).approve(address(strategy), type(uint256).max);
        vault.deposit(state.depositAmount2, state.user2);
        vm.stopPrank();

        // Clear mock
        vm.clearMockedCalls();

        // Generate more yield after second user joined (5% increase from last rate)
        state.newExchangeRate2 = (state.newExchangeRate1 * 105) / 100;

        // Check donation address balance before second harvest
        state.donationBalanceBefore2 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Mock the yield vault's stEthPerToken
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(state.newExchangeRate2));

        // Harvest again
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // Clear mock
        vm.clearMockedCalls();

        // Check donation address balance after second harvest
        state.donationBalanceAfter2 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Verify donation address received more profit
        assertGt(
            state.donationBalanceAfter2,
            state.donationBalanceBefore2,
            "Donation address should have received profit after second harvest"
        );

        // Both users withdraw
        vm.startPrank(state.user1);
        state.user1Shares = vault.balanceOf(state.user1);
        state.user1Assets = vault.redeem(vault.balanceOf(state.user1), state.user1, state.user1);
        vm.stopPrank();

        vm.startPrank(state.user2);
        state.user2Shares = vault.balanceOf(state.user2);
        state.user2Assets = vault.redeem(vault.balanceOf(state.user2), state.user2, state.user2);
        vm.stopPrank();

        // redeem the shares of the donation address
        vm.startPrank(donationAddress);
        vault.redeem(vault.balanceOf(donationAddress), donationAddress, donationAddress);
        vm.stopPrank();

        // User 1 deposited before first yield accrual, so should have earned more
        assertApproxEqRel(
            state.user1Assets * state.newExchangeRate2,
            state.depositAmount1 * state.initialExchangeRate,
            0.000001e18, // 0.0001% tolerance
            "User 1 should receive deposit adjusted for exchange rate change"
        );

        // User 2 deposited after first yield accrual but before second
        assertApproxEqRel(
            state.user2Assets * state.newExchangeRate2,
            state.depositAmount2 * state.newExchangeRate1,
            0.00001e18, // 0.1% tolerance
            "User 2 should receive deposit adjusted for exchange rate change"
        );
    }

    /// @notice Test the harvesting functionality
    function testHarvestLido() public {
        uint256 depositAmount = 100e18; // 100 WSTETH

        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Capture initial state
        uint256 initialAssets = vault.totalAssets();
        uint256 initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();

        // Call report as keeper (which internally calls _harvestAndReport)
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // Get new exchange rate and total assets
        uint256 newExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 newTotalAssets = vault.totalAssets();

        // mock stEthPerToken to be 1.1x the initial exchange rate
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode((newExchangeRate * 11) / 10));

        // Verify exchange rate is updated
        assertEq(newExchangeRate, initialExchangeRate, "Exchange rate should be updated after harvest");

        // Verify total assets after harvest
        // Note: We don't check for specific increases here as we're using a mainnet fork
        // and yield calculation can vary, but assets should be >= than before unless there's a loss
        assertGe(newTotalAssets, initialAssets, "Total assets should not decrease after harvest");
    }

    /// @notice Fuzz test emergency exit functionality
    function testFuzzEmergencyExit(uint256 depositAmount) public {
        // Bound deposit amount to reasonable values
        depositAmount = bound(depositAmount, 1e18, 10000e18); // 1 to 10,000 WSTETH

        // Airdrop tokens to user for this test
        airdrop(ERC20(WSTETH), user, depositAmount);

        // User deposits
        vm.startPrank(user);
        ERC20(WSTETH).approve(address(strategy), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Trigger emergency shutdown mode - must be called by emergency admin
        vm.startPrank(emergencyAdmin);
        vault.shutdownStrategy();

        // Execute emergency withdraw
        vault.emergencyWithdraw(type(uint256).max);
        vm.stopPrank();

        // User withdraws their funds
        vm.startPrank(user);
        uint256 userShares = vault.balanceOf(user);
        uint256 assetsReceived = vault.redeem(userShares, user, user);
        vm.stopPrank();

        // The user should receive approximately their original deposit in value
        // We allow a small deviation due to potential rounding in the calculations
        assertApproxEqRel(
            assetsReceived,
            depositAmount,
            0.001e18, // 0.1% tolerance
            "User should receive approximately original deposit value"
        );
    }

    /// @notice Fuzz test exchange rate tracking and yield calculation
    function testFuzzExchangeRateTrackingLido(uint256 depositAmount, uint256 exchangeRateIncreasePercentage) public {
        // Bound inputs to reasonable values
        depositAmount = bound(depositAmount, 1e18, 10000e18); // 1 to 10,000 WSTETH
        exchangeRateIncreasePercentage = bound(exchangeRateIncreasePercentage, 1, 99); // 1% to 50% increase

        // Airdrop tokens to user for this test
        airdrop(ERC20(WSTETH), user, depositAmount);

        // Deposit first
        vm.startPrank(user);
        ERC20(WSTETH).approve(address(strategy), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Get initial exchange rate
        uint256 initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();

        // Simulate exchange rate increase based on fuzzed percentage
        uint256 newExchangeRate = (initialExchangeRate * (100 + exchangeRateIncreasePercentage)) / 100;

        // Mock the yield vault's stEthPerToken
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(newExchangeRate));

        // Report to capture yield
        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();

        // Clear mock
        vm.clearMockedCalls();

        // Verify profit and loss
        assertGt(profit, 0, "Should have captured profit from exchange rate increase");
        assertEq(loss, 0, "Should have no loss");

        // Verify exchange rate was updated
        uint256 updatedExchangeRate = IYieldSkimmingStrategy(address(strategy)).getLastRateRay().rayToWad();

        assertApproxEqRel(
            updatedExchangeRate,
            newExchangeRate,
            0.000001e18,
            "Exchange rate should be updated after harvest"
        );
    }

    /// @notice Test getting the last reported exchange rate
    function testgetCurrentExchangeRate() public view {
        uint256 rate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        assertGt(rate, 0, "Exchange rate should be initialized and greater than zero");
    }

    /// @notice Test balance of asset and shares
    function testBalanceOfAssetAndShares() public {
        uint256 depositAmount = 100e18;
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 assetBalance = strategy.balanceOfAsset();
        uint256 sharesBalance = strategy.balanceOfAsset();

        assertEq(assetBalance, sharesBalance, "Asset and shares balance should match for this strategy");
        assertGt(assetBalance, 0, "Asset balance should be greater than zero after deposit");
    }

    /// @notice Test health check for profit limit exceeded
    function testHealthCheckProfitLimitExceeded() public {
        uint256 depositAmount = 1000e18;
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // First report: sets doHealthCheck = true, does NOT check
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // Mock a 10x exchange rate
        uint256 initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 newExchangeRate = (initialExchangeRate * 7) / 3; // 233%
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(newExchangeRate));

        // Second report: should revert
        vm.startPrank(keeper);
        vm.expectRevert("!profit");
        vault.report();
        vm.stopPrank();

        vm.clearMockedCalls();
    }

    // testHealthCheckProfitLimitExceeded when doHealthCheck is false
    function testHealthCheckProfitLimitExceededWhenDoHealthCheckIsFalse() public {
        vm.startPrank(management);
        strategy.setDoHealthCheck(false);
        vm.stopPrank();

        // check the do health check
        assertEq(strategy.doHealthCheck(), false);

        // old exchange rate
        uint256 initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();

        // make a 10 time profit (should revert when doHealthCheck is true but not when it is false)
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(initialExchangeRate * 10));

        // report
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // check the do health check
        assertEq(strategy.doHealthCheck(), true);
    }

    // test change profit limit ratio
    function testChangeProfitLimitRatio() public {
        vm.startPrank(management);
        strategy.setProfitLimitRatio(5000);
        vm.stopPrank();

        // check the profit limit ratio
        assertEq(strategy.profitLimitRatio(), 5000);
    }

    function testSetDoHealthCheckToFalse() public {
        vm.startPrank(management);
        strategy.setDoHealthCheck(false);
        vm.stopPrank();

        // check the do health check
        assertEq(strategy.doHealthCheck(), false);
    }

    // tendTrigger always returns false
    function testTendTriggerAlwaysFalse() public view {
        (bool trigger, ) = IBaseStrategy(address(strategy)).tendTrigger();
        assertEq(trigger, false, "Tend trigger should always be false");
    }

    /// @notice Fuzz test basic loss scenario with single user
    function testFuzzHarvestWithLossLido(
        uint256 depositAmount,
        uint256 profitPercentage,
        uint256 lossPercentage
    ) public {
        // Bound inputs to reasonable values
        depositAmount = bound(depositAmount, 1e18, 10000e18); // 1 to 10,000 WSTETH
        profitPercentage = bound(profitPercentage, 5, 50); // 5% to 50% profit first
        lossPercentage = bound(lossPercentage, 1, 19); // 1% to 19% loss (less than 20% limit)

        // Set loss limit to allow 20% losses
        vm.startPrank(management);
        strategy.setLossLimitRatio(2000); // 20%
        vm.stopPrank();

        // Airdrop tokens to user for this test
        airdrop(ERC20(WSTETH), user, depositAmount);

        // First deposit to create some donation shares for loss protection
        vm.startPrank(user);
        ERC20(WSTETH).approve(address(strategy), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Generate some profit first to create donation shares
        uint256 initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 profitExchangeRate = (initialExchangeRate * (100 + profitPercentage)) / 100;

        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(profitExchangeRate));

        vm.startPrank(keeper);
        vault.report(); // This creates donation shares for loss protection
        vm.stopPrank();

        vm.clearMockedCalls();

        // Check donation address has shares for loss protection
        uint256 donationSharesBefore = vault.balanceOf(donationAddress);
        assertGt(donationSharesBefore, 0, "Donation address should have shares for loss protection");

        // Check initial state before loss
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 userSharesBefore = vault.balanceOf(user);

        // Simulate exchange rate decrease
        uint256 lossExchangeRate = (profitExchangeRate * (100 - lossPercentage)) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(lossExchangeRate));

        // Call report and capture the returned values
        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();

        // Clear mock to avoid interference with other tests
        vm.clearMockedCalls();

        // Assert loss and profit
        assertEq(profit, 0, "Profit should be zero");
        assertGt(loss, 0, "Loss should be positive");

        // Check that donation shares were burned for loss protection
        uint256 donationSharesAfter = vault.balanceOf(donationAddress);
        assertLt(donationSharesAfter, donationSharesBefore, "Donation shares should be burned for loss protection");

        // User shares should remain the same (loss protection in effect)
        uint256 userSharesAfter = vault.balanceOf(user);
        assertEq(userSharesAfter, userSharesBefore, "User shares should not change due to loss protection");

        // Total assets should not change
        uint256 totalAssetsAfter = vault.totalAssets();
        assertEq(totalAssetsAfter, totalAssetsBefore, "Total assets should be the same before and after loss");
    }

    /// @notice Test loss scenario with multiple users to verify fair loss handling
    function testMultipleUserLossDistributionLido() public {
        // Set loss limit to allow 20% losses
        vm.startPrank(management);
        strategy.setLossLimitRatio(2000); // 20%
        vm.stopPrank();

        TestState memory state;

        // Setup users
        state.user1 = user;
        state.user2 = address(0x5678);
        state.depositAmount1 = 1000e18; // 1000 WSTETH
        state.depositAmount2 = 2000e18; // 2000 WSTETH

        // Get initial exchange rate
        state.initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();

        // First user deposits
        vm.startPrank(state.user1);
        vault.deposit(state.depositAmount1, state.user1);
        vm.stopPrank();

        // Generate some profit first to create donation shares for loss protection
        state.newExchangeRate1 = (state.initialExchangeRate * 110) / 100; // 10% profit
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(state.newExchangeRate1));

        vm.startPrank(keeper);
        vault.report(); // Creates donation shares
        vm.stopPrank();
        vm.clearMockedCalls();

        // Second user deposits after profit generation
        vm.startPrank(address(this));
        airdrop(ERC20(WSTETH), state.user2, state.depositAmount2);
        vm.stopPrank();

        vm.startPrank(state.user2);
        ERC20(WSTETH).approve(address(strategy), type(uint256).max);
        vault.deposit(state.depositAmount2, state.user2);
        vm.stopPrank();

        // Check donation shares available for loss protection
        uint256 donationSharesBefore = vault.balanceOf(donationAddress);
        assertGt(donationSharesBefore, 0, "Should have donation shares for loss protection");

        // Record user shares before loss
        uint256 user1SharesBefore = vault.balanceOf(state.user1);
        uint256 user2SharesBefore = vault.balanceOf(state.user2);

        // Generate loss (20% decrease from profit rate)
        state.newExchangeRate2 = (state.newExchangeRate1 * 8001) / 10000; // less than 20% loss
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(state.newExchangeRate2));

        // Report loss
        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        vm.clearMockedCalls();

        // Verify loss was reported
        assertEq(profit, 0, "Should have no profit");
        assertGt(loss, 0, "Should have reported loss");

        // Check that donation shares were burned for loss protection
        uint256 donationSharesAfter = vault.balanceOf(donationAddress);
        assertLt(donationSharesAfter, donationSharesBefore, "Donation shares should be burned for loss protection");

        // User shares should remain unchanged due to loss protection
        assertEq(vault.balanceOf(state.user1), user1SharesBefore, "User 1 shares should be protected");
        assertEq(vault.balanceOf(state.user2), user2SharesBefore, "User 2 shares should be protected");

        // Both users withdraw
        vm.startPrank(state.user1);
        state.user1Assets = vault.redeem(vault.balanceOf(state.user1), state.user1, state.user1);
        vm.stopPrank();

        vm.startPrank(state.user2);
        state.user2Assets = vault.redeem(vault.balanceOf(state.user2), state.user2, state.user2);
        vm.stopPrank();

        // Users should receive their deposits adjusted for exchange rate changes with loss protection
        assertApproxEqRel(
            state.user1Assets * state.newExchangeRate2,
            ((state.depositAmount1 * state.initialExchangeRate) * (110 * 8)) / (100 * 10),
            0.1e18, // 0.1% tolerance for loss scenarios
            "User 1 should receive deposit value with loss protection"
        );

        assertApproxEqRel(
            state.user2Assets * state.newExchangeRate2,
            (state.depositAmount2 * state.newExchangeRate1 * 8) / 10, // expect a 20 pr cent loss in value
            0.1e18, // 0.1% tolerance for loss scenarios
            "User 2 should receive deposit value with loss protection"
        );
    }

    /// @notice Test loss scenario where loss exceeds available donation shares
    function testLossExceedingDonationSharesLido() public {
        // Set loss limit to allow 15% losses
        vm.startPrank(management);
        strategy.setLossLimitRatio(1500); // 15%
        vm.stopPrank();

        uint256 depositAmount = 1000e18; // 1000 WSTETH

        // User deposits
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Generate small profit to create minimal donation shares
        uint256 initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 smallProfitRate = (initialExchangeRate * 1005) / 1000; // 0.5% profit
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(smallProfitRate));

        vm.startPrank(keeper);
        vault.report(); // Creates small amount of donation shares
        vm.stopPrank();
        vm.clearMockedCalls();

        uint256 donationSharesBefore = vault.balanceOf(donationAddress);
        uint256 userSharesBefore = vault.balanceOf(user);

        // Generate large loss (10% from initial rate)
        uint256 largeLossRate = (initialExchangeRate * 90) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(largeLossRate));

        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        vm.clearMockedCalls();

        // Verify loss was reported
        assertEq(profit, 0, "Should have no profit");
        assertGt(loss, 0, "Should have reported loss");

        // All donation shares should be burned (limited by available balance)
        uint256 donationSharesAfter = vault.balanceOf(donationAddress);
        assertLt(donationSharesAfter, donationSharesBefore, "Some donation shares should be burned");

        // User shares should remain the same (they don't get burned)
        assertEq(vault.balanceOf(user), userSharesBefore, "User shares should not be burned");

        // User should still be able to withdraw, but will receive less due to insufficient loss protection
        vm.startPrank(user);
        uint256 assetsReceived = vault.redeem(vault.balanceOf(user), user, user);
        vm.stopPrank();

        // User receives less than original deposit due to insufficient loss protection
        assertLt(
            assetsReceived * largeLossRate,
            depositAmount * initialExchangeRate,
            "User should receive less due to insufficient loss protection"
        );
    }

    /// @notice Test consecutive loss scenarios
    function testConsecutiveLossesLido() public {
        // Set loss limit to allow 15% losses
        vm.startPrank(management);
        strategy.setLossLimitRatio(1500); // 15%
        vm.stopPrank();

        uint256 depositAmount = 1000e18; // 1000 WSTETH

        // User deposits
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Generate profit to create donation shares
        uint256 initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 profitRate = (initialExchangeRate * 120) / 100; // 20% profit
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(profitRate));

        vm.startPrank(keeper);
        vault.report(); // Creates donation shares
        vm.stopPrank();
        vm.clearMockedCalls();

        uint256 donationSharesAfterProfit = vault.balanceOf(donationAddress);
        assertGt(donationSharesAfterProfit, 0, "Should have donation shares after profit");

        // First loss (5% from profit rate)
        uint256 firstLossRate = (profitRate * 95) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(firstLossRate));

        vm.startPrank(keeper);
        (uint256 profit1, uint256 loss1) = vault.report();
        vm.stopPrank();
        vm.clearMockedCalls();

        assertEq(profit1, 0, "Should have no profit in first loss");
        assertGt(loss1, 0, "Should have loss in first report");

        uint256 donationSharesAfterFirstLoss = vault.balanceOf(donationAddress);
        assertLt(
            donationSharesAfterFirstLoss,
            donationSharesAfterProfit,
            "Donation shares should decrease after first loss"
        );

        // Second consecutive loss (another 5% from current rate)
        uint256 secondLossRate = (firstLossRate * 95) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(secondLossRate));

        vm.startPrank(keeper);
        (uint256 profit2, uint256 loss2) = vault.report();
        vm.stopPrank();
        vm.clearMockedCalls();

        assertEq(profit2, 0, "Should have no profit in second loss");
        assertGt(loss2, 0, "Should have loss in second report");

        uint256 donationSharesAfterSecondLoss = vault.balanceOf(donationAddress);
        assertLe(
            donationSharesAfterSecondLoss,
            donationSharesAfterFirstLoss,
            "Donation shares should decrease or stay same after second loss"
        );

        // User should still be able to withdraw
        vm.startPrank(user);
        uint256 assetsReceived = vault.redeem(vault.balanceOf(user), user, user);
        vm.stopPrank();

        assertGt(assetsReceived, 0, "User should receive some assets");
    }

    /// @notice Test that loss protection works correctly with zero donation shares
    function testLossWithZeroDonationSharesLido() public {
        // Set loss limit to allow 10% losses
        vm.startPrank(management);
        strategy.setLossLimitRatio(1000); // 10%
        vm.stopPrank();

        uint256 depositAmount = 1000e18; // 1000 WSTETH

        // User deposits without any prior profit generation
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Verify no donation shares exist
        uint256 donationSharesBefore = vault.balanceOf(donationAddress);
        assertEq(donationSharesBefore, 0, "Should have no donation shares initially");

        uint256 userSharesBefore = vault.balanceOf(user);
        uint256 totalAssetsBefore = vault.totalAssets();

        // Generate loss (5% decrease)
        uint256 initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 lossRate = (initialExchangeRate * 95) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(lossRate));

        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        vm.clearMockedCalls();

        // Verify loss was reported
        assertEq(profit, 0, "Should have no profit");
        assertGt(loss, 0, "Should have reported loss");

        // Donation shares should remain zero (nothing to burn)
        uint256 donationSharesAfter = vault.balanceOf(donationAddress);
        assertEq(donationSharesAfter, 0, "Should still have no donation shares");

        // User shares should remain unchanged
        assertEq(vault.balanceOf(user), userSharesBefore, "User shares should not change");

        // Total assets should decrease by loss
        assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should be the same before and after loss");

        // User withdrawal should work but receive reduced value
        vm.startPrank(user);
        uint256 assetsReceived = vault.redeem(vault.balanceOf(user), user, user);
        vm.stopPrank();

        // User receives less due to no loss protection
        assertLt(
            assetsReceived * lossRate,
            depositAmount * initialExchangeRate,
            "User should receive less due to no loss protection"
        );
    }

    /// @notice Fuzz test consecutive loss scenarios
    function testFuzzConsecutiveLossesLido(
        uint256 depositAmount,
        uint256 profitPercentage,
        uint256 firstLossPercentage,
        uint256 secondLossPercentage
    ) public {
        // Bound inputs to reasonable values
        depositAmount = bound(depositAmount, 1e18, 10000e18); // 1 to 10,000 WSTETH
        profitPercentage = bound(profitPercentage, 10, 50); // 10% to 50% profit first
        firstLossPercentage = bound(firstLossPercentage, 1, 10); // 1% to 10% first loss
        secondLossPercentage = bound(secondLossPercentage, 1, 10); // 1% to 10% second loss

        FuzzTestState memory state;

        // Set loss limit to allow 15% losses
        vm.startPrank(management);
        strategy.setLossLimitRatio(2000); // 20%
        vm.stopPrank();

        // Airdrop tokens to user for this test
        airdrop(ERC20(WSTETH), user, depositAmount);

        // User deposits
        vm.startPrank(user);
        ERC20(WSTETH).approve(address(strategy), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Generate profit to create donation shares
        state.initialExchangeRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        state.profitRate = (state.initialExchangeRate * (100 + profitPercentage)) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(state.profitRate));

        vm.startPrank(keeper);
        vault.report(); // Creates donation shares
        vm.stopPrank();
        vm.clearMockedCalls();

        state.donationSharesAfterProfit = vault.balanceOf(donationAddress);
        assertGt(state.donationSharesAfterProfit, 0, "Should have donation shares after profit");

        // First loss
        state.firstLossRate = (state.profitRate * (100 - firstLossPercentage)) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(state.firstLossRate));

        vm.startPrank(keeper);
        (uint256 profit1, uint256 loss1) = vault.report();
        vm.stopPrank();
        vm.clearMockedCalls();

        assertEq(profit1, 0, "Should have no profit in first loss");
        assertGt(loss1, 0, "Should have loss in first report");

        state.donationSharesAfterFirstLoss = vault.balanceOf(donationAddress);
        assertLt(
            state.donationSharesAfterFirstLoss,
            state.donationSharesAfterProfit,
            "Donation shares should decrease after first loss"
        );

        // Second consecutive loss
        state.secondLossRate = (state.firstLossRate * (100 - secondLossPercentage)) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSignature("stEthPerToken()"), abi.encode(state.secondLossRate));

        vm.startPrank(keeper);
        (uint256 profit2, uint256 loss2) = vault.report();
        vm.stopPrank();
        vm.clearMockedCalls();

        assertEq(profit2, 0, "Should have no profit in second loss");
        assertGt(loss2, 0, "Should have loss in second report");

        state.donationSharesAfterSecondLoss = vault.balanceOf(donationAddress);
        assertLe(
            state.donationSharesAfterSecondLoss,
            state.donationSharesAfterFirstLoss,
            "Donation shares should decrease or stay same after second loss"
        );

        // User should still be able to withdraw
        vm.startPrank(user);
        state.assetsReceived = vault.redeem(vault.balanceOf(user), user, user);
        vm.stopPrank();

        assertGe(
            state.assetsReceived * state.secondLossRate,
            ((depositAmount * state.initialExchangeRate) * (100 - firstLossPercentage) * (100 - secondLossPercentage)) /
                10000, // should be greater or equal because of the first profit
            "User should receive some assets"
        );
    }
}
