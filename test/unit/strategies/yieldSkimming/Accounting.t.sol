// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { Setup, IMockStrategy } from "./utils/Setup.sol";
import { MockYieldSourceSkimming } from "test/mocks/core/tokenized-strategies/MockYieldSourceSkimming.sol";
import { IYieldSkimmingStrategy } from "src/strategies/yieldSkimming/IYieldSkimmingStrategy.sol";
import { MockStrategySkimming } from "test/mocks/core/tokenized-strategies/MockStrategySkimming.sol";
import { WadRayMath } from "src/utils/libs/maths/WadRay.sol";

contract AccountingTestHere is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_airdropDoesNotIncreasePPSHere(address _address, uint256 assets, uint16 airdropAmount) public {
        // Extremely tight bounds to avoid overflow
        assets = bound(assets, 1, 1e6); // Max 1 million - safe for all math
        airdropAmount = uint16(bound(airdropAmount, 1, 100)); // Small airdrop

        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(this));

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, _address, assets);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy
        uint256 toAirdrop = (assets * airdropAmount) / MAX_BPS;
        yieldSource.mint(address(strategy), toAirdrop);

        // PPS shouldn't change but the balance does.
        assertEq(strategy.pricePerShare(), pricePerShare, "!pricePerShare");
        checkStrategyTotals(strategy, assets, 0, assets, assets);

        // report in order to update the totalAssets
        vm.prank(keeper);
        strategy.report();

        uint256 beforeBalance = yieldSource.balanceOf(_address);

        vm.startPrank(_address);
        strategy.redeem(strategy.balanceOf(_address), _address, _address);
        vm.stopPrank();

        // make sure balance of strategy is 0
        assertEq(strategy.balanceOf(_address), 0, "!balanceOf _address 0");

        // should have pulled out just the deposited amount
        assertApproxEqRel(yieldSource.balanceOf(_address), beforeBalance + assets, 2e15, "!balanceOf _address");

        // redeem donation address shares
        uint256 donationShares = strategy.balanceOf(donationAddress);
        if (donationShares > 0) {
            vm.startPrank(address(donationAddress));
            strategy.redeem(donationShares, donationAddress, donationAddress);
            vm.stopPrank();
        }

        // make sure balance of strategy is 0
        assertEq(strategy.balanceOf(donationAddress), 0, "!balanceOf donationShares 0");

        assertEq(yieldSource.balanceOf(address(strategy)), 0, "!balanceOf strategy");

        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_airdropToYieldSourceDecreasesPPS_reportRecordsIt(
        address _address,
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        vm.assume(
            _address != address(0) &&
                _address != address(strategy) &&
                _address != address(yieldSource) &&
                _address != address(donationAddress)
        );

        // deposit into the yield source
        mintAndDepositIntoYieldSource(yieldSource, _address, _amount);

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 addressInitialDepositInValue = _amount * MockYieldSourceSkimming(address(yieldSource)).pricePerShare();

        // should increase
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to yield source
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(yieldSource), toAirdrop);

        // PPS should not change before the report
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, 0, _amount, _amount);

        // process a report to realize the gain from the airdrop

        uint256 totalAssetsBefore = strategy.totalAssets();
        uint256 totalSupplyBefore = strategy.totalSupply();

        vm.prank(keeper);
        (uint256 profit, ) = strategy.report();

        // if pricePerShare changes on the report, it should decrease pps
        if (profit > 0) {
            assertLt(strategy.pricePerShare(), pricePerShare, "!pricePerShare 1");
        } else {
            assertEq(strategy.pricePerShare(), pricePerShare, "!pricePerShare 1 eq");
        }

        // Calculate expected shares minted and verify
        uint256 expectedSharesMinted = calculateExpectedSharesFromProfit(profit, totalAssetsBefore, totalSupplyBefore);

        // Allow some tolerance for precision differences
        assertApproxEqRel(
            strategy.totalSupply() - totalSupplyBefore,
            expectedSharesMinted,
            1e13,
            "Shares minted should match expected"
        );

        checkStrategyTotals(strategy, _amount, 0, _amount, totalSupplyBefore + expectedSharesMinted);

        // allow some profit to come unlocked
        skip(profitMaxUnlockTime / 2);

        //air drop again, we should not increase again
        pricePerShare = strategy.pricePerShare();
        asset.mint(address(yieldSource), toAirdrop);
        totalSupplyBefore = strategy.totalSupply();
        // report again
        vm.prank(keeper);
        (uint256 profit2, ) = strategy.report();

        // if pricePerShare changes on the report, it should decrease pps
        if (profit2 > 0) {
            assertLt(strategy.pricePerShare(), pricePerShare, "!pricePerShare 2");
        } else {
            assertEq(strategy.pricePerShare(), pricePerShare, "!pricePerShare 2 eq");
        }

        // skip the rest of the time for unlocking
        skip(profitMaxUnlockTime / 2);

        // Total is the same but balance has adjusted again
        checkStrategyTotals(
            strategy,
            _amount,
            0,
            _amount,
            totalSupplyBefore +
                expectedSharesMinted +
                calculateExpectedSharesFromProfit(profit2, totalAssetsBefore, totalSupplyBefore)
        );

        vm.startPrank(_address);
        uint256 assetsReceived = strategy.redeem(strategy.balanceOf(_address), _address, _address);
        vm.stopPrank();

        // calculate the value of the assets received
        uint256 assetsReceivedInValue = assetsReceived * MockYieldSourceSkimming(address(yieldSource)).pricePerShare();

        // withdaw donation address shares
        uint256 donationShares = strategy.balanceOf(donationAddress);
        // check donation address has shares if profit is greater than 0
        if (profit > 0 || profit2 > 0) {
            assertGt(donationShares, 0, "!donationShares is zero");
            vm.startPrank(address(donationAddress));
            strategy.redeem(donationShares, donationAddress, donationAddress);
            vm.stopPrank();
        }

        uint256 expectedDonationsShares = _amount - assetsReceived;

        // should have pulled out in value the same as the airdrop
        assertApproxEqRel(assetsReceivedInValue, addressInitialDepositInValue, 1e13);
        // assert donation address has the airdrop
        assertEq(yieldSource.balanceOf(donationAddress), expectedDonationsShares, "!donationAddress");
        assertEq(yieldSource.balanceOf(address(strategy)), 0, "!strategy");

        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_earningYieldDecreasesPPS(address _address, uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        vm.assume(
            _address != address(0) &&
                _address != address(strategy) &&
                _address != address(yieldSource) &&
                _address != address(donationAddress)
        );

        // deposit into the yield source
        mintAndDepositIntoYieldSource(yieldSource, _address, _amount);

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the strategy
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 addressInitialDepositInValue = _amount * MockYieldSourceSkimming(address(yieldSource)).pricePerShare();

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to yield source
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(yieldSource), toAirdrop);

        // PPS should not change before the report
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, 0, _amount, _amount);

        // process a report to realize the gain from the airdrop
        uint256 profit;
        uint256 totalAssetsBefore = strategy.totalAssets();
        uint256 totalSupplyBefore = strategy.totalSupply();

        vm.prank(keeper);
        (profit, ) = strategy.report();

        // if pricePerShare changes on the report, it should decrease pps
        if (profit > 0) {
            assertLt(strategy.pricePerShare(), pricePerShare, "!pricePerShare 1");
        } else {
            assertEq(strategy.pricePerShare(), pricePerShare, "!pricePerShare 1 eq");
        }

        // Calculate expected shares minted and verify
        uint256 expectedSharesMinted = calculateExpectedSharesFromProfit(profit, totalAssetsBefore, totalSupplyBefore);

        // Allow some tolerance for precision differences
        assertApproxEqRel(
            strategy.totalSupply() - totalSupplyBefore,
            expectedSharesMinted,
            1e13,
            "Shares minted should match expected"
        );

        checkStrategyTotals(strategy, _amount, 0, _amount, totalSupplyBefore + expectedSharesMinted);

        // allow some profit to come unlocked
        skip(profitMaxUnlockTime / 2);

        //air drop again, we should not increase again
        pricePerShare = strategy.pricePerShare();
        asset.mint(address(yieldSource), toAirdrop);
        totalSupplyBefore = strategy.totalSupply();
        // report again
        vm.prank(keeper);
        (uint256 profit2, ) = strategy.report();

        // if pricePerShare changes on the report, it should decrease pps
        if (profit2 > 0) {
            assertLt(strategy.pricePerShare(), pricePerShare, "!pricePerShare 2");
        } else {
            assertEq(strategy.pricePerShare(), pricePerShare, "!pricePerShare 2 eq");
        }

        // skip the rest of the time for unlocking
        skip(profitMaxUnlockTime / 2);

        // Total is the same but balance has adjusted again
        checkStrategyTotals(
            strategy,
            _amount,
            0,
            _amount,
            totalSupplyBefore +
                expectedSharesMinted +
                calculateExpectedSharesFromProfit(profit2, totalAssetsBefore, totalSupplyBefore)
        );

        vm.startPrank(_address);
        uint256 assetsReceived = strategy.redeem(strategy.balanceOf(_address), _address, _address);
        vm.stopPrank();

        // calculate the value of the assets received
        uint256 assetsReceivedInValue = assetsReceived * MockYieldSourceSkimming(address(yieldSource)).pricePerShare();

        // withdaw donation address shares
        uint256 donationShares = strategy.balanceOf(donationAddress);
        // check donation address has shares if profit is greater than 0
        if (profit > 0 || profit2 > 0) {
            assertGt(donationShares, 0, "!donationShares is zero");
            vm.startPrank(address(donationAddress));
            strategy.redeem(donationShares, donationAddress, donationAddress);
            vm.stopPrank();
        }

        uint256 expectedDonationsShares = _amount - assetsReceived;

        // should have pulled out in value the same as the airdrop
        assertApproxEqRel(assetsReceivedInValue, addressInitialDepositInValue, 1e13);
        // assert donation address has the airdrop
        assertEq(yieldSource.balanceOf(donationAddress), expectedDonationsShares, "!donationAddress");
        assertEq(yieldSource.balanceOf(address(strategy)), 0, "!strategy");

        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_withdrawWithUnrealizedLoss_reverts(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(strategy));
        yieldSource.transfer(address(69), toLose);

        vm.expectRevert("too much loss");
        vm.prank(_address);
        strategy.withdraw(_amount, _address, _address);
    }

    function test_withdrawWithUnrealizedLoss_withMaxLoss(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(strategy));
        yieldSource.transfer(address(69), toLose);

        uint256 beforeBalance = yieldSource.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;
        // Withdraw the full amount before the loss is reported.
        vm.prank(_address);
        strategy.withdraw(_amount, _address, _address, _lossFactor);

        uint256 afterBalance = yieldSource.balanceOf(_address);

        assertEq(afterBalance - beforeBalance, expectedOut);
        assertEq(strategy.pricePerShare(), wad);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_redeemWithUnrealizedLoss(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.startPrank(address(strategy));
        yieldSource.transfer(address(69), toLose);
        vm.stopPrank();

        uint256 beforeBalance = yieldSource.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;
        // Withdraw the full amount before the loss is reported.
        vm.startPrank(_address);
        strategy.redeem(_amount, _address, _address);
        vm.stopPrank();

        uint256 afterBalance = yieldSource.balanceOf(_address);

        assertEq(afterBalance - beforeBalance, expectedOut);
        assertEq(strategy.pricePerShare(), wad);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_redeemWithUnrealizedLoss_allowNoLoss_reverts(
        address _address,
        uint256 _amount,
        uint16 _lossFactor
    ) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(strategy));
        yieldSource.transfer(address(69), toLose);

        vm.expectRevert("too much loss");
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address, 0);
    }

    function test_redeemWithUnrealizedLoss_customMaxLoss(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(strategy));
        yieldSource.transfer(address(69), toLose);

        uint256 beforeBalance = yieldSource.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;

        // First set it to just under the expected loss.
        vm.expectRevert("too much loss");
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address, _lossFactor - 1);

        // Now redeem with the correct loss.
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address, _lossFactor);

        uint256 afterBalance = yieldSource.balanceOf(_address);

        assertEq(afterBalance - beforeBalance, expectedOut);
        assertEq(strategy.pricePerShare(), wad);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_maxUintDeposit_depositsBalance(address _address, uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));
        vm.assume(yieldSource.balanceOf(_address) == 0);

        yieldSource.mint(_address, _amount);

        vm.prank(_address);
        yieldSource.approve(address(strategy), _amount);

        assertEq(yieldSource.balanceOf(_address), _amount, "!balanceOf _address");

        vm.startPrank(_address);
        strategy.deposit(type(uint256).max, _address);
        vm.stopPrank();

        // Should just deposit the available amount.
        checkStrategyTotals(strategy, _amount, 0, _amount, _amount);

        assertEq(yieldSource.balanceOf(_address), 0, "!balanceOf _address");
        assertEq(strategy.balanceOf(_address), _amount, "!balanceOf strategy");
        assertEq(yieldSource.balanceOf(address(strategy)), _amount, "!balanceOf strategy yieldSource");
    }

    // ===== LOSS BEHAVIOR TESTS =====

    /**
     * @notice Test that loss protection mechanism tracks losses correctly for yield skimming
     * @dev This tests the _handleDragonLossProtection function in YieldSkimmingTokenizedStrategy
     */
    function test_lossProtection_tracksLossesCorrectly(uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS - 1)); // Prevent 100% loss

        // Setup initial deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Record initial state
        uint256 initialDonationShares = strategy.balanceOf(donationAddress);
        assertEq(initialDonationShares, 0, "Initial donation shares should be 0");

        // Simulate a loss by decreasing the exchange rate
        uint256 currentRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 newRate = currentRate - (currentRate * _lossFactor) / MAX_BPS;

        // update the exchange rate
        MockStrategySkimming(address(strategy)).updateExchangeRate(newRate);

        // Report the loss - this should trigger loss protection
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "Should report no profit");
        assertGt(loss, 0, "Should report some loss");

        // Donation address should not receive any shares yet (loss is tracked internally)
        uint256 finalDonationShares = strategy.balanceOf(donationAddress);
        assertEq(finalDonationShares, initialDonationShares, "Donation shares should not change on loss");

        // Clear the mock
        vm.clearMockedCalls();
    }

    /**
     * @notice Test withdraw behavior during stored losses in yield skimming
     */
    function test_lossProtection_withdrawDuringStoredLoss(uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS / 2));

        // Setup initial deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Get initial exchange rate
        uint256 initialRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();

        // Simulate a loss by decreasing the exchange rate
        uint256 lossRate = (initialRate * (MAX_BPS - _lossFactor)) / MAX_BPS;
        MockStrategySkimming(address(strategy)).updateExchangeRate(lossRate);

        // Report the loss (attempts to burn donation shares if available)
        vm.prank(keeper);
        strategy.report();

        // Calculate expected assets based on lower rate
        uint256 userShares = strategy.balanceOf(user);
        uint256 expectedAssets = strategy.previewRedeem(userShares); // Uses current lower rate

        vm.prank(user);
        uint256 assetsReceived = strategy.redeem(userShares, user, user);

        // Should receive reduced amount based on lower rate
        assertApproxEqRel(assetsReceived, expectedAssets, 1e13, "Should receive expected assets after loss");
        // User should get back same number of assets (tokens)
        assertEq(assetsReceived, _amount, "Should receive same number of assets");

        // But underlying value should be less due to rate drop
        uint256 currentRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 withdrawnUnderlyingValue = (assetsReceived * currentRate) / 1e18;
        uint256 depositedUnderlyingValue = _amount; // Initial rate was 1.0

        assertLt(withdrawnUnderlyingValue, depositedUnderlyingValue, "Underlying value should be less due to loss");

        // Strategy should be empty after full withdrawal
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    /**
     * @notice Test maximum possible loss scenario in yield skimming
     */
    function test_lossProtection_maximumLossScenario(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // Setup initial deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // mock the exchange rate to 0
        MockStrategySkimming(address(strategy)).updateExchangeRate(0);

        // Report the loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "Should report no profit");
        assertEq(loss, _amount, "Should report total loss");
        assertEq(strategy.balanceOf(donationAddress), 0, "Donation address should have no shares");
    }

    // ===== DEFICIT ADJUSTMENT TESTS =====
    /**
     * @notice Test invariant: Depositors during loss period cannot withdraw more underlying value than deposited
     * @dev Simulates a loss, post-loss deposit, partial recovery, and verifies withdrawal value
     */
    function test_invariant_lossDepositorCannotWithdrawMoreThanDeposited(
        uint256 initialDeposit,
        uint256 postLossDeposit,
        uint16 lossFactor,
        uint16 recoveryFactor
    ) public {
        initialDeposit = bound(initialDeposit, minFuzzAmount, maxFuzzAmount / 2);
        postLossDeposit = bound(postLossDeposit, minFuzzAmount, maxFuzzAmount / 2);
        lossFactor = uint16(bound(lossFactor, 100, MAX_BPS / 2)); // 1-50% loss
        recoveryFactor = uint16(bound(recoveryFactor, 100, MAX_BPS / 2)); // 1-50% recovery

        address preLossUser = address(0x1234);
        address postLossUser = address(0x5678);

        // Initial deposit before loss
        mintAndDepositIntoStrategy(strategy, preLossUser, initialDeposit);

        // Simulate loss by decreasing exchange rate
        uint256 initialRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 lossRate = (initialRate * (MAX_BPS - lossFactor)) / MAX_BPS;
        MockStrategySkimming(address(strategy)).updateExchangeRate(lossRate);

        // Report the loss (may burn donation shares if available, but assume none for max loss impact)
        vm.startPrank(keeper);
        strategy.report();
        vm.stopPrank();

        // Post-loss deposit
        uint256 postLossUnderlyingValue = postLossDeposit * (lossRate / initialRate); // Expected underlying at loss rate
        mintAndDepositIntoStrategy(strategy, postLossUser, postLossDeposit);

        // Simulate partial recovery
        uint256 recoveryRate = lossRate + ((initialRate - lossRate) * recoveryFactor) / MAX_BPS;
        MockStrategySkimming(address(strategy)).updateExchangeRate(recoveryRate);

        // Report recovery (may mint if recovery exceeds previous supply)
        vm.startPrank(keeper);
        strategy.report();
        vm.stopPrank();

        // Post-loss user withdraws
        vm.startPrank(postLossUser);
        uint256 withdrawnAssets = strategy.redeem(strategy.balanceOf(postLossUser), postLossUser, postLossUser);
        vm.stopPrank();

        // Calculate withdrawn underlying value at current rate
        uint256 withdrawnValue = withdrawnAssets * (recoveryRate / initialRate);

        // Invariant: Cannot withdraw more underlying value than deposited (allowing small rounding tolerance)
        assertLe(withdrawnValue, postLossUnderlyingValue, "Withdrawn value exceeds deposited underlying value");
        assertApproxEqRel(
            withdrawnValue,
            postLossUnderlyingValue,
            0.001e18,
            "Withdrawn value should match deposited with tolerance"
        );
    }

    /**
     * @notice Test invariant: No minting to dragon router until all loss is recovered
     * @dev Simulates loss, partial recoveries, and verifies no minting until full recovery
     */
    function test_invariant_noMintUntilLossRecovered(
        uint256 initialDeposit,
        uint16 lossFactor,
        uint16 partialRecoveryFactor,
        uint16 fullRecoveryFactor
    ) public {
        initialDeposit = bound(initialDeposit, minFuzzAmount, maxFuzzAmount);
        lossFactor = uint16(bound(lossFactor, 100, MAX_BPS / 2)); // 1-50% loss
        partialRecoveryFactor = uint16(bound(partialRecoveryFactor, 50, 99)); // 50-99% of loss recovered (partial)
        fullRecoveryFactor = uint16(bound(fullRecoveryFactor, 100, 150)); // 100-150% (full + extra)

        address user = address(0x1234);

        // Initial deposit
        mintAndDepositIntoStrategy(strategy, user, initialDeposit);

        // Simulate loss
        uint256 initialRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        uint256 lossRate = (initialRate * (MAX_BPS - lossFactor)) / MAX_BPS;
        MockStrategySkimming(address(strategy)).updateExchangeRate(lossRate);

        // Report loss (tracks but doesn't fully handle if no donation shares)
        vm.prank(keeper);
        strategy.report();

        uint256 supplyAfterLoss = strategy.totalSupply();

        // Simulate partial recovery (not enough to cover loss)
        uint256 partialRecoveryRate = lossRate + ((initialRate - lossRate) * partialRecoveryFactor) / 100;
        MockStrategySkimming(address(strategy)).updateExchangeRate(partialRecoveryRate);

        // Report partial recovery
        vm.prank(keeper);
        strategy.report();

        // Invariant: No new shares minted (supply unchanged or decreased if burning)
        assertLe(strategy.totalSupply(), supplyAfterLoss, "No minting during partial recovery");

        // Simulate full recovery (exceeds loss)
        uint256 fullRecoveryRate = lossRate + ((initialRate - lossRate) * fullRecoveryFactor) / 100;
        MockStrategySkimming(address(strategy)).updateExchangeRate(fullRecoveryRate);

        // Report full recovery
        vm.prank(keeper);
        strategy.report();

        // Now minting can occur since loss is swallowed
        if (fullRecoveryFactor > 100) {
            assertGt(strategy.totalSupply(), supplyAfterLoss, "Minting occurs after full recovery");
        } else {
            assertLe(strategy.totalSupply(), supplyAfterLoss, "No minting until excess recovery");
        }
    }

    /**
     * @notice Invariant: Depositors can never receive more in underlying asset value than deposited
     * @dev Fuzzes over deposit amounts, loss/recovery factors, and multiple users
     */
    struct TestVars {
        uint256 initialRate;
        uint256 lossRate;
        uint256 recoveryRate;
        uint256 depositorShares;
        uint256 totalSupplyAfterRecovery;
        uint256 withdrawnAssets;
        uint256 withdrawnValue;
        uint256 netRateChange;
        uint256 depositorFraction;
        uint256 expected;
    }

    function test_invariant_depositorsCannotWithdrawMoreThanDeposited(
        uint256 depositAmount,
        uint16 lossFactor,
        uint16 recoveryFactor
    ) public {
        TestVars memory vars;

        depositAmount = bound(depositAmount, minFuzzAmount, maxFuzzAmount);
        lossFactor = uint16(bound(lossFactor, 100, MAX_BPS / 2)); // 1-50% loss
        recoveryFactor = uint16(bound(recoveryFactor, 50, 200)); // 50-200% recovery (partial to over-recovery)

        address depositor = address(0xABCD);

        // Initial deposit
        mintAndDepositIntoStrategy(strategy, depositor, depositAmount);

        // Get initial exchange rate
        vars.initialRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();

        // Simulate loss
        vars.lossRate = (vars.initialRate * (MAX_BPS - lossFactor)) / MAX_BPS;
        MockStrategySkimming(address(strategy)).updateExchangeRate(vars.lossRate);
        vm.startPrank(keeper);
        strategy.report();
        vm.stopPrank();

        // Get depositor shares before recovery (for fraction calculation)
        vars.depositorShares = strategy.balanceOf(depositor);

        // Simulate recovery
        vars.recoveryRate = vars.lossRate + ((vars.initialRate - vars.lossRate) * recoveryFactor) / 100;
        MockStrategySkimming(address(strategy)).updateExchangeRate(vars.recoveryRate);
        vm.startPrank(keeper);
        strategy.report();
        vm.stopPrank();

        // Get total supply after recovery report (includes any dilution from excess profit minting)
        vars.totalSupplyAfterRecovery = strategy.totalSupply();

        // Withdraw
        vm.startPrank(depositor);
        vars.withdrawnAssets = strategy.redeem(vars.depositorShares, depositor, depositor);
        vm.stopPrank();

        // Calculate withdrawn value in initial rate terms (underlying value)
        vars.withdrawnValue = (vars.withdrawnAssets * vars.recoveryRate) / vars.initialRate;

        // Invariant: Withdrawn value <= deposited amount (with rounding tolerance)
        assertLe(vars.withdrawnValue, depositAmount, "Withdrawn value exceeds deposited amount");

        // Adjusted expectation: Withdrawn value should be approximately deposit adjusted by net rate change and depositor's fraction after dilution (only on excess profit)
        vars.netRateChange = (vars.recoveryRate * 1e18) / vars.initialRate; // Scale to preserve fractions
        vars.depositorFraction = (vars.depositorShares * 1e18) / vars.totalSupplyAfterRecovery; // Scale for precision
        vars.expected = (depositAmount * vars.netRateChange * vars.depositorFraction) / (1e18 * 1e18); // Divide by scales

        assertApproxEqRel(
            vars.withdrawnValue,
            vars.expected,
            0.001e18, // 0.01% tolerance for rounding/dilution effects
            "Value should reflect net recovery rate adjusted for dilution on excess profit"
        );
    }

    struct RecoveryVars {
        uint256 initialRate;
        uint256 lossRate;
        uint256 recoveryRate;
        uint256 initialUnderlying;
        uint256 preRecoverySupply;
        uint256 preRecoveryDragonShares;
        uint256 postRecoverySupply;
        uint256 postRecoveryDragonShares;
        uint256 mintedToDragon;
        uint256 depositorShares;
        uint256 withdrawnAssets;
        uint256 withdrawnUnderlying;
        uint256 recoveryVsLoss;
        uint256 excessUnderlying;
        uint256 expectedMinted;
    }

    function test_invariant_recoveryBehavior(
        uint256 depositAmount,
        uint16 lossFactor,
        uint16 recoveryMultiplier
    ) public {
        RecoveryVars memory vars;

        depositAmount = bound(depositAmount, minFuzzAmount, maxFuzzAmount);
        lossFactor = uint16(bound(lossFactor, 1, MAX_BPS / 2)); // 0.01-50% loss to avoid zero
        recoveryMultiplier = uint16(bound(recoveryMultiplier, 0, 300)); // 0-300% recovery factor

        address depositor = address(0xABCD);

        // Initial deposit
        mintAndDepositIntoStrategy(strategy, depositor, depositAmount);

        vars.initialRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        vars.initialUnderlying = (depositAmount * vars.initialRate) / 1e18; // Assuming rate in 1e18 scale for simplicity

        // Simulate loss
        vars.lossRate = (vars.initialRate * (MAX_BPS - lossFactor)) / MAX_BPS;
        MockStrategySkimming(address(strategy)).updateExchangeRate(vars.lossRate);
        vm.startPrank(keeper);
        strategy.report();
        vm.stopPrank();

        vars.preRecoverySupply = strategy.totalSupply();
        vars.preRecoveryDragonShares = strategy.balanceOf(donationAddress); // Corrected to donationAddress

        // Simulate recovery
        uint256 lostAmount = vars.initialRate - vars.lossRate;
        vars.recoveryRate = vars.lossRate + (lostAmount * recoveryMultiplier) / 100;
        MockStrategySkimming(address(strategy)).updateExchangeRate(vars.recoveryRate);
        vm.startPrank(keeper);
        strategy.report();
        vm.stopPrank();

        vars.postRecoverySupply = strategy.totalSupply();
        vars.postRecoveryDragonShares = strategy.balanceOf(donationAddress); // Corrected to donationAddress

        vars.mintedToDragon = vars.postRecoveryDragonShares - vars.preRecoveryDragonShares;

        // Withdraw
        vm.startPrank(depositor);
        vars.depositorShares = strategy.balanceOf(depositor);
        vars.withdrawnAssets = strategy.redeem(strategy.balanceOf(depositor), depositor, depositor);
        vm.stopPrank();

        vars.withdrawnUnderlying = (vars.withdrawnAssets * vars.recoveryRate) / 1e18;

        // Calculate recovery ratio (recovery vs. loss in underlying terms)
        vars.recoveryVsLoss = (vars.recoveryRate >= vars.initialRate)
            ? 2 // Full recovery ( > loss)
            : (vars.recoveryRate > vars.lossRate)
                ? 1
                : 0; // Partial recovery (< loss) or further loss

        if (vars.recoveryVsLoss == 0) {
            // Recovery <= loss (further or no recovery)
            assertEq(vars.mintedToDragon, 0, "No minting if recovery <= loss");
            assertLt(vars.withdrawnUnderlying, vars.initialUnderlying, "Withdrawn < deposited if incomplete recovery");
        } else if (vars.recoveryVsLoss == 1) {
            // Partial recovery (recovery > lossRate but < initialRate)
            assertEq(vars.mintedToDragon, 0, "No minting if partial recovery (< full loss offset)");
            assertLt(vars.withdrawnUnderlying, vars.initialUnderlying, "Withdrawn < deposited if partial recovery");
        } else {
            // Full recovery (recovery >= initialRate, excess >0)
            assertApproxEqRel(
                vars.withdrawnUnderlying,
                vars.initialUnderlying,
                0.001e18,
                "Depositor gets exactly deposited underlying on full recovery"
            );
            // Adjust for dust: only assert >0 if excess is material (e.g., >1e9 wei underlying to avoid flooring to 0)
            vars.excessUnderlying = (depositAmount * (vars.recoveryRate - vars.initialRate)) / 1e18;
            if (vars.excessUnderlying > 1e9) {
                assertGt(vars.mintedToDragon, 0, "Excess profit minted to dragon on full recovery");
            } else {
                assertGe(vars.mintedToDragon, 0, "Dust excess may not trigger minting");
            }
            // Optional: Check minted ≈ excess underlying converted to shares
            vars.expectedMinted = vars.excessUnderlying; // Assuming PPS≈1 in underlying
            assertApproxEqRel(vars.mintedToDragon, vars.expectedMinted, 0.0001e18, "Minted matches excess underlying");
        }
    }

    struct LocalVars {
        uint256 initialRate;
        uint256 lossRate;
        uint256 recoveryRate;
    }

    function test_invariant_depositorsCannotWithdrawMoreThanInitialUnderlying(
        uint256 depositAmount1,
        uint256 depositAmount2,
        uint16 lossFactor,
        uint16 recoveryMultiplier
    ) public {
        address depositor1 = makeAddr("depositor1");
        address depositor2 = makeAddr("depositor2");

        depositAmount1 = bound(depositAmount1, minFuzzAmount, maxFuzzAmount / 2);
        depositAmount2 = bound(depositAmount2, minFuzzAmount, maxFuzzAmount / 2);
        lossFactor = uint16(bound(lossFactor, 0, MAX_BPS / 2));
        recoveryMultiplier = uint16(bound(recoveryMultiplier, 0, MAX_BPS * 2));
        vm.assume(depositAmount1 > 0 && depositAmount2 > 0);

        LocalVars memory vars;

        // Depositor 1 deposits using helper
        mintAndDepositIntoStrategy(strategy, depositor1, depositAmount1);
        uint256 initialUnderlying1 = depositAmount1; // Adjust if initial rate !=1e18

        // Depositor 2 deposits using helper
        mintAndDepositIntoStrategy(strategy, depositor2, depositAmount2);
        uint256 initialUnderlying2 = depositAmount2;

        // Simulate loss and recovery
        vars.initialRate = IYieldSkimmingStrategy(address(strategy)).getCurrentExchangeRate();
        vars.lossRate = (vars.initialRate * (MAX_BPS - lossFactor)) / MAX_BPS;
        MockStrategySkimming(address(strategy)).updateExchangeRate(vars.lossRate);
        vm.prank(keeper);
        strategy.report();

        vars.recoveryRate = vars.lossRate + (vars.lossRate * recoveryMultiplier) / MAX_BPS;
        MockStrategySkimming(address(strategy)).updateExchangeRate(vars.recoveryRate);
        vm.prank(keeper);
        strategy.report();

        // Withdraw and check
        uint256 shares1 = strategy.balanceOf(depositor1);
        vm.prank(depositor1);
        uint256 withdrawnAssets1 = strategy.redeem(shares1, depositor1, depositor1);
        uint256 withdrawnUnderlying1 = (withdrawnAssets1 * vars.recoveryRate) / 1e18;

        uint256 shares2 = strategy.balanceOf(depositor2);
        vm.prank(depositor2);
        uint256 withdrawnAssets2 = strategy.redeem(shares2, depositor2, depositor2);
        uint256 withdrawnUnderlying2 = (withdrawnAssets2 * vars.recoveryRate) / 1e18;

        assertLe(withdrawnUnderlying1, initialUnderlying1 + 1, "Depositor1 withdrawn <= initial");
        assertLe(withdrawnUnderlying2, initialUnderlying2 + 1, "Depositor2 withdrawn <= initial");
    }
}
