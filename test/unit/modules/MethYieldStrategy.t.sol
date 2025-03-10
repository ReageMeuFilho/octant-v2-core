// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../Base.t.sol";
import { MethYieldStrategy } from "src/dragons/modules/MethYieldStrategy.sol";

import { YieldBearingDragonTokenizedStrategy } from "src/dragons/vaults/YieldBearingDragonTokenizedStrategy.sol";
import { TokenizedStrategy__DepositMoreThanMax } from "src/errors.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { IDragonTokenizedStrategy } from "src/interfaces/IDragonTokenizedStrategy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { MockMETH } from "../../mocks/MockMETH.sol";
import { MockMantleStaking } from "../../mocks/MockMantleStaking.sol";
import { MockMethYieldStrategy } from "../../mocks/MockMethYieldStrategy.sol";

/**
 * @title MethYieldStrategyTest
 * @notice Unit tests for the MethYieldStrategy
 * @dev Uses mock contracts to simulate Mantle's staking and mETH behavior
 */
contract MethYieldStrategyTest is BaseTest {
    // Strategy parameters
    address management = makeAddr("management");
    address keeper = makeAddr("keeper");
    address dragonRouter = makeAddr("dragonRouter");
    address regenGovernance = makeAddr("regenGovernance");

    // Test wallets
    address user1;
    address user2;
    address deployer;

    // Mock contracts
    MockMETH mockMeth;
    MockMantleStaking mockMantleStaking;

    // Test environment
    testTemps temps;
    address tokenizedStrategyImplementation;
    address moduleImplementation;
    MethYieldStrategy strategy;

    // The actual constant addresses for reference
    address constant REAL_MANTLE_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Test parameters
    uint256 internal constant MAX_BPS = 10_000;
    // Fixed parameters for yield test
    uint256 internal constant EXCHANGE_RATE_INCREASE_PCT = 5;
    uint256 internal constant BASE_RATE = 1e18; // 1:1 ratio initially

    // State tracking for multi-cycle tests
    uint256 internal currentCycleRate;
    uint256 internal currentTotalAssets;

    function setUp() public {
        _configure(true, "eth");

        // Set up users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        deployer = makeAddr("deployer");
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(deployer, 10 ether);

        // Deploy mock contracts
        mockMeth = new MockMETH();
        mockMantleStaking = new MockMantleStaking(address(mockMeth));

        // Configure mock relationships
        mockMeth.setMantleStaking(address(mockMantleStaking));
        mockMantleStaking.setExchangeRate(1e18); // 1:1 for simplicity
        mockMantleStaking.setMETHToken(address(mockMeth));

        // Fund mock staking contract with ETH
        vm.deal(address(mockMantleStaking), 100 ether);

        // Setup mocks at the real address with etch
        vm.etch(REAL_MANTLE_STAKING, address(mockMantleStaking).code);
        vm.startPrank(address(this));
        // Initialize exchange rate at the real address
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setExchangeRate(1e18);
        // Set the mETH token reference in the staking contract
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setMETHToken(address(mockMeth));
        vm.stopPrank();

        // Fund the real address with ETH
        vm.deal(REAL_MANTLE_STAKING, 100 ether);

        // Create implementations
        moduleImplementation = address(new MockMethYieldStrategy());
        tokenizedStrategyImplementation = address(new YieldBearingDragonTokenizedStrategy());

        uint256 maxReportDelay = 7 days;

        // Use _testTemps to set up the test environment
        temps = _testTemps(
            moduleImplementation,
            abi.encode(
                tokenizedStrategyImplementation,
                management,
                keeper,
                dragonRouter,
                maxReportDelay,
                regenGovernance,
                address(mockMeth)
            )
        );

        // Cast the module to our strategy type
        strategy = MethYieldStrategy(payable(temps.module));

        // Set mock addresses in the strategy implementation
        MockMethYieldStrategy(payable(temps.module)).setMockAddresses(address(mockMantleStaking), address(mockMeth));

        // Mint tokens directly to the strategy for simplicity in testing
        mockMeth.mint(address(strategy), 10 ether);

        // Force initialize the strategy's accounting to recognize the tokens
        vm.startPrank(keeper);
        ITokenizedStrategy(address(strategy)).report();
        vm.stopPrank();

        // Verify the strategy has received the tokens and initialized its accounting
        assertEq(mockMeth.balanceOf(address(strategy)), 10 ether, "Strategy should have 10 mETH");
        assertEq(ITokenizedStrategy(address(strategy)).totalAssets(), 10 ether, "Total assets should be 10 mETH");
    }

    /**
     * @notice Test basic initialization and constants
     */
    function testInitialization() public view {
        assertEq(address(strategy.MANTLE_STAKING()), REAL_MANTLE_STAKING, "Incorrect Mantle staking address");
        assertEq(ITokenizedStrategy(address(strategy)).management(), management, "Incorrect management address");
        assertEq(ITokenizedStrategy(address(strategy)).keeper(), keeper, "Incorrect keeper address");
        assertEq(ITokenizedStrategy(address(strategy)).dragonRouter(), dragonRouter, "Incorrect dragon router address");
    }

    /**
     * @notice Helper function to process a harvest cycle and return key values
     * @return profit The profit generated in this cycle
     * @return routerBalance The router balance after harvest
     */
    function _processHarvestCycle() internal returns (uint256 profit, uint256 routerBalance) {
        // Calculate new exchange rate with increase
        uint256 newRate = currentCycleRate == 0
            ? BASE_RATE + ((BASE_RATE * EXCHANGE_RATE_INCREASE_PCT) / 100)
            : currentCycleRate + ((currentCycleRate * EXCHANGE_RATE_INCREASE_PCT) / 100);

        // Set the new rate in the mock
        mockMantleStaking.setExchangeRate(newRate);

        // Get the actual mETH balance
        uint256 actualMethBalance = mockMeth.balanceOf(address(strategy));

        // Calculate ETH value before and after rate change - replicate the exact calculation in the strategy
        uint256 previousEthValue = currentCycleRate == 0
            ? actualMethBalance // 1:1 initially
            : (actualMethBalance * currentCycleRate) / 1e18;
        uint256 newEthValue = (actualMethBalance * newRate) / 1e18;

        // Profit in ETH terms
        uint256 expectedProfitInEth = newEthValue - previousEthValue;

        // Convert ETH profit to mETH at new exchange rate - exactly as the strategy does
        uint256 expectedProfitInMeth = (expectedProfitInEth * 1e18) / newRate;

        // Trigger harvest/report
        vm.prank(keeper);
        (profit, ) = ITokenizedStrategy(address(strategy)).report();

        // Assert that the profit matches our calculation exactly
        assertEq(profit, expectedProfitInMeth, "Profit calculation incorrect");

        // Verify exchange rate was updated
        assertEq(strategy.lastExchangeRate(), newRate, "Exchange rate should be updated");

        // Update current rate for next cycle
        currentCycleRate = newRate;

        // Return the router's new balance
        routerBalance = ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter);
    }

    /**
     * @notice Helper function to process a withdrawal and return key values
     * @param _routerBalanceBefore Router balance before withdrawal
     * @return assetsReceived Assets received from withdrawal
     * @return routerBalanceAfter Router balance after withdrawal
     */
    function _processWithdrawal(
        uint256 _routerBalanceBefore
    ) internal returns (uint256 assetsReceived, uint256 routerBalanceAfter) {
        // Get mETH balance of router before withdrawal
        uint256 mEthBalanceBeforeWithdrawal = mockMeth.balanceOf(dragonRouter);

        // Withdraw half of the shares
        uint256 sharesToWithdraw = _routerBalanceBefore / 2;

        // Prank as dragon router and perform withdraw
        vm.prank(dragonRouter);
        assetsReceived = ITokenizedStrategy(address(strategy)).redeem(
            sharesToWithdraw,
            dragonRouter,
            dragonRouter,
            MAX_BPS // Allow max loss (not relevant for this test)
        );

        // Verify withdrawal succeeded
        assertGt(assetsReceived, 0, "Router should have received assets");
        assertEq(
            mockMeth.balanceOf(dragonRouter),
            mEthBalanceBeforeWithdrawal + assetsReceived,
            "Router mETH balance should increase by withdrawn amount"
        );

        routerBalanceAfter = ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter);
        assertEq(
            routerBalanceAfter,
            _routerBalanceBefore - sharesToWithdraw,
            "Router should have fewer shares after withdrawal"
        );
    }

    /**
     * @notice Test multiple harvest cycles with exchange rate changes
     */
    function testMultipleHarvestCycles() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // Verify initial balance
        uint256 initialBalance = mockMeth.balanceOf(address(strategy));
        assertEq(initialBalance, 10 ether, "Initial balance should be 10 mETH");

        // ----- CYCLE 1 -----
        (uint256 profitCycle1, ) = _processHarvestCycle();

        // Get total assets after first cycle
        uint256 totalAssetsAfterCycle1 = ITokenizedStrategy(address(strategy)).totalAssets();
        uint256 expectedTotalAssetsAfterCycle1 = initialBalance + profitCycle1;
        assertEq(totalAssetsAfterCycle1, expectedTotalAssetsAfterCycle1, "Total assets incorrect after cycle 1");

        // ----- CYCLE 2 -----
        (uint256 profitCycle2, uint256 routerBalanceAfterCycle2) = _processHarvestCycle();

        // Verify total assets increased
        uint256 totalAssetsAfterCycle2 = ITokenizedStrategy(address(strategy)).totalAssets();
        uint256 expectedTotalAssetsAfterCycle2 = expectedTotalAssetsAfterCycle1 + profitCycle2;
        assertEq(totalAssetsAfterCycle2, expectedTotalAssetsAfterCycle2, "Total assets incorrect after cycle 2");

        // ----- WITHDRAWAL -----
        // We're only interested in the router balance after withdrawal
        (, uint256 routerBalanceAfterWithdrawal) = _processWithdrawal(routerBalanceAfterCycle2);

        // Calculate expected router balance after withdrawal
        uint256 expectedRouterBalanceAfterWithdrawal = routerBalanceAfterCycle2 / 2;
        assertEq(
            routerBalanceAfterWithdrawal,
            expectedRouterBalanceAfterWithdrawal,
            "Router balance after withdrawal incorrect"
        );

        // Get total assets after withdrawal
        uint256 totalAssetsAfterWithdrawal = ITokenizedStrategy(address(strategy)).totalAssets();

        // ----- CYCLE 3 -----
        (uint256 profitCycle3, ) = _processHarvestCycle();

        // Verify profit was generated in cycle 3
        assertGt(profitCycle3, 0, "No profit generated in cycle 3");

        // Verify total assets increased - using totalAssetsAfterWithdrawal as the base
        uint256 totalAssetsAfterCycle3 = ITokenizedStrategy(address(strategy)).totalAssets();
        uint256 expectedTotalAssetsAfterCycle3 = totalAssetsAfterWithdrawal + profitCycle3;
        assertEq(totalAssetsAfterCycle3, expectedTotalAssetsAfterCycle3, "Total assets incorrect after cycle 3");
    }

    /**
     * @notice Test exchange rate stays the same (no profit scenario)
     */
    function testNoExchangeRateChange() public {
        // Verify initial balance
        uint256 initialBalance = mockMeth.balanceOf(address(strategy));
        assertEq(initialBalance, 10 ether, "Initial balance should be 10 mETH");

        // Check initial router balance
        uint256 initialRouterBalance = ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter);

        // No change in exchange rate (stays at 1:1)

        // Trigger harvest/report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = ITokenizedStrategy(address(strategy)).report();

        // We expect no profit
        assertEq(profit, 0, "Profit should be zero");
        assertEq(loss, 0, "Loss should be zero");

        // Check that DragonRouter received no additional shares
        uint256 finalRouterBalance = ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter);
        assertEq(finalRouterBalance, initialRouterBalance, "Dragon router should not have received additional shares");
    }

    /**
     * @notice Test exchange rate decreases (loss scenario)
     */
    function testExchangeRateDecrease() public {
        // Verify initial balance
        uint256 initialBalance = mockMeth.balanceOf(address(strategy));
        assertEq(initialBalance, 10 ether, "Initial balance should be 10 mETH");

        // Decrease exchange rate by 5%
        mockMantleStaking.setExchangeRate(0.95e18);

        // Trigger harvest/report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = ITokenizedStrategy(address(strategy)).report();

        // We expect no profit, but also no loss due to how the strategy is implemented
        // The strategy simply updates the exchange rate and doesn't report a loss
        assertEq(profit, 0, "Profit should be zero");
        assertEq(loss, 0, "Loss should be zero");

        // Check that the exchange rate was updated
        assertEq(strategy.lastExchangeRate(), 0.95e18, "Exchange rate should be updated");
    }

    /**
     * @notice Test emergency withdrawal
     */
    function testEmergencyWithdraw() public {
        // Get the initial mETH balance in the strategy
        uint256 initialMethBalance = mockMeth.balanceOf(address(strategy));
        assertEq(initialMethBalance, 10 ether, "Strategy should start with 10 mETH");

        // Set temps.safe as the emergencyAdmin
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setEmergencyAdmin(temps.safe);

        // First shutdown the strategy
        vm.prank(temps.safe);
        ITokenizedStrategy(address(strategy)).shutdownStrategy();

        // Emergency withdraw to temps.safe (which is the emergency admin)
        vm.prank(temps.safe);
        (bool success, ) = address(strategy).call(
            abi.encodeWithSignature("emergencyWithdraw(uint256)", initialMethBalance)
        );
        assertTrue(success, "Emergency withdraw should succeed");

        // Verify mETH was sent to temps.safe (the emergency admin)
        uint256 strategyFinalMethBalance = mockMeth.balanceOf(address(strategy));
        assertLt(
            strategyFinalMethBalance,
            initialMethBalance,
            "Strategy should have less mETH after emergency withdraw"
        );

        // Verify that the emergencyAdmin received the funds
        uint256 safeBalance = mockMeth.balanceOf(temps.safe);
        assertGt(safeBalance, 0, "Emergency admin should have received mETH tokens");
    }

    /**
     * @notice Test that a depositor can withdraw the full ETH value including yield
     * when the exchange rate increases
     */
    function testDepositorWithdrawalAfterExchangeRateIncrease() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // First make sure dragon-only mode is disabled
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Create a separate depositor (different from the dragon router)
        address depositor = makeAddr("depositor");
        uint256 depositAmount = 10 ether;

        // Mint mETH to depositor
        mockMeth.mint(depositor, depositAmount);

        // Depositor approves and deposits mETH to the strategy
        vm.startPrank(depositor);
        mockMeth.approve(address(strategy), depositAmount);
        uint256 sharesMinted = IDragonTokenizedStrategy(address(strategy)).deposit(depositAmount, depositor);
        vm.stopPrank();

        // Verify depositor received shares
        uint256 depositorShares = ITokenizedStrategy(address(strategy)).balanceOf(depositor);
        assertEq(depositorShares, sharesMinted, "Depositor should have received shares");

        // Calculate initial ETH value (1:1 at start)
        uint256 initialEthValue = depositAmount; // 1:1 exchange rate

        // Increase the exchange rate
        uint256 newRate = BASE_RATE + ((BASE_RATE * EXCHANGE_RATE_INCREASE_PCT) / 100); // 5% increase
        mockMantleStaking.setExchangeRate(newRate);

        // Now let depositor withdraw without harvest (so no router profit has been taken)
        vm.startPrank(depositor);
        uint256 withdrawnMeth = ITokenizedStrategy(address(strategy)).redeem(
            depositorShares,
            depositor,
            depositor,
            MAX_BPS
        );
        vm.stopPrank();

        // Calculate ETH value of the withdrawn mETH (should be more than deposited because of exchange rate)
        uint256 withdrawnEthValue = (withdrawnMeth * newRate) / 1e18;

        // With our exchange rate adjustments, the depositor should get back approximately
        // their original ETH value (10 ETH), not the increased value
        uint256 expectedWithdrawnEthValue = initialEthValue;

        // We should allow for some small rounding errors
        uint256 tolerance = 1e16; // 0.01 ETH tolerance
        assertApproxEqAbs(
            withdrawnEthValue,
            expectedWithdrawnEthValue,
            tolerance,
            "With exchange rate adjustments, depositor should get back original ETH value"
        );
    }

    /**
     * @notice Test that a depositor gets their original ETH value back after yield receiver has taken their yield
     * due to the exchange rate adjustment in our _convertToShares and _convertToAssets functions
     */
    function testDepositorWithdrawalAfterYieldWithdrawal() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // First make sure dragon-only mode is disabled
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Create a separate depositor (different from the dragon router)
        address depositor = makeAddr("depositor");
        uint256 depositAmount = 10 ether;

        // Mint mETH to depositor
        mockMeth.mint(depositor, depositAmount);

        // Depositor approves and deposits mETH to the strategy
        vm.startPrank(depositor);
        mockMeth.approve(address(strategy), depositAmount);
        uint256 sharesMinted = IDragonTokenizedStrategy(address(strategy)).deposit(depositAmount, depositor);
        vm.stopPrank();

        // Verify depositor received shares
        uint256 depositorShares = ITokenizedStrategy(address(strategy)).balanceOf(depositor);
        assertEq(depositorShares, sharesMinted, "Depositor should have received shares");

        // Calculate initial ETH value (1:1 at start)
        uint256 initialEthValue = depositAmount; // 1:1 exchange rate

        // Run a single harvest cycle to generate yield
        (uint256 profit, uint256 routerBalanceAfter) = _processHarvestCycle();

        // Verify profit was generated
        assertGt(profit, 0, "Harvest should generate profit");
        assertGt(routerBalanceAfter, 0, "Router should have received shares");

        // Get the new exchange rate
        uint256 newExchangeRate = strategy.lastExchangeRate();
        assertGt(newExchangeRate, 1e18, "Exchange rate should have increased");

        // Dragon router (yield receiver) withdraws all its profit shares
        vm.prank(dragonRouter);
        uint256 assetsReceived = ITokenizedStrategy(address(strategy)).redeem(
            routerBalanceAfter,
            dragonRouter,
            dragonRouter,
            MAX_BPS
        );

        // Verify yield receiver got assets
        assertGt(assetsReceived, 0, "Router should have received assets");

        // Verify router has no shares left
        assertEq(ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter), 0, "Router should have no shares left");

        // Now check if the depositor can withdraw and get the original ETH value
        vm.startPrank(depositor);
        uint256 withdrawnMeth = ITokenizedStrategy(address(strategy)).redeem(
            depositorShares,
            depositor,
            depositor,
            MAX_BPS
        );
        vm.stopPrank();

        // Calculate ETH value of the withdrawn mETH
        uint256 withdrawnEthValue = (withdrawnMeth * newExchangeRate) / 1e18;

        // With our exchange rate adjustments in _convertToShares and _convertToAssets,
        // the depositor should get approximately their original ETH value back (10 ETH)
        // rather than experiencing a loss due to yield withdrawal

        // Allow for rounding errors - a 0.3% tolerance is reasonable for ERC4626 math
        uint256 tolerance = 0.03 ether; // 0.03 ETH tolerance = 0.3% of 10 ETH
        assertApproxEqAbs(
            withdrawnEthValue,
            initialEthValue,
            tolerance,
            "With exchange rate adjustments, depositor should get back original ETH value"
        );
    }

    /**
     * @notice Test that a depositor gets back their original ETH value after a harvest cycle
     * when the exchange rate increases but before router withdraws yield
     */
    function testWithdrawalAfterHarvest() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // First make sure dragon-only mode is disabled
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Create a separate depositor (different from the dragon router)
        address depositor = makeAddr("depositor");
        uint256 depositAmount = 10 ether;

        // Mint mETH to depositor
        mockMeth.mint(depositor, depositAmount);

        // Depositor approves and deposits mETH to the strategy
        vm.startPrank(depositor);
        mockMeth.approve(address(strategy), depositAmount);
        uint256 sharesMinted = IDragonTokenizedStrategy(address(strategy)).deposit(depositAmount, depositor);
        vm.stopPrank();

        // Verify depositor received shares
        uint256 depositorShares = ITokenizedStrategy(address(strategy)).balanceOf(depositor);
        assertEq(depositorShares, sharesMinted, "Depositor should have received shares");

        // Calculate initial ETH value (1:1 at start)
        uint256 initialEthValue = depositAmount; // 1:1 exchange rate

        // Run a single harvest cycle to generate yield
        (uint256 profit, uint256 routerBalanceAfter) = _processHarvestCycle();

        // Verify profit was generated
        assertGt(profit, 0, "Harvest should generate profit");
        assertGt(routerBalanceAfter, 0, "Router should have received shares");

        // Get the new exchange rate
        uint256 newExchangeRate = strategy.lastExchangeRate();
        assertGt(newExchangeRate, 1e18, "Exchange rate should have increased");

        // Now have the depositor withdraw their shares
        vm.startPrank(depositor);
        uint256 withdrawnMeth = ITokenizedStrategy(address(strategy)).redeem(
            depositorShares,
            depositor,
            depositor,
            MAX_BPS
        );
        vm.stopPrank();

        // Calculate ETH value of the withdrawn mETH
        uint256 withdrawnEthValue = (withdrawnMeth * newExchangeRate) / 1e18;

        // With our exchange rate adjustments in _convertToShares and _convertToAssets,
        // the depositor should get approximately their original ETH value back (10 ETH)

        // Allow for rounding errors - a 0.3% tolerance is reasonable for ERC4626 math
        uint256 tolerance = 0.03 ether; // 0.03 ETH tolerance = 0.3% of 10 ETH
        assertApproxEqAbs(
            withdrawnEthValue,
            initialEthValue,
            tolerance,
            "With exchange rate adjustments, depositor should get back original ETH value"
        );
    }
}
