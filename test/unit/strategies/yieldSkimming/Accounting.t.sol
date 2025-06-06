// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { Setup, IMockStrategy } from "./utils/Setup.sol";
import { MockYieldSourceSkimming } from "test/mocks/core/tokenized-strategies/MockYieldSourceSkimming.sol";

contract AccountingTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    // todo check with team if it makes sense in yield skimming strategy
    function test_airdropDoesNotIncreasePPS(address _address, uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        vm.assume(
            _address != address(0) &&
                _address != address(strategy) &&
                _address != address(yieldSource) &&
                _address != address(donationAddress)
        );

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        yieldSource.mint(address(strategy), toAirdrop);

        // PPS shouldn't change but the balance does.
        assertEq(strategy.pricePerShare(), pricePerShare, "!pricePerShare");
        checkStrategyTotals(strategy, _amount, 0, _amount, _amount);

        // report in order to update the totalAssets
        vm.prank(keeper);
        strategy.report();

        uint256 beforeBalance = yieldSource.balanceOf(_address);
        vm.startPrank(_address);
        strategy.redeem(strategy.balanceOf(_address), _address, _address);
        vm.stopPrank();

        // should have pulled out just the deposited amount leaving the rest deployed.
        assertEq(yieldSource.balanceOf(_address), beforeBalance + _amount + toAirdrop, "!balanceOf _address");

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
        vm.prank(address(strategy));
        yieldSource.transfer(address(69), toLose);

        uint256 beforeBalance = yieldSource.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;
        // Withdraw the full amount before the loss is reported.
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

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

        yieldSource.mint(_address, _amount);

        vm.prank(_address);
        yieldSource.approve(address(strategy), _amount);

        assertEq(yieldSource.balanceOf(_address), _amount, "!balanceOf _address");

        vm.prank(_address);
        strategy.deposit(type(uint256).max, _address);

        // Should just deposit the available amount.
        checkStrategyTotals(strategy, _amount, 0, _amount, _amount);

        assertEq(yieldSource.balanceOf(_address), 0, "!balanceOf _address");
        assertEq(strategy.balanceOf(_address), _amount, "!balanceOf strategy");
        assertEq(yieldSource.balanceOf(address(strategy)), _amount, "!balanceOf strategy yieldSource");
    }

    function test_deposit_zeroAssetsPositiveSupply_reverts(address _address, uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        vm.assume(
            _address != address(0) &&
                _address != address(strategy) &&
                _address != address(yieldSource) &&
                _address != donationAddress
        );

        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = _amount;
        // Simulate a loss.
        vm.prank(address(strategy));
        yieldSource.transfer(address(69), toLose);

        vm.prank(keeper);
        strategy.report();

        // Should still have shares but no yieldSources
        // checkStrategyTotals(strategy, _amount, 0, _amount, _amount);

        assertEq(strategy.balanceOf(_address), _amount, "!balanceOf _address");
        assertEq(yieldSource.balanceOf(address(strategy)), 0, "!balanceOf strategy");
        assertEq(yieldSource.balanceOf(address(yieldSource)), 0, "!balanceOf yieldSource");

        yieldSource.mint(_address, _amount);
        vm.prank(_address);
        yieldSource.approve(address(strategy), _amount);

        vm.expectRevert("ZERO_SHARES");
        vm.prank(_address);
        strategy.deposit(_amount, _address);

        assertEq(strategy.convertToAssets(_amount), 0);
        assertEq(strategy.convertToShares(_amount), 0);
        assertEq(strategy.pricePerShare(), 0);
    }

    function test_mint_zeroAssetsPositiveSupply_reverts(address _address, uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        vm.assume(
            _address != address(0) &&
                _address != address(strategy) &&
                _address != address(yieldSource) &&
                _address != donationAddress
        );

        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = _amount;
        // Simulate a loss.
        vm.prank(address(strategy));
        yieldSource.transfer(address(69), toLose);

        vm.prank(keeper);
        strategy.report();

        // Should still have shares but no assets
        checkStrategyTotals(strategy, 0, 0, 0, _amount);

        assertEq(strategy.balanceOf(_address), _amount);
        assertEq(yieldSource.balanceOf(address(strategy)), 0, "!balanceOf strategy");

        yieldSource.mint(_address, _amount);
        vm.prank(_address);
        yieldSource.approve(address(strategy), _amount);

        vm.expectRevert("ZERO_ASSETS");
        vm.prank(_address);
        strategy.mint(_amount, _address);

        assertEq(strategy.convertToAssets(_amount), 0);
        assertEq(strategy.convertToShares(_amount), 0);
        assertEq(strategy.pricePerShare(), 0);
    }
}
