// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { RocketPoolStrategy } from "src/strategies/yieldSkimming/RocketPoolStrategy.sol";
import { RocketPoolStrategyVaultFactory } from "src/factories/yieldSkimming/RocketPoolStrategyVaultFactory.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IBaseStrategy } from "src/core/interfaces/IBaseStrategy.sol";

/// @title RocketPool Test
/// @author Octant
/// @notice Integration tests for the RocketPool strategy using a mainnet fork
contract RocketPoolStrategyTest is Test {
    using SafeERC20 for ERC20;

    // Strategy instance
    RocketPoolStrategy public strategy;
    ITokenizedStrategy public vault;

    // Factory for creating strategies
    YieldSkimmingTokenizedStrategy public tokenizedStrategy;
    RocketPoolStrategyVaultFactory public factory;

    // Strategy parameters
    address public management;
    address public keeper;
    address public emergencyAdmin;
    address public donationAddress;
    string public vaultSharesName = "RocketPool Vault Shares";
    bytes32 public strategySalt = keccak256("TEST_STRATEGY_SALT");
    YieldSkimmingTokenizedStrategy public implementation;

    // Test user
    address public user = address(0x1234);

    // Mainnet addresses
    address public constant R_ETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;

    // Test constants
    uint256 public constant INITIAL_DEPOSIT = 100000e18; // R_ETH has 18 decimals
    uint256 public mainnetFork;
    uint256 public mainnetForkBlock = 22508883 - 6500 * 90; // latest alchemy block - 90 days

    // Fuzzing bounds
    uint256 constant MIN_DEPOSIT = 1e15; // 0.001 R_ETH minimum
    uint256 constant MAX_DEPOSIT = 10000e18; // 10,000 R_ETH maximum
    uint256 constant MIN_EXCHANGE_RATE_CHANGE = 10000; // 1%
    uint256 constant MAX_EXCHANGE_RATE_CHANGE = 200000; // 200%
    uint256 constant BASIS_POINTS = 10000;

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

        // Now use that address as our tokenizedStrategy
        tokenizedStrategy = YieldSkimmingTokenizedStrategy(address(implementation));

        // Set up addresses
        management = address(0x1);
        keeper = address(0x2);
        emergencyAdmin = address(0x3);
        donationAddress = address(0x4);

        // Deploy factory
        factory = new RocketPoolStrategyVaultFactory();

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
        strategy = RocketPoolStrategy(strategyAddress);
        vault = ITokenizedStrategy(address(strategy));

        // Label addresses for better trace outputs
        vm.label(address(strategy), "RocketPool");
        vm.label(address(factory), "YieldSkimmingVaultFactory");
        vm.label(R_ETH, "RocketPool Yield Vault");
        vm.label(TOKENIZED_STRATEGY_ADDRESS, "TokenizedStrategy");
        vm.label(management, "Management");
        vm.label(keeper, "Keeper");
        vm.label(emergencyAdmin, "Emergency Admin");
        vm.label(donationAddress, "Donation Address");
        vm.label(user, "Test User");

        // Airdrop rETH tokens to test user
        airdrop(ERC20(R_ETH), user, INITIAL_DEPOSIT);

        // Approve strategy to spend user's tokens
        vm.startPrank(user);
        ERC20(R_ETH).approve(address(strategy), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Test that the strategy is properly initialized
    function testInitializationRocketPool() public view {
        assertEq(IERC4626(address(strategy)).asset(), R_ETH, "Yield vault address incorrect");
        assertEq(vault.management(), management, "Management address incorrect");
        assertEq(vault.keeper(), keeper, "Keeper address incorrect");
        assertEq(vault.emergencyAdmin(), emergencyAdmin, "Emergency admin incorrect");
        assertGt(strategy.getLastReportedExchangeRate(), 0, "Last reported exchange rate should be initialized");
    }

    /// @notice Fuzz test for depositing assets into the strategy
    function testFuzzDepositRocketPool(uint256 depositAmount) public {
        // Bound the deposit amount to reasonable values
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);

        // Initial balances
        uint256 initialUserBalance = ERC20(R_ETH).balanceOf(user);

        // Ensure user has enough balance
        if (initialUserBalance < depositAmount) {
            airdrop(ERC20(R_ETH), user, depositAmount);
            initialUserBalance = ERC20(R_ETH).balanceOf(user);
        }

        // Deposit assets
        vm.startPrank(user);
        // approve the strategy to spend the user's tokens
        ERC20(R_ETH).approve(address(strategy), depositAmount);
        uint256 sharesReceived = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Verify balances after deposit
        assertEq(
            ERC20(R_ETH).balanceOf(user),
            initialUserBalance - depositAmount,
            "User balance not reduced correctly"
        );

        assertGt(sharesReceived, 0, "No shares received from deposit");
        assertGt(strategy.balanceOfShares(), 0, "Strategy should have deployed assets to yield vault");
    }

    /// @notice Fuzz test for withdrawing assets from the strategy
    function testFuzzWithdraw(uint256 depositAmount, uint256 withdrawPercentage) public {
        // Bound the inputs
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);
        withdrawPercentage = bound(withdrawPercentage, 1, 100); // 1% to 100%

        // Ensure user has enough balance
        if (ERC20(R_ETH).balanceOf(user) < depositAmount) {
            airdrop(ERC20(R_ETH), user, depositAmount);
        }

        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);

        // Initial balances before withdrawal
        uint256 initialUserBalance = ERC20(R_ETH).balanceOf(user);
        uint256 initialShareBalance = vault.balanceOf(user);

        // Calculate withdrawal amount based on percentage
        uint256 withdrawAmount = (depositAmount * withdrawPercentage) / 100;

        // Ensure withdrawal amount doesn't exceed available
        uint256 maxWithdraw = vault.maxWithdraw(user);
        if (withdrawAmount > maxWithdraw) {
            withdrawAmount = maxWithdraw;
        }

        uint256 sharesToBurn = vault.previewWithdraw(withdrawAmount);
        uint256 assetsReceived = vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();

        // Verify balances after withdrawal
        assertEq(
            ERC20(R_ETH).balanceOf(user),
            initialUserBalance + withdrawAmount,
            "User didn't receive correct assets"
        );
        assertEq(vault.balanceOf(user), initialShareBalance - sharesToBurn, "Shares not burned correctly");
        assertEq(assetsReceived, withdrawAmount, "Incorrect amount of assets received");
    }

    /// @notice Fuzz test for harvesting functionality with profit simulation
    function testFuzzHarvestWithProfitRocketPool(uint256 depositAmount, uint256 profitPercentage) public {
        // Bound the inputs
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);
        profitPercentage = bound(profitPercentage, 100, 10000); // 1% to 100% // or else will revert on health check

        // Ensure user has enough balance
        if (ERC20(R_ETH).balanceOf(user) < depositAmount) {
            airdrop(ERC20(R_ETH), user, depositAmount);
        }

        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Check initial state
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 initialExchangeRate = strategy.getLastReportedExchangeRate();

        // Simulate exchange rate increase
        uint256 newExchangeRate = (initialExchangeRate * profitPercentage) / 10000;

        // the actual yield vault's getExchangeRate
        vm.mockCall(R_ETH, abi.encodeWithSignature("getExchangeRate()"), abi.encode(newExchangeRate));

        uint256 donationAddressBalanceBefore = ERC20(address(strategy)).balanceOf(donationAddress);

        // Prepare to call report and expect event
        vm.startPrank(keeper);

        // Call report and capture the returned values
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();

        // Clear mock to avoid interference with other tests
        vm.clearMockedCalls();

        // Assert profit and loss
        if (profitPercentage > 10000) {
            assertGt(profit, 0, "Profit should be positive");
        }
        assertEq(loss, 0, "There should be no loss");

        uint256 donationAddressBalanceAfter = ERC20(address(strategy)).balanceOf(donationAddress);

        // donation address should have received the profit
        if (profit > 0) {
            assertGt(
                donationAddressBalanceAfter,
                donationAddressBalanceBefore,
                "Donation address should have received profit"
            );
        }

        // Check total assets after harvest
        uint256 totalAssetsAfter = vault.totalAssets();

        assertEq(totalAssetsAfter, totalAssetsBefore, "Total assets should not change after harvest");
    }

    /// @notice Fuzz test for multiple users with fair profit distribution
    function testFuzzMultipleUserProfitDistributionRocketPool(
        uint256 depositAmount1,
        uint256 depositAmount2,
        uint256 firstYieldIncrease,
        uint256 secondYieldIncrease
    ) public {
        TestState memory state;

        // Bound the inputs
        depositAmount1 = bound(depositAmount1, MIN_DEPOSIT, MAX_DEPOSIT);
        depositAmount2 = bound(depositAmount2, MIN_DEPOSIT, MAX_DEPOSIT);
        firstYieldIncrease = bound(firstYieldIncrease, 10100, 20000); // 1% to 100% increase
        secondYieldIncrease = bound(secondYieldIncrease, 10100, 15000); // 1% to 50% increase

        // First user deposits
        state.user1 = user; // Reuse existing test user
        state.user2 = address(0x5678);
        state.depositAmount1 = depositAmount1;
        state.depositAmount2 = depositAmount2;

        // Ensure user1 has enough balance
        if (ERC20(R_ETH).balanceOf(state.user1) < state.depositAmount1) {
            airdrop(ERC20(R_ETH), state.user1, state.depositAmount1);
        }

        // Get initial exchange rate
        state.initialExchangeRate = strategy.getLastReportedExchangeRate();

        vm.startPrank(state.user1);
        vault.deposit(state.depositAmount1, state.user1);
        vm.stopPrank();

        // Generate yield for first user
        state.newExchangeRate1 = (state.initialExchangeRate * firstYieldIncrease) / 10000;

        // Check donation address balance before harvest
        state.donationBalanceBefore1 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Mock the yield vault's getExchangeRate instead of strategy's internal method
        vm.mockCall(R_ETH, abi.encodeWithSignature("getExchangeRate()"), abi.encode(state.newExchangeRate1));

        // Harvest to realize profit
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // Check donation address balance after harvest
        state.donationBalanceAfter1 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Verify donation address received profit
        if (firstYieldIncrease > 10000) {
            assertGt(
                state.donationBalanceAfter1,
                state.donationBalanceBefore1,
                "Donation address should have received profit after first harvest"
            );
        }

        // Second user deposits after profit
        vm.startPrank(address(this));
        airdrop(ERC20(R_ETH), state.user2, state.depositAmount2);
        vm.stopPrank();

        vm.startPrank(state.user2);
        ERC20(R_ETH).approve(address(strategy), type(uint256).max);
        vault.deposit(state.depositAmount2, state.user2);
        vm.stopPrank();

        // Clear mock
        vm.clearMockedCalls();

        // Generate more yield after second user joined
        state.newExchangeRate2 = (state.newExchangeRate1 * secondYieldIncrease) / 10000;

        // Check donation address balance before second harvest
        state.donationBalanceBefore2 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Mock the yield vault's getExchangeRate
        vm.mockCall(R_ETH, abi.encodeWithSignature("getExchangeRate()"), abi.encode(state.newExchangeRate2));

        // Harvest again
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // Clear mock
        vm.clearMockedCalls();

        // Check donation address balance after second harvest
        state.donationBalanceAfter2 = ERC20(address(strategy)).balanceOf(donationAddress);

        // Verify donation address received more profit
        if (secondYieldIncrease > 10000) {
            assertGt(
                state.donationBalanceAfter2,
                state.donationBalanceBefore2,
                "Donation address should have received profit after second harvest"
            );
        }

        // Both users withdraw
        vm.startPrank(state.user1);
        state.user1Shares = vault.balanceOf(state.user1);
        if (state.user1Shares > 0) {
            state.user1Assets = vault.redeem(vault.balanceOf(state.user1), state.user1, state.user1);
        }
        vm.stopPrank();

        vm.startPrank(state.user2);
        state.user2Shares = vault.balanceOf(state.user2);
        if (state.user2Shares > 0) {
            state.user2Assets = vault.redeem(vault.balanceOf(state.user2), state.user2, state.user2);
        }
        vm.stopPrank();

        // redeem the shares of the donation address
        vm.startPrank(donationAddress);
        uint256 donationShares = vault.balanceOf(donationAddress);
        if (donationShares > 0) {
            vault.redeem(donationShares, donationAddress, donationAddress);
        }
        vm.stopPrank();

        // User 1 deposited before first yield accrual, so should have earned more
        assertApproxEqRel(
            state.user1Assets * state.newExchangeRate2,
            state.depositAmount1 * state.initialExchangeRate,
            0.00001e18, // 0.001% tolerance
            "User 1 should receive deposit adjusted for exchange rate change"
        );

        // User 2 deposited after first yield accrual but before second
        assertApproxEqRel(
            state.user2Assets * state.newExchangeRate2,
            state.depositAmount2 * state.newExchangeRate1,
            0.0001e18, // 0.01% tolerance
            "User 2 should receive deposit adjusted for exchange rate change"
        );
    }

    /// @notice Fuzz test for the harvesting functionality
    function testFuzzHarvestRocketPool(uint256 depositAmount) public {
        // Bound the deposit amount
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);

        // Ensure user has enough balance
        if (ERC20(R_ETH).balanceOf(user) < depositAmount) {
            airdrop(ERC20(R_ETH), user, depositAmount);
        }

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

        // Verify exchange rate is updated
        assertEq(newExchangeRate, initialExchangeRate, "Exchange rate should be updated after harvest");

        // Verify total assets after harvest
        assertGe(newTotalAssets, initialAssets, "Total assets should not decrease after harvest");
    }

    /// @notice Fuzz test for emergency exit functionality
    function testFuzzEmergencyExit(uint256 depositAmount) public {
        // Bound the deposit amount
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);

        // Ensure user has enough balance
        if (ERC20(R_ETH).balanceOf(user) < depositAmount) {
            airdrop(ERC20(R_ETH), user, depositAmount);
        }

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
        assertApproxEqRel(
            assetsReceived,
            depositAmount,
            0.0001e18, // 0.01% tolerance
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
        strategy.sweep(R_ETH);
        vm.stopPrank();
    }

    /// @notice Fuzz test for exchange rate tracking and yield calculation
    function testFuzzExchangeRateTracking(uint256 depositAmount, uint256 rateIncreasePercentage) public {
        // Bound the inputs
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);
        rateIncreasePercentage = bound(rateIncreasePercentage, 10100, 20000); // 1% to 100% increase

        // Ensure user has enough balance
        if (ERC20(R_ETH).balanceOf(user) < depositAmount) {
            airdrop(ERC20(R_ETH), user, depositAmount);
        }

        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Get initial exchange rate
        uint256 initialExchangeRate = strategy.getLastReportedExchangeRate();

        // Skip time and mine blocks
        skip(30 days);
        vm.roll(block.number + 6500 * 30);

        // Simulate exchange rate increase
        uint256 newExchangeRate = (initialExchangeRate * rateIncreasePercentage) / 10000;

        // Mock the getExchangeRate function
        vm.mockCall(R_ETH, abi.encodeWithSignature("getExchangeRate()"), abi.encode(newExchangeRate));

        // Report to capture yield
        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();

        // Clear mock
        vm.clearMockedCalls();

        // Log and verify profit
        if (rateIncreasePercentage > 10000) {
            assertGt(profit, 0, "Should have captured profit from exchange rate increase");
        }
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

    /// @notice Fuzz test for balance of asset and shares
    function testFuzzBalanceOfAssetAndShares(uint256 depositAmount) public {
        // Bound the deposit amount
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);

        // Ensure user has enough balance
        if (ERC20(R_ETH).balanceOf(user) < depositAmount) {
            airdrop(ERC20(R_ETH), user, depositAmount);
        }

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

    /// @notice Fuzz test for health check when profit limit is exceeded
    function testFuzzHealthCheckProfitLimitExceeded(uint256 depositAmount, uint256 exchangeRateMultiplier) public {
        // Bound the inputs
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);
        exchangeRateMultiplier = bound(exchangeRateMultiplier, 201, 1000); // 201% to 1000%

        // Ensure user has enough balance
        if (ERC20(R_ETH).balanceOf(user) < depositAmount) {
            airdrop(ERC20(R_ETH), user, depositAmount);
        }

        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // First report: sets doHealthCheck = true, does NOT check
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // Mock an extreme exchange rate increase
        uint256 initialExchangeRate = strategy.getLastReportedExchangeRate();
        uint256 newExchangeRate = (initialExchangeRate * exchangeRateMultiplier) / 100;
        vm.mockCall(R_ETH, abi.encodeWithSignature("getExchangeRate()"), abi.encode(newExchangeRate));

        // Second report: should revert if profit limit is exceeded
        vm.startPrank(keeper);
        // Only expect revert if the profit exceeds the limit (default 100%)
        if (exchangeRateMultiplier > 200) {
            vm.expectRevert("healthCheck: profit limit exceeded");
        }
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
        vm.mockCall(R_ETH, abi.encodeWithSignature("getExchangeRate()"), abi.encode((initialExchangeRate * 10)));

        // report
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();

        // check the do health check
        assertEq(strategy.doHealthCheck(), true);
    }

    // Fuzz test for changing profit limit ratio
    function testFuzzChangeProfitLimitRatio(uint16 newProfitLimitRatio) public {
        // Bound to valid range (1 to 10000 basis points)
        vm.assume(newProfitLimitRatio > 0 && newProfitLimitRatio <= 10000);

        vm.startPrank(management);
        strategy.updateProfitLimitRatio(newProfitLimitRatio);
        vm.stopPrank();

        // check the profit limit ratio
        assertEq(strategy.getProfitLimitRatio(), newProfitLimitRatio);
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
}
