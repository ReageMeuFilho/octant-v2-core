// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MorphoCompounderStrategy } from "src/strategies/yieldSkimming/MorphoCompounderStrategy.sol";
import { BaseHealthCheck } from "src/strategies/periphery/BaseHealthCheck.sol";
import { UniswapV3Swapper } from "src/strategies/periphery/UniswapV3Swapper.sol";
import { MorphoCompounderStrategyVaultFactory } from "src/factories/MorphoCompounderStrategyVaultFactory.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVault } from "src/strategies/interfaces/IVault.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { MorphoCompounderWrapper } from "test/wrappers/MorphoCompounderWrapper.sol";

/// @title MorphoCompounder Test
/// @author Octant
/// @notice Integration tests for the MorphoCompounder strategy using a mainnet fork
contract MorphoCompounderStrategyTest is Test {
    using SafeERC20 for ERC20;

    // Strategy instance
    MorphoCompounderStrategy public strategy;
    ITokenizedStrategy public vault;
    MorphoCompounderWrapper public wrapper;

    // Factory for creating strategies
    YieldSkimmingTokenizedStrategy tokenizedStrategy;
    MorphoCompounderStrategyVaultFactory public factory;

    // Strategy parameters
    address public management;
    address public keeper;
    address public emergencyAdmin;
    address public donationAddress;
    string public vaultSharesName = "MorphoCompounder Vault Shares";
    bytes32 public strategySalt = keccak256("TEST_STRATEGY_SALT");

    // Test user
    address public user = address(0x1234);

    // Mainnet addresses
    address public constant YIELD_VAULT = 0x074134A2784F4F66b6ceD6f68849382990Ff3215;
    address public constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Test constants
    uint256 public constant INITIAL_DEPOSIT = 100000e18; // YIELD_VAULT has 18 decimals
    uint256 public mainnetFork;
    uint256 public mainnetForkBlock = 22508883 - 6500 * 90; // latest alchemy block - 90 days
    YieldSkimmingTokenizedStrategy public implementation;

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
        factory = new MorphoCompounderStrategyVaultFactory();

        // Deploy wrapper
        wrapper = new MorphoCompounderWrapper(
            YIELD_VAULT,
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            address(tokenizedStrategy)
        );

        // Deploy strategy using the factory's createStrategy method
        vm.startPrank(management);
        address strategyAddress = factory.createStrategy(
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            strategySalt,
            address(implementation)
        );
        vm.stopPrank();

        // Cast the deployed address to our strategy type
        strategy = MorphoCompounderStrategy(strategyAddress);
        vault = ITokenizedStrategy(address(strategy));

        // Label addresses for better trace outputs
        vm.label(address(strategy), "MorphoCompounder");
        vm.label(address(factory), "YieldSkimmingVaultFactory");
        vm.label(YIELD_VAULT, "Morpho Yield Vault");
        vm.label(TOKENIZED_STRATEGY_ADDRESS, "TokenizedStrategy");
        vm.label(management, "Management");
        vm.label(keeper, "Keeper");
        vm.label(emergencyAdmin, "Emergency Admin");
        vm.label(donationAddress, "Donation Address");
        vm.label(user, "Test User");
        vm.label(WETH, "WETH");

        // Airdrop YIELD_VAULT tokens to test user
        airdrop(ERC20(YIELD_VAULT), user, INITIAL_DEPOSIT);

        // Approve strategy to spend user's tokens
        vm.startPrank(user);
        ERC20(YIELD_VAULT).approve(address(strategy), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Test that the strategy is properly initialized
    function testInitializationMorpho() public view {
        assertEq(IERC4626(address(strategy)).asset(), YIELD_VAULT, "Yield vault address incorrect");
        assertEq(vault.management(), management, "Management address incorrect");
        assertEq(vault.keeper(), keeper, "Keeper address incorrect");
        assertEq(vault.emergencyAdmin(), emergencyAdmin, "Emergency admin incorrect");
        assertGt(strategy.getLastReportedExchangeRate(), 0, "Last reported exchange rate should be initialized");
    }

    /// @notice Test depositing assets into the strategy
    function testDepositMorpho() public {
        uint256 depositAmount = 100e18; // 100 YIELD_VAULT

        // Initial balances
        uint256 initialUserBalance = ERC20(YIELD_VAULT).balanceOf(user);

        // Deposit assets
        vm.startPrank(user);
        // approve the strategy to spend the user's tokens
        ERC20(YIELD_VAULT).approve(address(strategy), depositAmount);
        uint256 sharesReceived = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Verify balances after deposit
        assertEq(
            ERC20(YIELD_VAULT).balanceOf(user),
            initialUserBalance - depositAmount,
            "User balance not reduced correctly"
        );

        assertGt(sharesReceived, 0, "No shares received from deposit");
        assertGt(strategy.balanceOfShares(), 0, "Strategy should have deployed assets to yield vault");
    }

    /// @notice Test withdrawing assets from the strategy
    function testWithdraw() public {
        uint256 depositAmount = 100e18; // 100 YIELD_VAULT

        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);

        // Initial balances before withdrawal
        uint256 initialUserBalance = ERC20(YIELD_VAULT).balanceOf(user);
        uint256 initialShareBalance = vault.balanceOf(user);

        // Withdraw half of the deposit
        uint256 withdrawAmount = depositAmount / 2;
        uint256 sharesToBurn = vault.previewWithdraw(withdrawAmount);
        uint256 assetsReceived = vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();

        // Verify balances after withdrawal
        assertEq(
            ERC20(YIELD_VAULT).balanceOf(user),
            initialUserBalance + withdrawAmount,
            "User didn't receive correct assets"
        );
        assertEq(vault.balanceOf(user), initialShareBalance - sharesToBurn, "Shares not burned correctly");
        assertEq(assetsReceived, withdrawAmount, "Incorrect amount of assets received");
    }

    /// @notice Test the harvesting functionality using explicit profit simulation
    function testHarvestWithProfitMorpho() public {
        uint256 depositAmount = 100e18; // 100 YIELD_VAULT

        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Check initial state
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 initialExchangeRate = strategy.getLastReportedExchangeRate();

        // Simulate exchange rate increase (10% increase)
        uint256 newExchangeRate = (initialExchangeRate * 11) / 10;

        // the actual yield vault's pricePerShare
        vm.mockCall(YIELD_VAULT, abi.encodeWithSignature("pricePerShare()"), abi.encode(newExchangeRate));

        uint256 donationAddressBalanceBefore = ERC20(address(strategy)).balanceOf(donationAddress);

        // Prepare to call report and expect event
        vm.startPrank(keeper);

        // Call report and capture the returned values
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();

        // Clear mock to avoid interference with other tests
        vm.clearMockedCalls();

        // Assert profit and loss
        assertGt(profit, 0, "Profit should be positive");
        assertEq(loss, 0, "There should be no loss");

        uint256 donationAddressBalanceAfter = ERC20(address(strategy)).balanceOf(donationAddress);

        // donation address should have received the profit
        assertGt(
            donationAddressBalanceAfter,
            donationAddressBalanceBefore,
            "Donation address should have received profit"
        );

        // Check total assets after harvest
        uint256 totalAssetsAfter = vault.totalAssets();

        assertEq(totalAssetsAfter, totalAssetsBefore, "Total assets should not change after harvest");

        // donation address should be able to withdraw the profit
        vm.startPrank(donationAddress);
        vault.redeem(donationAddressBalanceAfter, donationAddress, donationAddress);
        vm.stopPrank();

        // check vault balance of donation address
        assertEq(vault.balanceOf(donationAddress), 0, "Donation address should have no shares after redeem");
        assertEq(
            ERC20(address(strategy)).balanceOf(donationAddress),
            0,
            "Donation address should have no balance after redeem"
        );
        // should have received yield vault shares
        assertGt(
            ERC20(YIELD_VAULT).balanceOf(donationAddress),
            0,
            "Donation address should have received yield vault shares"
        );

        // Withdraw everything
        vm.startPrank(user);
        uint256 sharesToRedeem = vault.balanceOf(user);
        uint256 assetsReceived = vault.redeem(sharesToRedeem, user, user);
        vm.stopPrank();

        // Verify user received their original deposit plus profit
        assertApproxEqRel(
            assetsReceived * newExchangeRate,
            depositAmount * initialExchangeRate,
            0.000001e18, // 0.0001% tolerance
            "User should receive original deposit"
        );
    }

    /// @notice Test multiple users with fair profit distribution
    function testMultipleUserProfitDistributionMorpho() public {
        TestState memory state;

        // First user deposits
        state.user1 = user; // Reuse existing test user
        state.user2 = address(0x5678);
        state.depositAmount1 = 1000e18; // 1000 YIELD_VAULT
        state.depositAmount2 = 2000e18; // 2000 YIELD_VAULT

        // Get initial exchange rate
        state.initialExchangeRate = strategy.getLastReportedExchangeRate();

        vm.startPrank(state.user1);
        vault.deposit(state.depositAmount1, state.user1);
        vm.stopPrank();

        // Generate yield for first user (10% increase in exchange rate)
        state.newExchangeRate1 = (state.initialExchangeRate * 110) / 100;

        // Check donation address balance before harvest
        state.donationBalanceBefore1 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Mock the yield vault's pricePerShare instead of strategy's internal method
        vm.mockCall(YIELD_VAULT, abi.encodeWithSignature("pricePerShare()"), abi.encode(state.newExchangeRate1));

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
        airdrop(ERC20(YIELD_VAULT), state.user2, state.depositAmount2);
        vm.stopPrank();

        vm.startPrank(state.user2);
        ERC20(YIELD_VAULT).approve(address(strategy), type(uint256).max);
        vault.deposit(state.depositAmount2, state.user2);
        vm.stopPrank();

        // Clear mock
        vm.clearMockedCalls();

        // Generate more yield after second user joined (5% increase from last rate)
        state.newExchangeRate2 = (state.newExchangeRate1 * 105) / 100;

        // Check donation address balance before second harvest
        state.donationBalanceBefore2 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Mock the yield vault's pricePerShare
        vm.mockCall(YIELD_VAULT, abi.encodeWithSignature("pricePerShare()"), abi.encode(state.newExchangeRate2));

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
    function testHarvestMorpho() public {
        uint256 depositAmount = 100e18; // 100 YIELD_VAULT

        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Capture initial state
        uint256 initialAssets = vault.totalAssets();
        uint256 initialExchangeRate = strategy.getLastReportedExchangeRate();

        // Call report as keeper (which internally calls _harvestAndReport)
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // Get new exchange rate and total assets
        uint256 newExchangeRate = strategy.getLastReportedExchangeRate();
        uint256 newTotalAssets = vault.totalAssets();

        // mock pricePerShare to be 1.1x the initial exchange rate
        vm.mockCall(YIELD_VAULT, abi.encodeWithSignature("pricePerShare()"), abi.encode((newExchangeRate * 11) / 10));

        // Verify exchange rate is updated
        assertEq(newExchangeRate, initialExchangeRate, "Exchange rate should be updated after harvest");

        // Verify total assets after harvest
        // Note: We don't check for specific increases here as we're using a mainnet fork
        // and yield calculation can vary, but assets should be >= than before unless there's a loss
        assertGe(newTotalAssets, initialAssets, "Total assets should not decrease after harvest");
    }

    /// @notice Test emergency exit functionality
    function testEmergencyExit() public {
        // Setup - deposit a significant amount
        uint256 depositAmount = 1000e6; // 1000 USDC

        vm.startPrank(user);
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
            0.00001e18, // 0.1% tolerance
            "User should receive approximately original deposit value"
        );
    }

    /// @notice Test the sweep function for non-asset ERC20 tokens
    function testSweep() public {
        // Create a mock token that we'll sweep
        MockERC20 mockToken = new MockERC20(18);
        mockToken.mint(address(strategy), 1000e18);

        // Verify token balance in strategy
        assertEq(mockToken.balanceOf(address(strategy)), 1000e18, "Strategy should have mock tokens");
        assertEq(mockToken.balanceOf(strategy.GOV()), 0, "GOV should have no mock tokens initially");

        // Call sweep function
        vm.startPrank(strategy.GOV());
        strategy.sweep(address(mockToken));
        vm.stopPrank();

        // Verify tokens were swept to governance
        assertEq(mockToken.balanceOf(address(strategy)), 0, "Strategy should have no mock tokens after sweep");
        assertEq(mockToken.balanceOf(strategy.GOV()), 1000e18, "GOV should have all mock tokens after sweep");
    }

    /// @notice Test that trying to sweep the asset token reverts
    function testCannotSweepAsset() public {
        // Try to sweep the asset token, which should revert
        vm.startPrank(strategy.GOV());
        vm.expectRevert("!asset");
        strategy.sweep(YIELD_VAULT);
        vm.stopPrank();
    }

    /// @notice Test exchange rate tracking and yield calculation
    function testExchangeRateTracking() public {
        uint256 depositAmount = 1000e18; // 1000 YIELD_VAULT

        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Get initial exchange rate
        uint256 initialExchangeRate = strategy.getLastReportedExchangeRate();

        // Skip time and mine blocks
        skip(30 days);
        vm.roll(block.number + 6500 * 30);

        // Simulate a 5% increase in exchange rate
        uint256 newExchangeRate = (initialExchangeRate * 105) / 100;

        // Mock the getCurrentExchangeRate function
        vm.mockCall(YIELD_VAULT, abi.encodeWithSignature("pricePerShare()"), abi.encode(newExchangeRate));

        // Report to capture yield
        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();

        // Clear mock
        vm.clearMockedCalls();

        // Log and verify profit
        assertGt(profit, 0, "Should have captured profit from exchange rate increase");
        assertEq(loss, 0, "Should have no loss");

        // Verify exchange rate was updated
        uint256 updatedExchangeRate = strategy.getLastReportedExchangeRate();
        assertEq(updatedExchangeRate, newExchangeRate, "Exchange rate should be updated after harvest");
    }

    /// @notice Test getting the last reported exchange rate
    function testGetLastReportedExchangeRate() public view {
        uint256 rate = strategy.getLastReportedExchangeRate();
        assertGt(rate, 0, "Exchange rate should be initialized and greater than zero");
    }

    /// @notice Test balance of asset and shares
    function testBalanceOfAssetAndShares() public {
        uint256 depositAmount = 100e18;
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 assetBalance = strategy.balanceOfAsset();
        uint256 sharesBalance = strategy.balanceOfShares();

        assertEq(assetBalance, sharesBalance, "Asset and shares balance should match for this strategy");
        assertGt(assetBalance, 0, "Asset balance should be greater than zero after deposit");
    }

    /// @notice Test sweep function for unauthorized access
    function testSweepUnauthorized() public {
        MockERC20 mockToken = new MockERC20(18);
        mockToken.mint(address(strategy), 1000e18);

        // Try to sweep as a non-governance address
        vm.startPrank(user);
        vm.expectRevert();
        strategy.sweep(address(mockToken));
        vm.stopPrank();
    }

    /// @notice Test onlyGovernance modifier
    function testOnlyGovernanceModifier() public {
        // Try to call sweep as a non-governance address
        MockERC20 mockToken = new MockERC20(18);
        mockToken.mint(address(strategy), 1000e18);

        vm.startPrank(user);
        vm.expectRevert();
        strategy.sweep(address(mockToken));
        vm.stopPrank();
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
        uint256 initialExchangeRate = strategy.getLastReportedExchangeRate();
        uint256 newExchangeRate = (initialExchangeRate * 7) / 3; // 233%
        vm.mockCall(YIELD_VAULT, abi.encodeWithSignature("pricePerShare()"), abi.encode(newExchangeRate));

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
        uint256 initialExchangeRate = strategy.getLastReportedExchangeRate();

        // make a 10 time profit (should revert when doHealthCheck is true but not when it is false)
        vm.mockCall(YIELD_VAULT, abi.encodeWithSignature("pricePerShare()"), abi.encode((initialExchangeRate * 10)));

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
        strategy.updateProfitLimitRatio(5000);
        vm.stopPrank();

        // check the profit limit ratio
        assertEq(strategy.getProfitLimitRatio(), 5000);
    }

    function testSetDoHealthCheckToFalse() public {
        vm.startPrank(management);
        strategy.setDoHealthCheck(false);
        vm.stopPrank();

        // check the do health check
        assertEq(strategy.doHealthCheck(), false);
    }

    /// @notice Test _tendTrigger always returns false
    function testTendTriggerAlwaysFalse() public view {
        bool trigger = wrapper.exposeTendTrigger();
        assertEq(trigger, false, "Tend trigger should always be false");
    }
}
