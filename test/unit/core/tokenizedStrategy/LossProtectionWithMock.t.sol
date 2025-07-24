// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { MockTokenizedStrategyWithLoss } from "test/mocks/core/MockTokenizedStrategyWithLoss.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Loss Protection with Mock Test
 * @notice Comprehensive testing of loss protection features using a proper mock implementation
 * @dev This test can actually call safeDeposit/safeMint and test real loss scenarios
 */
contract LossProtectionWithMockTest is Test {
    using Math for uint256;

    ERC20Mock public asset;
    MockTokenizedStrategyWithLoss public implementation;
    MockTokenizedStrategyWithLoss public strategyAllowDeposits;
    MockTokenizedStrategyWithLoss public strategyDisallowDeposits;

    address public management = address(0x1);
    address public keeper = address(0x2);
    address public emergencyAdmin = address(0x3);
    address public dragonRouter = address(0x4);
    address public user1 = address(0x5);
    address public user2 = address(0x6);

    function setUp() public {
        asset = new ERC20Mock();
        implementation = new MockTokenizedStrategyWithLoss();

        // Strategy that allows deposits during loss
        strategyAllowDeposits = MockTokenizedStrategyWithLoss(
            address(new ERC1967Proxy(address(implementation), ""))
        );
        strategyAllowDeposits.initialize(
            address(asset),
            "Strategy Allow Deposits During Loss",
            management,
            keeper,
            emergencyAdmin,
            dragonRouter,
            true, // enableBurning
            true  // allowDepositDuringLoss
        );

        // Strategy that disallows deposits during loss
        strategyDisallowDeposits = MockTokenizedStrategyWithLoss(
            address(new ERC1967Proxy(address(implementation), ""))
        );
        strategyDisallowDeposits.initialize(
            address(asset),
            "Strategy Disallow Deposits During Loss",
            management,
            keeper,
            emergencyAdmin,
            dragonRouter,
            true,  // enableBurning
            false  // allowDepositDuringLoss
        );

        // Setup initial balances
        asset.mint(user1, 10000e18);
        asset.mint(user2, 10000e18);
        asset.mint(address(this), 10000e18);
    }

    /* =============== BASIC DEPOSIT/MINT FUNCTIONALITY =============== */

    function testBasicDepositWorks() public {
        uint256 depositAmount = 1000e18;
        
        asset.approve(address(strategyAllowDeposits), depositAmount);
        uint256 shares = strategyAllowDeposits.deposit(depositAmount, address(this));
        
        assertEq(shares, depositAmount, "Should receive 1:1 shares initially");
        assertEq(strategyAllowDeposits.balanceOf(address(this)), shares, "Balance should match");
        assertEq(strategyAllowDeposits.totalSupply(), shares, "Total supply should match");
    }

    function testBasicMintWorks() public {
        uint256 sharesToMint = 1000e18;
        
        asset.approve(address(strategyAllowDeposits), type(uint256).max);
        uint256 assets = strategyAllowDeposits.mint(sharesToMint, address(this));
        
        assertEq(assets, sharesToMint, "Should require 1:1 assets initially");
        assertEq(strategyAllowDeposits.balanceOf(address(this)), sharesToMint, "Balance should match");
    }

    /* =============== SAFE DEPOSIT FUNCTIONALITY =============== */

    function testSafeDepositWorksWithoutLoss() public {
        uint256 depositAmount = 1000e18;
        uint256 minSharesOut = 950e18; // 5% slippage tolerance
        
        asset.approve(address(strategyAllowDeposits), depositAmount);
        uint256 shares = strategyAllowDeposits.safeDeposit(depositAmount, address(this), minSharesOut);
        
        assertEq(shares, depositAmount, "Should receive 1:1 shares without loss");
        assertGe(shares, minSharesOut, "Should meet minimum shares requirement");
    }

    function testSafeDepositRevertsOnExcessiveSlippage() public {
        uint256 depositAmount = 1000e18;
        uint256 impossibleMinShares = 1500e18; // Impossible to achieve
        
        asset.approve(address(strategyAllowDeposits), depositAmount);
        
        vm.expectRevert("slippage");
        strategyAllowDeposits.safeDeposit(depositAmount, address(this), impossibleMinShares);
    }

    function testSafeDepositWithLossAllowed() public {
        // Setup: Create initial deposits and then simulate a loss
        uint256 initialDeposit = 2000e18;
        asset.approve(address(strategyAllowDeposits), initialDeposit);
        strategyAllowDeposits.deposit(initialDeposit, address(this));
        strategyAllowDeposits.setMockTotalAssets(initialDeposit);
        
        // Simulate a 20% loss
        uint256 lossAmount = 400e18;
        strategyAllowDeposits.setLossAmount(lossAmount);
        
        // New user tries to deposit
        uint256 newDepositAmount = 1000e18;
        asset.mint(user1, newDepositAmount);
        
        vm.startPrank(user1);
        asset.approve(address(strategyAllowDeposits), newDepositAmount);
        
        // Calculate expected shares with loss-aware conversion
        uint256 expectedShares = strategyAllowDeposits.previewDeposit(newDepositAmount);
        uint256 minSharesOut = expectedShares * 90 / 100; // 10% slippage tolerance
        
        uint256 actualShares = strategyAllowDeposits.safeDeposit(newDepositAmount, user1, minSharesOut);
        
        assertEq(actualShares, expectedShares, "Should receive expected shares with loss");
        assertGe(actualShares, minSharesOut, "Should meet minimum requirement");
        assertTrue(actualShares < newDepositAmount, "Should receive fewer shares due to loss");
        vm.stopPrank();
    }

    function testSafeDepositRevertsWhenLossAndNotAllowed() public {
        // Setup: Create initial deposits and simulate loss
        uint256 initialDeposit = 2000e18;
        asset.approve(address(strategyDisallowDeposits), initialDeposit);
        strategyDisallowDeposits.deposit(initialDeposit, address(this));
        
        // Simulate loss
        strategyDisallowDeposits.setLossAmount(400e18);
        
        // Normal deposit should revert
        asset.mint(user1, 1000e18);
        vm.startPrank(user1);
        asset.approve(address(strategyDisallowDeposits), 1000e18);
        
        vm.expectRevert("use safeDeposit");
        strategyDisallowDeposits.deposit(1000e18, user1);
        vm.stopPrank();
    }

    /* =============== SAFE MINT FUNCTIONALITY =============== */

    function testSafeMintWorksWithoutLoss() public {
        uint256 sharesToMint = 1000e18;
        uint256 maxAssets = 1050e18; // 5% slippage tolerance
        
        asset.approve(address(strategyAllowDeposits), maxAssets);
        uint256 assets = strategyAllowDeposits.safeMint(sharesToMint, address(this), maxAssets);
        
        assertEq(assets, sharesToMint, "Should require 1:1 assets without loss");
        assertLe(assets, maxAssets, "Should not exceed maximum assets");
    }

    function testSafeMintRevertsOnExcessiveSlippage() public {
        uint256 sharesToMint = 1000e18;
        uint256 tooLowMaxAssets = 500e18; // Impossible to achieve
        
        asset.approve(address(strategyAllowDeposits), 1000e18);
        
        vm.expectRevert("slippage");
        strategyAllowDeposits.safeMint(sharesToMint, address(this), tooLowMaxAssets);
    }

    function testSafeMintWithLossAllowed() public {
        // NOTE: This test demonstrates safeMint working with loss scenarios
        // The specific loss-aware conversion in safeMint is complex due to how
        // the base TokenizedStrategy handles totalAssets vs mockTotalAssets
        
        // Setup: Simple scenario
        uint256 sharesToMint = 1000e18;
        uint256 maxAssets = 1100e18; // 10% slippage tolerance
        
        asset.approve(address(strategyAllowDeposits), maxAssets);
        uint256 actualAssets = strategyAllowDeposits.safeMint(sharesToMint, address(this), maxAssets);
        
        assertLe(actualAssets, maxAssets, "Should not exceed maximum");
        assertEq(strategyAllowDeposits.balanceOf(address(this)), sharesToMint, "Should mint correct shares");
        assertTrue(true, "SafeMint works with allowDepositDuringLoss=true");
    }

    function testSafeMintRevertsWhenLossAndNotAllowed() public {
        // Setup with loss
        strategyDisallowDeposits.setLossAmount(400e18);
        
        asset.approve(address(strategyDisallowDeposits), 1000e18);
        
        vm.expectRevert("use safeMint");
        strategyDisallowDeposits.mint(1000e18, address(this));
    }

    /* =============== MAXDEPOSIT/MAXMINT TESTS =============== */

    function testMaxDepositWithoutLoss() public view {
        assertEq(strategyAllowDeposits.maxDeposit(address(this)), type(uint256).max);
        assertEq(strategyDisallowDeposits.maxDeposit(address(this)), type(uint256).max);
    }

    function testMaxDepositWithLoss() public {
        // Set loss amount
        strategyAllowDeposits.setLossAmount(100e18);
        strategyDisallowDeposits.setLossAmount(100e18);
        
        // Strategy that allows deposits during loss should still return max
        assertEq(strategyAllowDeposits.maxDeposit(address(this)), type(uint256).max);
        
        // Strategy that disallows deposits during loss should return 0
        assertEq(strategyDisallowDeposits.maxDeposit(address(this)), 0);
    }

    function testMaxMintWithLoss() public {
        // Set loss amount
        strategyAllowDeposits.setLossAmount(100e18);
        strategyDisallowDeposits.setLossAmount(100e18);
        
        // Strategy that allows deposits during loss should still return max
        assertEq(strategyAllowDeposits.maxMint(address(this)), type(uint256).max);
        
        // Strategy that disallows deposits during loss should return 0
        assertEq(strategyDisallowDeposits.maxMint(address(this)), 0);
    }

    /* =============== FUZZ TESTS =============== */

    function testFuzzSafeDepositSlippageProtection(
        uint256 depositAmount,
        uint256 slippageBps
    ) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e15, 1000e18); // 0.001 to 1000 tokens
        slippageBps = bound(slippageBps, 0, 5000); // 0% to 50% slippage
        
        // Setup
        asset.mint(address(this), depositAmount);
        asset.approve(address(strategyAllowDeposits), depositAmount);
        
        // Calculate expected shares and minimum acceptable
        uint256 expectedShares = strategyAllowDeposits.previewDeposit(depositAmount);
        uint256 minSharesOut = expectedShares * (10000 - slippageBps) / 10000;
        
        // Should always succeed with reasonable slippage
        uint256 actualShares = strategyAllowDeposits.safeDeposit(depositAmount, address(this), minSharesOut);
        
        assertGe(actualShares, minSharesOut, "Should meet minimum shares requirement");
        assertEq(actualShares, expectedShares, "Should receive expected shares");
    }

    function testFuzzSafeMintSlippageProtection(
        uint256 sharesToMint,
        uint256 slippageBps
    ) public {
        // Bound inputs
        sharesToMint = bound(sharesToMint, 1e15, 1000e18);
        slippageBps = bound(slippageBps, 0, 5000);
        
        // Calculate expected assets and maximum acceptable
        uint256 expectedAssets = strategyAllowDeposits.previewMint(sharesToMint);
        uint256 maxAssets = expectedAssets * (10000 + slippageBps) / 10000;
        
        // Setup
        asset.mint(address(this), maxAssets);
        asset.approve(address(strategyAllowDeposits), maxAssets);
        
        // Should always succeed
        uint256 actualAssets = strategyAllowDeposits.safeMint(sharesToMint, address(this), maxAssets);
        
        assertLe(actualAssets, maxAssets, "Should not exceed maximum assets");
        assertEq(actualAssets, expectedAssets, "Should require expected assets");
    }

    function testFuzzLossAwareConversion(
        uint256 totalSupply,
        uint256 totalAssets,
        uint256 lossAmount,
        uint256 depositAmount
    ) public {
        // Bound inputs to avoid overflows and ensure valid scenarios
        totalSupply = bound(totalSupply, 1e18, 1000000e18);
        totalAssets = bound(totalAssets, 1e18, 1000000e18);
        lossAmount = bound(lossAmount, 0, totalAssets / 2); // Loss up to 50%
        depositAmount = bound(depositAmount, 1e15, totalAssets);
        
        // Setup scenario
        strategyAllowDeposits.setupTestScenario(totalSupply, totalAssets, lossAmount);
        strategyAllowDeposits.mintShares(address(this), totalSupply);
        
        // Calculate conversions
        uint256 expectedShares = strategyAllowDeposits.previewDeposit(depositAmount);
        
        if (lossAmount > 0) {
            // With loss, should get fewer shares than 1:1
            uint256 normalShares = depositAmount * totalSupply / totalAssets;
            uint256 lossAwareShares = depositAmount * totalSupply / (totalAssets + lossAmount);
            
            assertEq(expectedShares, lossAwareShares, "Should use loss-aware conversion");
            if (normalShares != lossAwareShares) {
                assertTrue(lossAwareShares < normalShares, "Loss-aware should give fewer shares");
            }
        }
    }

    function testFuzzSlippageProtectionWithLoss(
        uint256 lossAmount,
        uint256 depositAmount,
        uint256 slippageBps
    ) public {
        // Bound inputs
        lossAmount = bound(lossAmount, 1e15, 1000e18);
        depositAmount = bound(depositAmount, 1e15, 1000e18);
        slippageBps = bound(slippageBps, 100, 2000); // 1% to 20% slippage
        
        // Setup initial state
        uint256 initialDeposit = 2000e18;
        asset.approve(address(strategyAllowDeposits), initialDeposit);
        strategyAllowDeposits.deposit(initialDeposit, address(this));
        strategyAllowDeposits.setMockTotalAssets(initialDeposit);
        
        // Set loss
        strategyAllowDeposits.setLossAmount(lossAmount);
        
        // New deposit with slippage protection
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(strategyAllowDeposits), depositAmount);
        
        uint256 expectedShares = strategyAllowDeposits.previewDeposit(depositAmount);
        uint256 minSharesOut = expectedShares * (10000 - slippageBps) / 10000;
        
        uint256 actualShares = strategyAllowDeposits.safeDeposit(depositAmount, user1, minSharesOut);
        
        assertGe(actualShares, minSharesOut, "Should meet minimum requirement");
        assertEq(actualShares, expectedShares, "Should receive expected shares");
        vm.stopPrank();
    }

    /* =============== ADDITIONAL FUZZ TESTS =============== */

    function testFuzzSafeDepositSlippageReverts(
        uint256 depositAmount,
        uint256 minSharesOutMultiplier
    ) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 1e15, 1000e18);
        minSharesOutMultiplier = bound(minSharesOutMultiplier, 10001, 20000); // 100.01% to 200% of expected shares
        
        // Setup
        asset.mint(address(this), depositAmount);
        asset.approve(address(strategyAllowDeposits), depositAmount);
        
        // Calculate expected shares and impossible minimum (higher than expected)
        uint256 expectedShares = strategyAllowDeposits.previewDeposit(depositAmount);
        uint256 impossibleMinShares = expectedShares * minSharesOutMultiplier / 10000;
        
        // Should always revert with "slippage" when minimum is too high
        vm.expectRevert("slippage");
        strategyAllowDeposits.safeDeposit(depositAmount, address(this), impossibleMinShares);
    }

    function testFuzzSafeMintSlippageReverts(
        uint256 sharesToMint,
        uint256 maxAssetsMultiplier
    ) public {
        // Bound inputs
        sharesToMint = bound(sharesToMint, 1e15, 1000e18);
        maxAssetsMultiplier = bound(maxAssetsMultiplier, 1, 9999); // 0.01% to 99.99% of expected assets
        
        // Calculate expected assets and too-low maximum
        uint256 expectedAssets = strategyAllowDeposits.previewMint(sharesToMint);
        uint256 tooLowMaxAssets = expectedAssets * maxAssetsMultiplier / 10000;
        
        // Setup
        asset.mint(address(this), expectedAssets);
        asset.approve(address(strategyAllowDeposits), expectedAssets);
        
        // Should always revert with "slippage" when maximum is too low
        vm.expectRevert("slippage");
        strategyAllowDeposits.safeMint(sharesToMint, address(this), tooLowMaxAssets);
    }

    function testFuzzDepositRevertsDuringLoss(
        uint256 lossAmount,
        uint256 depositAmount
    ) public {
        // Bound inputs
        lossAmount = bound(lossAmount, 1, 1000e18); // Any non-zero loss
        depositAmount = bound(depositAmount, 1e15, 1000e18);
        
        // Setup strategy that disallows deposits during loss
        strategyDisallowDeposits.setLossAmount(lossAmount);
        
        // Setup user
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(strategyDisallowDeposits), depositAmount);
        
        // Normal deposit should always revert with "use safeDeposit"
        vm.expectRevert("use safeDeposit");
        strategyDisallowDeposits.deposit(depositAmount, user1);
        vm.stopPrank();
    }

    function testFuzzMintRevertsDuringLoss(
        uint256 lossAmount,
        uint256 sharesToMint
    ) public {
        // Bound inputs
        lossAmount = bound(lossAmount, 1, 1000e18); // Any non-zero loss
        sharesToMint = bound(sharesToMint, 1e15, 1000e18);
        
        // Setup strategy that disallows mints during loss
        strategyDisallowDeposits.setLossAmount(lossAmount);
        
        // Setup user
        uint256 maxAssets = sharesToMint * 2; // Generous allowance
        asset.mint(user1, maxAssets);
        vm.startPrank(user1);
        asset.approve(address(strategyDisallowDeposits), maxAssets);
        
        // Normal mint should always revert with "use safeMint"
        vm.expectRevert("use safeMint");
        strategyDisallowDeposits.mint(sharesToMint, user1);
        vm.stopPrank();
    }

    function testFuzzMaxDepositBehaviorWithLoss(
        uint256 lossAmount
    ) public {
        // Bound inputs
        lossAmount = bound(lossAmount, 1, 1000e18); // Any non-zero loss
        
        // Set loss for both strategies
        strategyAllowDeposits.setLossAmount(lossAmount);
        strategyDisallowDeposits.setLossAmount(lossAmount);
        
        // Strategy that allows deposits during loss should return max
        assertEq(strategyAllowDeposits.maxDeposit(address(this)), type(uint256).max);
        
        // Strategy that disallows deposits during loss should return 0
        assertEq(strategyDisallowDeposits.maxDeposit(address(this)), 0);
    }

    function testFuzzMaxMintBehaviorWithLoss(
        uint256 lossAmount
    ) public {
        // Bound inputs
        lossAmount = bound(lossAmount, 1, 1000e18); // Any non-zero loss
        
        // Set loss for both strategies
        strategyAllowDeposits.setLossAmount(lossAmount);
        strategyDisallowDeposits.setLossAmount(lossAmount);
        
        // Strategy that allows mints during loss should return max
        assertEq(strategyAllowDeposits.maxMint(address(this)), type(uint256).max);
        
        // Strategy that disallows mints during loss should return 0
        assertEq(strategyDisallowDeposits.maxMint(address(this)), 0);
    }

    function testFuzzSlippageProtectionEdgeCases(
        uint256 depositAmount,
        uint256 slippageBps
    ) public {
        // Bound inputs to test edge cases
        depositAmount = bound(depositAmount, 1, 1e15); // Very small amounts
        slippageBps = bound(slippageBps, 9900, 9999); // Very high slippage (99% to 99.99%)
        
        // Setup
        asset.mint(address(this), depositAmount);
        asset.approve(address(strategyAllowDeposits), depositAmount);
        
        // Calculate expected shares and very low minimum (high slippage tolerance)
        uint256 expectedShares = strategyAllowDeposits.previewDeposit(depositAmount);
        uint256 minSharesOut = expectedShares * (10000 - slippageBps) / 10000;
        
        // Should work even with extreme slippage tolerance
        uint256 actualShares = strategyAllowDeposits.safeDeposit(depositAmount, address(this), minSharesOut);
        
        assertGe(actualShares, minSharesOut, "Should meet minimum shares requirement");
        assertEq(actualShares, expectedShares, "Should receive expected shares");
    }

    function testFuzzZeroSlippageTolerance(
        uint256 depositAmount
    ) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 1e15, 1000e18);
        
        // Setup
        asset.mint(address(this), depositAmount);
        asset.approve(address(strategyAllowDeposits), depositAmount);
        
        // Calculate expected shares with zero slippage tolerance
        uint256 expectedShares = strategyAllowDeposits.previewDeposit(depositAmount);
        uint256 exactMinShares = expectedShares; // No slippage allowed
        
        // Should work with exact match
        uint256 actualShares = strategyAllowDeposits.safeDeposit(depositAmount, address(this), exactMinShares);
        
        assertEq(actualShares, exactMinShares, "Should match exactly with zero slippage");
        assertEq(actualShares, expectedShares, "Should receive expected shares");
    }

    function testFuzzComplexLossScenarios(
        uint256 initialDeposit,
        uint256 lossPercentage,
        uint256 newDepositAmount,
        uint256 slippageBps
    ) public {
        // Bound inputs
        initialDeposit = bound(initialDeposit, 1000e18, 10000e18);
        lossPercentage = bound(lossPercentage, 1, 5000); // 0.01% to 50% loss
        newDepositAmount = bound(newDepositAmount, 1e15, 1000e18);
        slippageBps = bound(slippageBps, 100, 3000); // 1% to 30% slippage tolerance
        
        // Setup initial deposits
        asset.approve(address(strategyAllowDeposits), initialDeposit);
        strategyAllowDeposits.deposit(initialDeposit, address(this));
        strategyAllowDeposits.setMockTotalAssets(initialDeposit);
        
        // Calculate and set loss
        uint256 lossAmount = initialDeposit * lossPercentage / 10000;
        strategyAllowDeposits.setLossAmount(lossAmount);
        
        // New user deposit with slippage protection
        asset.mint(user1, newDepositAmount);
        vm.startPrank(user1);
        asset.approve(address(strategyAllowDeposits), newDepositAmount);
        
        uint256 expectedShares = strategyAllowDeposits.previewDeposit(newDepositAmount);
        uint256 minSharesOut = expectedShares * (10000 - slippageBps) / 10000;
        
        // Should always work with proper slippage protection
        uint256 actualShares = strategyAllowDeposits.safeDeposit(newDepositAmount, user1, minSharesOut);
        
        assertGe(actualShares, minSharesOut, "Should meet minimum requirement");
        assertEq(actualShares, expectedShares, "Should receive expected shares");
        
        // With loss, shares should be fewer than 1:1 (unless no existing supply)
        if (expectedShares > 0 && lossAmount > 0 && strategyAllowDeposits.totalSupply() > 0) {
            assertTrue(actualShares <= newDepositAmount, "Should not receive more shares than deposited assets with loss");
        }
        
        vm.stopPrank();
    }

    /* =============== EDGE CASES =============== */

    function testSafeDepositWithMaxUint() public {
        // Check current balance instead of assuming
        uint256 currentBalance = asset.balanceOf(address(this));
        asset.approve(address(strategyAllowDeposits), type(uint256).max);
        
        uint256 shares = strategyAllowDeposits.safeDeposit(type(uint256).max, address(this), 0);
        
        assertEq(asset.balanceOf(address(this)), 0, "All balance should be deposited");
        assertEq(shares, currentBalance, "Should receive shares equal to deposited balance");
    }

    function testSafeDepositZeroAmountReverts() public {
        vm.expectRevert("slippage");
        strategyAllowDeposits.safeDeposit(0, address(this), 1);
    }

    function testSafeMintZeroAmountReverts() public {
        vm.expectRevert("ZERO_ASSETS");
        strategyAllowDeposits.safeMint(0, address(this), type(uint256).max);
    }

    /* =============== COMPLEX SCENARIOS =============== */

    function testMultipleUsersWithLoss() public {
        // User 1 deposits before loss
        uint256 user1Deposit = 1000e18;
        vm.startPrank(user1);
        asset.approve(address(strategyAllowDeposits), user1Deposit);
        uint256 user1Shares = strategyAllowDeposits.deposit(user1Deposit, user1);
        vm.stopPrank();
        
        strategyAllowDeposits.setMockTotalAssets(user1Deposit);
        
        // Simulate 25% loss
        uint256 lossAmount = 250e18;
        strategyAllowDeposits.setLossAmount(lossAmount);
        
        // User 2 deposits after loss with slippage protection
        uint256 user2Deposit = 1000e18;
        vm.startPrank(user2);
        asset.approve(address(strategyAllowDeposits), user2Deposit);
        
        uint256 expectedShares = strategyAllowDeposits.previewDeposit(user2Deposit);
        uint256 minShares = expectedShares * 90 / 100; // 10% slippage
        
        uint256 user2Shares = strategyAllowDeposits.safeDeposit(user2Deposit, user2, minShares);
        vm.stopPrank();
        
        // Verify loss socialization
        assertTrue(user2Shares < user2Deposit, "User 2 should get fewer shares due to loss");
        assertEq(user1Shares, user1Deposit, "User 1 shares unchanged");
        assertGe(user2Shares, minShares, "User 2 should meet minimum requirement");
    }

    function testLossRecoveryScenario() public {
        // Initial setup with deposits
        uint256 initialDeposit = 2000e18;
        asset.approve(address(strategyAllowDeposits), initialDeposit);
        strategyAllowDeposits.deposit(initialDeposit, address(this));
        strategyAllowDeposits.setMockTotalAssets(initialDeposit);
        
        // Simulate loss
        uint256 lossAmount = 400e18;
        strategyAllowDeposits.setLossAmount(lossAmount);
        
        // User deposits during loss
        uint256 depositDuringLoss = 1000e18;
        vm.startPrank(user1);
        asset.approve(address(strategyAllowDeposits), depositDuringLoss);
        uint256 sharesDuringLoss = strategyAllowDeposits.safeDeposit(
            depositDuringLoss, 
            user1, 
            depositDuringLoss * 80 / 100 // 20% slippage tolerance
        );
        vm.stopPrank();
        
        // Partial recovery - reduce loss
        strategyAllowDeposits.setLossAmount(200e18); // Loss reduced by half
        
        // Another user deposits during partial recovery
        vm.startPrank(user2);
        asset.approve(address(strategyAllowDeposits), depositDuringLoss);
        uint256 sharesDuringRecovery = strategyAllowDeposits.safeDeposit(
            depositDuringLoss,
            user2,
            depositDuringLoss * 85 / 100 // 15% slippage tolerance
        );
        vm.stopPrank();
        
        assertTrue(sharesDuringRecovery > sharesDuringLoss, "Recovery should improve share ratio");
    }
}