// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "../Base.t.sol";
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
import { console } from "forge-std/console.sol";
import { IYieldBearingDragonTokenizedStrategy } from "src/interfaces/IYieldBearingDragonTokenizedStrategy.sol";

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
    uint256 internal constant ZERO_BPS = 0;
    // Fixed parameters for yield test
    uint256 internal constant EXCHANGE_RATE_INCREASE_PCT = 20;
    uint256 internal constant BASE_RATE = 1e18; // 1:1 ratio initially

    // State tracking for multi-cycle tests
    uint256 internal currentCycleRate;
    uint256 internal currentTotalAssets;

    function setUp() public {
        _configure(false, "eth");

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

        // Mint tokens to the temps.safe address instead of directly to the strategy
        mockMeth.mint(temps.safe, 10 ether);

        // Deposit using the temps.safe address which should have operator permissions
        vm.startPrank(temps.safe);
        mockMeth.approve(address(strategy), 10 ether);
        ITokenizedStrategy(address(strategy)).deposit(10 ether, temps.safe);
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
    function _processHarvestCycle() internal returns (uint256 profit, uint256 routerBalance, uint256 newRate) {
        // Calculate new exchange rate with increase
        newRate = currentCycleRate == 0
            ? BASE_RATE + ((BASE_RATE * EXCHANGE_RATE_INCREASE_PCT) / 100)
            : currentCycleRate + ((currentCycleRate * EXCHANGE_RATE_INCREASE_PCT) / 100);

        // Set the new rate in the mock
        mockMantleStaking.setExchangeRate(newRate);

        // get available yield
        uint256 availableYield = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();

        // Get the actual mETH balance
        uint256 actualMethBalance = mockMeth.balanceOf(address(strategy)) - availableYield;

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
     * @param _shareOwner Owner of the shares to withdraw
     * @param _shareAmount Amount of shares to withdraw (if 0, will withdraw half of owner's balance)
     * @param _recipient Recipient of the withdrawn assets
     * @param _maxLoss Maximum loss to accept (in basis points)
     * @return assetsReceived Assets received from withdrawal
     * @return sharesRemaining Shares remaining after withdrawal
     */
    function _processWithdrawal(
        address _shareOwner,
        uint256 _shareAmount,
        address _recipient,
        uint256 _maxLoss
    ) internal returns (uint256 assetsReceived, uint256 sharesRemaining) {
        // Get initial balances
        uint256 initialRecipientBalance = mockMeth.balanceOf(_recipient);
        uint256 initialOwnerShares = ITokenizedStrategy(address(strategy)).balanceOf(_shareOwner);

        // Determine shares to withdraw
        uint256 sharesToWithdraw = _shareAmount > 0 ? _shareAmount : initialOwnerShares / 2;
        require(sharesToWithdraw <= initialOwnerShares, "Not enough shares to withdraw");

        // First, run an external report call as the keeper to update the strategy state
        // This ensures the internal report call in redeem() won't fail due to permission issues
        vm.prank(keeper);
        ITokenizedStrategy(address(strategy)).report();

        // Now perform the withdrawal as the share owner
        vm.startPrank(_shareOwner);
        assetsReceived = ITokenizedStrategy(address(strategy)).redeem(
            sharesToWithdraw,
            _recipient,
            _shareOwner,
            _maxLoss
        );
        vm.stopPrank();

        // Verify withdrawal succeeded
        assertGt(assetsReceived, 0, "Should have received assets");
        assertEq(
            mockMeth.balanceOf(_recipient),
            initialRecipientBalance + assetsReceived,
            "Recipient's mETH balance should increase by withdrawn amount"
        );

        // Check remaining shares
        sharesRemaining = ITokenizedStrategy(address(strategy)).balanceOf(_shareOwner);
        assertEq(
            sharesRemaining,
            initialOwnerShares - sharesToWithdraw,
            "Owner should have fewer shares after withdrawal"
        );

        return (assetsReceived, sharesRemaining);
    }

    // /**
    //  * @notice Test the complete flow: deposit -> harvest -> redeemYield -> redeem
    //  * Verifies that after all operations, the original depositor gets back their
    //  * initial ETH value when redeeming their shares
    //  */
    // function testDepositHarvestRedeemFlow() public {
    //     // Reset state tracking variables
    //     currentCycleRate = 0;

    //     // First make sure dragon-only mode is disabled
    //     bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
    //     if (isDragonOnly) {
    //         vm.prank(temps.safe);
    //         IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
    //     }

    //     // Create a separate depositor
    //     address depositor = makeAddr("depositor");
    //     uint256 depositAmount = 10 ether;

    //     // Mint mETH to depositor
    //     mockMeth.mint(depositor, depositAmount);

    //     console.log("before deposit");

    //     // STEP 1: DEPOSIT
    //     // Depositor approves and deposits mETH to the strategy
    //     vm.startPrank(depositor);
    //     mockMeth.approve(address(strategy), depositAmount);
    //     uint256 shares = IDragonTokenizedStrategy(address(strategy)).deposit(depositAmount, depositor);
    //     vm.stopPrank();

    //     console.log("after deposit");

    //     // Verify depositor received shares
    //     assertEq(
    //         ITokenizedStrategy(address(strategy)).balanceOf(depositor),
    //         shares,
    //         "Depositor should have received shares"
    //     );

    //     // STEP 2: HARVEST
    //     console.log("before harvest");
    //     (uint256 profit, uint256 routerShares, uint256 exchangeRate) = _processHarvestCycle();
    //     console.log("after harvest");

    //     // Verify profit was generated
    //     assertGt(profit, 0, "Harvest should generate profit");
    //     assertGt(routerShares, 0, "Router should have received shares");

    //     // STEP 3: REDEEM YIELD
    //     uint256 sharesToRedeem = routerShares / 2;
    //     uint256 balanceBefore = mockMeth.balanceOf(dragonRouter);

    //     // Redeem yield
    //     vm.prank(dragonRouter);
    //     uint256 yieldAssets = YieldBearingDragonTokenizedStrategy(address(strategy)).redeemYield(
    //         sharesToRedeem,
    //         dragonRouter,
    //         dragonRouter,
    //         ZERO_BPS
    //     );

    //     // Verify yield redemption worked
    //     assertGt(yieldAssets, 0, "Router should have received yield assets");
    //     assertEq(
    //         mockMeth.balanceOf(dragonRouter),
    //         balanceBefore + yieldAssets,
    //         "Router's mETH balance should increase by yield amount"
    //     );

    //     // STEP 4: PREPARE FOR DEPOSITOR REDEEM
    //     // Call report as the keeper
    //     vm.prank(keeper);
    //     ITokenizedStrategy(address(strategy)).report();

    //     // STEP 5: DEPOSITOR REDEEMS
    //     balanceBefore = mockMeth.balanceOf(depositor);

    //     vm.startPrank(depositor);
    //     uint256 assets = ITokenizedStrategy(address(strategy)).redeem(shares, depositor, depositor, ZERO_BPS);
    //     vm.stopPrank();

    //     // Verify redemption succeeded
    //     assertGt(assets, 0, "Depositor should have received assets");
    //     assertEq(
    //         mockMeth.balanceOf(depositor),
    //         balanceBefore + assets,
    //         "Depositor's mETH balance should increase by redeemed amount"
    //     );

    //     // VERIFY ETH VALUES
    //     uint256 redeemedEthValue = (assets * exchangeRate) / 1e18;

    //     // With the exchange rate adjustments, the depositor should get back approximately
    //     // their original ETH value, not diminished by yield withdrawals
    //     uint256 tolerance = 0.01 ether; // 0.1% tolerance for rounding errors
    //     assertApproxEqAbs(
    //         redeemedEthValue,
    //         depositAmount, // original ETH value (1:1 at deposit time)
    //         tolerance,
    //         "Depositor should receive original ETH value when redeeming"
    //     );
    // }

    /**
     * @notice Test multiple harvest cycles with exchange rate changes
     */
    function testMultipleHarvestCycles() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // Verify initial balance
        assertEq(mockMeth.balanceOf(address(strategy)), 10 ether, "Initial balance should be 10 mETH");
        assertEq(
            YieldBearingDragonTokenizedStrategy(address(strategy)).totalEthValueDeposited(),
            10 ether,
            "Initial ETH value should be 10 ETH"
        );

        // ----- CYCLE 1 -----
        (uint256 profitCycle1, , ) = _processHarvestCycle();

        // Verify cycle 1 results
        assertEq(
            ITokenizedStrategy(address(strategy)).totalAssets(),
            10 ether + profitCycle1,
            "Total assets incorrect after cycle 1"
        );

        // ----- CYCLE 2 -----
        (uint256 profitCycle2, , uint256 exchangeRateCycle2) = _processHarvestCycle();

        // Verify cycle 2 results
        assertEq(
            ITokenizedStrategy(address(strategy)).totalAssets(),
            10 ether + profitCycle1 + profitCycle2,
            "Total assets incorrect after cycle 2"
        );

        // Store ETH value before withdrawal for comparison
        uint256 ethValueBeforeWithdrawal = YieldBearingDragonTokenizedStrategy(address(strategy))
            .totalEthValueDeposited();

        // ----- WITHDRAWAL -----
        // Get router's current shares and withdraw half
        uint256 routerSharesBefore = ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter);
        uint256 assetsToWithdraw = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();
        uint256 sharesToWithdraw = YieldBearingDragonTokenizedStrategy(address(strategy)).convertToShares(
            ((assetsToWithdraw / exchangeRateCycle2) * 1e18)
        );
        uint256 mEthBalanceBeforeWithdrawal = mockMeth.balanceOf(dragonRouter);

        // Perform the withdrawal
        vm.prank(dragonRouter);
        uint256 assetsReceived = YieldBearingDragonTokenizedStrategy(address(strategy)).redeemYield(
            sharesToWithdraw,
            dragonRouter,
            dragonRouter,
            0
        );

        // Verify withdrawal succeeded
        assertGt(assetsReceived, 0, "Router should have received assets");
        assertEq(
            mockMeth.balanceOf(dragonRouter),
            mEthBalanceBeforeWithdrawal + assetsReceived,
            "Router mETH balance should increase by withdrawn amount"
        );
        assertEq(
            ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter),
            routerSharesBefore - sharesToWithdraw,
            "Router should have fewer shares after withdrawal"
        );

        // Store total assets after withdrawal for cycle 3 comparison
        uint256 assetsAfterWithdrawal = ITokenizedStrategy(address(strategy)).totalAssets();

        // Get ETH value after withdrawal and validate it has NOT changed
        // When using redeemYield, totalEthValueDeposited should remain the same
        // since we're only withdrawing yield, not principal
        uint256 ethValueAfterWithdrawal = YieldBearingDragonTokenizedStrategy(address(strategy))
            .totalEthValueDeposited();

        // IMPORTANT: Verify the ETH value did NOT change after redeemYield
        assertEq(
            ethValueAfterWithdrawal,
            ethValueBeforeWithdrawal,
            "totalEthValueDeposited should remain unchanged after redeemYield"
        );

        // ----- CYCLE 3 -----
        (uint256 profitCycle3, , ) = _processHarvestCycle();

        // Verify profit was generated and total assets increased
        assertGt(profitCycle3, 0, "No profit generated in cycle 3");
        assertEq(
            ITokenizedStrategy(address(strategy)).totalAssets(),
            assetsAfterWithdrawal + profitCycle3,
            "Total assets incorrect after cycle 3"
        );

        // convert profitCycle3 assets to shares
        uint256 sharesToWithdrawCycle3 = YieldBearingDragonTokenizedStrategy(address(strategy)).convertToShares(
            profitCycle3
        );

        vm.prank(dragonRouter);
        YieldBearingDragonTokenizedStrategy(address(strategy)).redeemYield(
            sharesToWithdrawCycle3,
            dragonRouter,
            dragonRouter,
            ZERO_BPS
        );

        // Get the final ETH value
        uint256 finalEthValue = YieldBearingDragonTokenizedStrategy(address(strategy)).totalEthValueDeposited();

        // make sure final eth value is 10 ether - remaining yield * exchange rate
        assertApproxEqAbs(
            finalEthValue,
            10 ether,
            0.00000000001 ether, // precision of more than 10^-10
            "Final ETH value should be 10 ether - remaining yield * exchange rate"
        );
    }

    /**
     * @notice Test the new withdrawYield functionality
     */
    function testWithdrawYield() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // Process a harvest cycle to generate yield
        (uint256 profitGenerated, uint256 routerBalanceBefore, ) = _processHarvestCycle();

        // Verify profit was generated and Router received shares
        assertGt(profitGenerated, 0, "Should have generated profit");
        assertGt(routerBalanceBefore, 0, "Router should have received shares");

        // Get the available yield
        uint256 availableYield = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();
        assertEq(availableYield, profitGenerated, "Available yield should match profit generated");

        // Create a yield receiver
        address yieldReceiver = makeAddr("yieldReceiver");
        uint256 initialReceiverBalance = mockMeth.balanceOf(yieldReceiver);

        // Withdraw half of the available yield
        uint256 yieldToWithdraw = availableYield / 2;

        // Track router's shares before withdrawal
        uint256 routerSharesBefore = ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter);

        // Perform yield withdrawal
        vm.prank(dragonRouter);
        uint256 sharesWithdrawn = YieldBearingDragonTokenizedStrategy(address(strategy)).withdrawYield(
            yieldToWithdraw,
            yieldReceiver,
            dragonRouter,
            ZERO_BPS
        );

        // Verify yield receiver got the tokens
        assertEq(
            mockMeth.balanceOf(yieldReceiver),
            initialReceiverBalance + yieldToWithdraw,
            "Yield receiver should have received tokens"
        );

        // Verify router shares were burned/reduced
        uint256 routerSharesAfter = ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter);
        assertEq(
            routerSharesAfter,
            routerSharesBefore - sharesWithdrawn,
            "Router shares should be reduced by the withdrawn amount"
        );

        // Verify available yield was reduced
        uint256 availableYieldAfter = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();
        assertEq(availableYieldAfter, availableYield - yieldToWithdraw, "Available yield should have decreased");

        // Test withdrawing more than available yield (should revert)
        uint256 excessYield = availableYieldAfter + 1 ether;

        vm.prank(keeper);
        vm.expectRevert(IYieldBearingDragonTokenizedStrategy.InsufficientYieldAvailable.selector);
        YieldBearingDragonTokenizedStrategy(address(strategy)).withdrawYield(
            excessYield,
            yieldReceiver,
            dragonRouter,
            ZERO_BPS
        );

        // Test withdrawing to the zero address (should revert)
        vm.prank(keeper);
        vm.expectRevert(IYieldBearingDragonTokenizedStrategy.CannotWithdrawToZeroAddress.selector);
        YieldBearingDragonTokenizedStrategy(address(strategy)).withdrawYield(1, address(0), dragonRouter, ZERO_BPS);

        // Test withdrawing remaining yield
        vm.prank(dragonRouter);
        YieldBearingDragonTokenizedStrategy(address(strategy)).withdrawYield(
            availableYieldAfter,
            yieldReceiver,
            dragonRouter,
            ZERO_BPS
        );

        // Verify all yield is now withdrawn
        uint256 finalAvailableYield = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();
        assertEq(finalAvailableYield, 0, "Available yield should be zero after full withdrawal");
    }

    /**
     * @notice Test basic redeemYield functionality
     */
    function testRedeemYieldBasic() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // Process a harvest cycle to generate yield
        (uint256 profitGenerated, uint256 routerBalanceBefore, ) = _processHarvestCycle();

        // Verify profit was generated and Router received shares
        assertGt(profitGenerated, 0, "Should have generated profit");
        assertGt(routerBalanceBefore, 0, "Router should have received shares");

        // Get the available yield
        uint256 availableYield = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();
        assertEq(availableYield, profitGenerated, "Available yield should match profit generated");

        // Create yield receivers
        address yieldReceiver = makeAddr("yieldReceiver");

        // Redeem a small amount of shares
        uint256 smallShares = routerBalanceBefore / 10; // 10% of router shares

        // Track mETH balances before redemption
        uint256 receiverBalanceBefore = mockMeth.balanceOf(yieldReceiver);

        // Call redeemYield directly from the dragonRouter (owner of the shares)
        vm.prank(dragonRouter);
        uint256 assetsReceived = YieldBearingDragonTokenizedStrategy(address(strategy)).redeemYield(
            smallShares,
            yieldReceiver,
            dragonRouter,
            ZERO_BPS
        );

        // Verify receiver got tokens and router shares decreased
        assertGt(assetsReceived, 0, "Should have received assets");
        assertEq(
            mockMeth.balanceOf(yieldReceiver),
            receiverBalanceBefore + assetsReceived,
            "Receiver should have tokens"
        );
        assertEq(
            ITokenizedStrategy(address(strategy)).balanceOf(dragonRouter),
            routerBalanceBefore - smallShares,
            "Router shares should decrease by smallShares"
        );

        // Check available yield has been reduced
        uint256 availableYieldAfter = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();
        assertLt(availableYieldAfter, availableYield, "Available yield should have decreased");
    }

    /**
     * @notice Test redeemYield edge cases
     */
    function testRedeemYieldEdgeCases() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // Process a harvest cycle to generate yield
        (, /* uint256 profitGenerated */ uint256 routerBalanceBefore, ) = _processHarvestCycle();

        // Create yield receiver
        address yieldReceiver = makeAddr("yieldReceiver");

        // Test redeeming with a max loss parameter
        uint256 reducedShares = routerBalanceBefore / 5; // 20% of router shares
        uint256 maxLoss = 500; // 5% max loss

        // Call redeemYield directly from the dragonRouter (owner of the shares)
        vm.prank(dragonRouter);
        uint256 assetsReceived = YieldBearingDragonTokenizedStrategy(address(strategy)).redeemYield(
            reducedShares,
            yieldReceiver,
            dragonRouter,
            maxLoss
        );

        // Verify assets were received
        assertGt(assetsReceived, 0, "Should have received assets with max loss parameter");
    }

    /**
     * @notice Test redeemYield error cases
     */
    function testRedeemYieldErrorCases() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // Process a harvest cycle to generate yield
        (, /* uint256 profitGenerated */ uint256 routerBalanceBefore, ) = _processHarvestCycle();

        // Create yield receiver
        address yieldReceiver = makeAddr("yieldReceiver");

        // Case 1: Try to redeem more shares than the yield available allows
        // The YieldBearingDragonTokenizedStrategy checks if there's enough yield before attempting to burn shares
        uint256 tooManyShares = routerBalanceBefore * 2;

        // Call redeemYield from the dragonRouter but with too many shares (should revert with "Insufficient yield available")
        vm.prank(dragonRouter);
        vm.expectRevert(); // todo add error message
        YieldBearingDragonTokenizedStrategy(address(strategy)).redeemYield(
            tooManyShares,
            yieldReceiver,
            dragonRouter,
            ZERO_BPS
        );

        // Case 2: Get available yield and withdraw most of it
        uint256 availableYield = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();
        uint256 smallYieldAmount = availableYield / 10;

        vm.startPrank(dragonRouter);
        // Withdraw most of the yield
        YieldBearingDragonTokenizedStrategy(address(strategy)).withdrawYield(
            availableYield - smallYieldAmount,
            yieldReceiver,
            dragonRouter,
            ZERO_BPS
        );
        vm.stopPrank();

        // Now we have a small amount of yield and many shares
        // Try to redeem more than available yield - should fail
        vm.prank(dragonRouter);
        vm.expectRevert(); // todo add error message
        YieldBearingDragonTokenizedStrategy(address(strategy)).redeemYield(
            routerBalanceBefore,
            yieldReceiver,
            dragonRouter,
            ZERO_BPS
        );
    }

    /**
     * @notice Test totalEthValueDeposited is updated correctly
     */
    function testTotalEthValueDeposited() public {
        // Reset state tracking variables
        currentCycleRate = 0;

        // Process a harvest cycle to generate yield and update exchange rate
        _processHarvestCycle();

        // Get updated ETH value
        uint256 updatedEthValue = YieldBearingDragonTokenizedStrategy(address(strategy)).totalEthValueDeposited();

        // Get the current exchange rate
        uint256 currentExchangeRate = strategy.getCurrentExchangeRate();

        // Get available yield and total mETH balance
        uint256 availableYield = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();
        uint256 totalMethBalance = mockMeth.balanceOf(address(strategy));

        // Calculate the mEthProfitBalance exactly as in the contract
        uint256 mEthProfitBalance = totalMethBalance - availableYield;

        // Calculate the expected ETH value using the formula from the contract
        uint256 expectedEthValue = (mEthProfitBalance * currentExchangeRate) / 1e18;

        // Verify that our updatedEthValue matches the expected calculation
        // Allow a small tolerance for rounding errors
        uint256 tolerance = 1; // 1 wei tolerance
        assertApproxEqAbs(updatedEthValue, expectedEthValue, tolerance, "Total ETH value should match our calculation");

        // Process a second harvest cycle
        (uint256 profit2, , ) = _processHarvestCycle();

        // Verify profit was generated
        assertGt(profit2, 0, "Second harvest should generate profit");

        // Check with a deposit instead of just yield
        address depositor = makeAddr("depositor");
        uint256 depositAmount = 5 ether;

        // Disable dragon-only mode if it's enabled
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Mint mETH to depositor and deposit
        mockMeth.mint(depositor, depositAmount);

        vm.startPrank(depositor);
        mockMeth.approve(address(strategy), depositAmount);
        IDragonTokenizedStrategy(address(strategy)).deposit(depositAmount, depositor);
        vm.stopPrank();

        // Get ETH value after deposit
        uint256 postDepositEthValue = YieldBearingDragonTokenizedStrategy(address(strategy)).totalEthValueDeposited();

        // The deposit should increase the mEthProfitBalance and consequently the totalEthValueDeposited
        // But we need to account for the way the contract calculates it

        // Get updated available yield and total mETH balance
        uint256 availableYieldAfterDeposit = YieldBearingDragonTokenizedStrategy(address(strategy)).availableYield();
        uint256 totalMethBalanceAfterDeposit = mockMeth.balanceOf(address(strategy));

        // Get the current exchange rate after deposit
        uint256 currentExchangeRateAfterDeposit = strategy.getCurrentExchangeRate();

        // Calculate the new mEthProfitBalance
        uint256 newMEthProfitBalance = totalMethBalanceAfterDeposit - availableYieldAfterDeposit;

        // Calculate the expected ETH value after deposit using the current exchange rate
        uint256 expectedPostDepositEthValue = (newMEthProfitBalance * currentExchangeRateAfterDeposit) / 1e18;

        assertEq(postDepositEthValue, expectedPostDepositEthValue, "ETH value should match calculation after deposit");
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

        // Set temps.safe as the emergencyAdmin using the management address which has permission
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setEmergencyAdmin(temps.safe);

        // First shutdown the strategy - this should be done by management
        vm.prank(management);
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
}
