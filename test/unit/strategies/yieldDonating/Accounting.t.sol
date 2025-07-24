// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { console } from "forge-std/console.sol";
import { Setup, IMockStrategy } from "./utils/Setup.sol";
import { IBaseStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

contract AccountingTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_airdropDoesNotIncreasePPS(address _address, uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(strategy), toAirdrop);

        // PPS shouldn't change but the balance does.
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, _amount - toAirdrop, toAirdrop, _amount);

        uint256 beforeBalance = asset.balanceOf(_address);
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

        // should have pulled out just the deposited amount leaving the rest deployed.
        assertEq(asset.balanceOf(_address), beforeBalance + _amount);
        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(asset.balanceOf(address(yieldSource)), toAirdrop);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_airdropDoesNotIncreasePPS_reportRecordsIt(
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
                _address != donationAddress
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
        asset.mint(address(strategy), toAirdrop);

        // PPS shouldn't change but the balance does.
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, _amount - toAirdrop, toAirdrop, _amount);

        // process a report to realize the gain from the airdrop
        uint256 profit;
        vm.prank(keeper);
        (profit, ) = strategy.report();

        assertEq(strategy.pricePerShare(), pricePerShare);
        assertEq(profit, toAirdrop);
        checkStrategyTotals(strategy, _amount + toAirdrop, _amount + toAirdrop, 0, _amount + toAirdrop);

        // allow some profit to come unlocked
        skip(profitMaxUnlockTime / 2);

        // PPS should not increase price per share after report - different behavior from original strategy
        assertEq(strategy.pricePerShare(), pricePerShare);

        //air drop again, we should not increase again
        pricePerShare = strategy.pricePerShare();
        asset.mint(address(strategy), toAirdrop);
        assertEq(strategy.pricePerShare(), pricePerShare, "!pps");

        // skip the rest of the time for unlocking
        skip(profitMaxUnlockTime / 2);

        // Total is the same but balance has adjusted again
        checkStrategyTotals(strategy, _amount + toAirdrop, _amount, toAirdrop);

        uint256 beforeBalance = asset.balanceOf(_address);
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

        // withdaw donation address shares
        uint256 donationShares = strategy.balanceOf(donationAddress);
        // check donation address has shares
        assertGt(donationShares, 0, "!donationShares is zero");
        vm.startPrank(address(donationAddress));
        strategy.redeem(donationShares, donationAddress, donationAddress);
        vm.stopPrank();

        // should have pulled out the deposit plus profit that was reported but not the second airdrop
        assertEq(asset.balanceOf(_address), beforeBalance + _amount);
        // assert donation address has the airdrop
        assertEq(asset.balanceOf(donationAddress), toAirdrop, "!donationAddress");
        assertEq(asset.balanceOf(address(strategy)), 0, "!strategy");

        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_earningYieldDoesNotIncreasePPS(address _address, uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the strategy
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(yieldSource), toAirdrop);

        // nothing should change
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, _amount, 0, _amount);

        uint256 beforeBalance = asset.balanceOf(_address);
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

        // should have pulled out just the deposit amount
        assertEq(asset.balanceOf(_address), beforeBalance + _amount);
        assertEq(asset.balanceOf(address(yieldSource)), toAirdrop);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_earningYieldDoesNotIncreasePPS_reportRecordsIt(
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
                _address != donationAddress
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
        asset.mint(address(yieldSource), toAirdrop);
        assertEq(asset.balanceOf(address(yieldSource)), _amount + toAirdrop, "!yieldSource");

        // nothing should change
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, _amount, 0, _amount);

        // process a report to realize the gain from the airdrop
        uint256 profit;
        vm.prank(keeper);
        (profit, ) = strategy.report();

        assertEq(strategy.pricePerShare(), pricePerShare);
        assertEq(profit, toAirdrop);

        checkStrategyTotals(strategy, _amount + toAirdrop, _amount + toAirdrop, 0, _amount + toAirdrop);

        // allow some profit to come unlocked
        skip(profitMaxUnlockTime / 2);

        // PPS should not increase price per share after report - different behavior from original strategy
        assertEq(strategy.pricePerShare(), pricePerShare);

        //air drop again, we should not increase again
        pricePerShare = strategy.pricePerShare();
        asset.mint(address(yieldSource), toAirdrop);
        assertEq(strategy.pricePerShare(), pricePerShare);

        // skip the rest of the time for unlocking
        skip(profitMaxUnlockTime / 2);

        // Total is the same.
        checkStrategyTotals(strategy, _amount + toAirdrop, _amount + toAirdrop, 0);

        uint256 beforeBalance = asset.balanceOf(_address);
        vm.startPrank(_address);
        uint256 _addressShares = strategy.balanceOf(_address);
        strategy.redeem(_addressShares, _address, _address);
        vm.stopPrank();

        // withdaw donation address shares
        uint256 donationShares = strategy.balanceOf(donationAddress);
        // check donation address has shares
        assertGt(donationShares, 0, "!donationShares is zero");
        vm.startPrank(address(donationAddress));
        strategy.redeem(donationShares, donationAddress, donationAddress);
        vm.stopPrank();

        // should have pulled out the deposit plus profit that was reported but not the second airdrop
        assertEq(asset.balanceOf(_address), beforeBalance + _amount);
        // assert donation address has the airdrop
        assertEq(asset.balanceOf(donationAddress), toAirdrop, "!donationAddress");
        assertEq(asset.balanceOf(address(strategy)), 0, "!strategy");

        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_tend_noIdle_harvestProfit(uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 1, MAX_BPS));

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy to simulate a harvesting of rewards
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(strategy), toAirdrop);
        assertEq(asset.balanceOf(address(strategy)), toAirdrop);
        checkStrategyTotals(strategy, _amount, _amount - toAirdrop, toAirdrop);

        vm.prank(keeper);
        strategy.tend();

        // Should have deposited the toAirdrop amount but no other changes
        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(asset.balanceOf(address(yieldSource)), _amount + toAirdrop, "!yieldSource");
        assertEq(strategy.pricePerShare(), wad, "!pps");

        // Make sure we now report the profit correctly
        vm.prank(keeper);
        strategy.report();

        skip(profitMaxUnlockTime);

        // price per share should be the same
        assertEq(strategy.pricePerShare(), pricePerShare);

        uint256 beforeBalance = asset.balanceOf(user);
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // withdaw donation address shares
        uint256 donationShares = strategy.balanceOf(donationAddress);
        // check donation address has shares
        assertGt(donationShares, 0, "!donationShares is zero");
        vm.startPrank(address(donationAddress));
        strategy.redeem(donationShares, donationAddress, donationAddress);
        vm.stopPrank();

        // should have pulled out the deposit plus profit that was reported but not the second airdrop
        assertEq(asset.balanceOf(user), beforeBalance + _amount);
        // assert donation address has the airdrop
        assertEq(asset.balanceOf(donationAddress), toAirdrop, "!donationAddress");
        assertEq(asset.balanceOf(address(strategy)), 0, "!strategy");
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_tend_idleFunds_harvestProfit(uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 1, MAX_BPS));

        // Use the illiquid mock strategy so it doesn't deposit all funds
        strategy = IMockStrategy(setUpIlliquidStrategy());

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 expectedDeposit = _amount / 2;
        checkStrategyTotals(strategy, _amount, expectedDeposit, _amount - expectedDeposit, _amount);

        assertEq(asset.balanceOf(address(yieldSource)), expectedDeposit, "!yieldSource");
        // should still be 1
        assertEq(strategy.pricePerShare(), wad);

        // airdrop to strategy to simulate a harvesting of rewards
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(strategy), toAirdrop);
        assertEq(asset.balanceOf(address(strategy)), _amount - expectedDeposit + toAirdrop);

        vm.prank(keeper);
        strategy.tend();

        // Should have withdrawn all the funds from the yield source
        checkStrategyTotals(strategy, _amount, 0, _amount, _amount);
        assertEq(asset.balanceOf(address(yieldSource)), 0, "!yieldSource");
        assertEq(asset.balanceOf(address(strategy)), _amount + toAirdrop);
        assertEq(strategy.pricePerShare(), wad, "!pps");

        // Make sure we now report the profit correctly
        vm.prank(keeper);
        strategy.report();

        checkStrategyTotals(
            strategy,
            _amount + toAirdrop,
            (_amount + toAirdrop) / 2,
            (_amount + toAirdrop) - ((_amount + toAirdrop) / 2)
        );
        assertEq(asset.balanceOf(address(yieldSource)), (_amount + toAirdrop) / 2);

        skip(profitMaxUnlockTime);

        // price per share should be the same
        assertEq(strategy.pricePerShare(), pricePerShare);

        // withdaw donation address shares
        uint256 donationShares = strategy.balanceOf(donationAddress);
        // check donation address has shares
        assertGt(donationShares, 0, "!donationShares is zero");
    }

    function test_withdrawWithUnrealizedLoss_reverts(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

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
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        uint256 beforeBalance = asset.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;
        // Withdraw the full amount before the loss is reported.
        vm.prank(_address);
        strategy.withdraw(_amount, _address, _address, _lossFactor);

        uint256 afterBalance = asset.balanceOf(_address);

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
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        uint256 beforeBalance = asset.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;
        // Withdraw the full amount before the loss is reported.
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

        uint256 afterBalance = asset.balanceOf(_address);

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
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

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
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        uint256 beforeBalance = asset.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;

        // First set it to just under the expected loss.
        vm.expectRevert("too much loss");
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address, _lossFactor - 1);

        // Now redeem with the correct loss.
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address, _lossFactor);

        uint256 afterBalance = asset.balanceOf(_address);

        assertEq(afterBalance - beforeBalance, expectedOut);
        assertEq(strategy.pricePerShare(), wad);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_maxUintDeposit_depositsBalance(address _address, uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        asset.mint(_address, _amount);

        vm.prank(_address);
        asset.approve(address(strategy), _amount);

        assertEq(asset.balanceOf(_address), _amount);

        vm.prank(_address);
        strategy.deposit(type(uint256).max, _address);

        // Should just deposit the available amount.
        checkStrategyTotals(strategy, _amount, _amount, 0, _amount);

        assertEq(asset.balanceOf(_address), 0);
        assertEq(strategy.balanceOf(_address), _amount);
        assertEq(asset.balanceOf(address(strategy)), 0);

        assertEq(asset.balanceOf(address(yieldSource)), _amount);
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
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        vm.prank(keeper);
        strategy.report();

        // Should still have shares but no assets
        checkStrategyTotals(strategy, 0, 0, 0, _amount);

        assertEq(strategy.balanceOf(_address), _amount);
        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(asset.balanceOf(address(yieldSource)), 0);

        asset.mint(_address, _amount);
        vm.prank(_address);
        asset.approve(address(strategy), _amount);

        // Should revert with "use safeDeposit" because lossAmount > 0
        vm.expectRevert("use safeDeposit");
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
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        vm.prank(keeper);
        strategy.report();

        // Should still have shares but no assets
        checkStrategyTotals(strategy, 0, 0, 0, _amount);

        assertEq(strategy.balanceOf(_address), _amount);
        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(asset.balanceOf(address(yieldSource)), 0);

        asset.mint(_address, _amount);
        vm.prank(_address);
        asset.approve(address(strategy), _amount);

        // Should revert with "use safeMint" because lossAmount > 0
        vm.expectRevert("use safeMint");
        vm.prank(_address);
        strategy.mint(_amount, _address);

        assertEq(strategy.convertToAssets(_amount), 0);
        assertEq(strategy.convertToShares(_amount), 0);
        assertEq(strategy.pricePerShare(), 0);
    }

    // ===== LOSS BEHAVIOR TESTS =====

    /**
     * @notice Test that loss protection mechanism tracks losses correctly
     * @dev This tests the _handleDragonLossProtection function
     */
    function test_lossProtection_tracksLossesCorrectly(uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));

        // Setup initial deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Record initial state
        uint256 initialDonationShares = strategy.balanceOf(donationAddress);
        assertEq(initialDonationShares, 0, "Initial donation shares should be 0");

        // Simulate a loss in the yield source
        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        // Report the loss - this should trigger loss protection
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "Should report no profit");
        assertEq(loss, toLose, "Should report correct loss amount");

        // Donation address should not receive any shares yet (loss is tracked internally)
        uint256 finalDonationShares = strategy.balanceOf(donationAddress);
        assertEq(finalDonationShares, initialDonationShares, "Donation shares should not change on loss");

        // Total assets should reflect the loss
        assertEq(strategy.totalAssets(), _amount - toLose, "Total assets should reflect loss");
    }

    /**
     * @notice Test that stored losses are offset against future profits
     */
    function test_lossProtection_offsetsAgainstFutureProfits(
        uint256 _amount,
        uint16 _lossFactor,
        uint16 _profitFactor
    ) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS / 2)); // Max 50% loss
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS)); // Up to 100% profit

        // Setup initial deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Simulate a loss
        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        // Report the loss
        vm.prank(keeper);
        (uint256 lossProfit, uint256 reportedLoss) = strategy.report();
        assertEq(lossProfit, 0, "Should report no profit on loss");
        assertEq(reportedLoss, toLose, "Should report correct loss");

        uint256 donationSharesAfterLoss = strategy.balanceOf(donationAddress);
        // convert to assets
        uint256 donationAssetsAfterLoss = strategy.convertToAssets(donationSharesAfterLoss);

        // Now simulate profit that's greater than the loss
        uint256 profitAmount = (_amount * _profitFactor) / MAX_BPS;

        // Report the profit
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IBaseStrategy.harvestAndReport.selector),
            abi.encode(strategy.totalAssets() + profitAmount, 0)
        );
        vm.prank(keeper);
        (uint256 reportedProfit, uint256 profitLoss) = strategy.report();
        assertEq(reportedProfit, profitAmount, "Should report correct profit");
        assertEq(profitLoss, 0, "Should report no loss on profit");
        asset.mint(address(strategy), profitAmount);

        uint256 donationPreviewWithdraw = strategy.convertToAssets(strategy.balanceOf(donationAddress));
        uint256 donationSharesAfterProfit = strategy.balanceOf(donationAddress);

        if (profitAmount > reportedLoss) {
            // If profit exceeds loss, donation address should get shares for the net profit
            uint256 netProfit = profitAmount - reportedLoss;
            assertApproxEqRel(
                donationPreviewWithdraw - donationAssetsAfterLoss,
                netProfit,
                1e16, // 1% tolerance for rounding
                "Donation address should receive shares for net profit"
            );
        } else {
            // If profit doesn't exceed loss, no shares should be minted
            assertEq(
                donationSharesAfterProfit,
                donationSharesAfterLoss,
                "No shares should be minted when profit doesn't exceed stored loss"
            );
        }
    }

    /**
     * @notice Test multiple loss/profit cycles
     */
    function test_lossProtection_multipleCycles(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount / 10); // Smaller amounts for multiple cycles

        // Setup initial deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 cumulativeLoss = 0;
        uint256 cumulativeProfit = 0;

        // Cycle 1: Loss
        uint256 loss1 = _amount / 10; // 10% loss
        vm.prank(address(yieldSource));
        asset.transfer(address(69), loss1);
        vm.prank(keeper);
        strategy.report();
        cumulativeLoss += loss1;

        // Cycle 2: Small profit (less than accumulated loss)
        uint256 profit1 = _amount / 20; // 5% profit
        asset.mint(address(strategy), profit1);
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IBaseStrategy.harvestAndReport.selector),
            abi.encode(strategy.totalAssets() + profit1, 0)
        );
        vm.prank(keeper);
        strategy.report();
        cumulativeProfit += profit1;

        uint256 donationSharesAfterPartialRecovery = strategy.balanceOf(donationAddress);
        assertEq(donationSharesAfterPartialRecovery, 0, "No shares should be minted until losses are fully offset");

        // Cycle 3: Larger profit (exceeds remaining loss)
        uint256 profit2 = _amount / 5; // 20% profit
        asset.mint(address(strategy), profit2);
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IBaseStrategy.harvestAndReport.selector),
            abi.encode(strategy.totalAssets() + profit2, 0)
        );
        vm.prank(keeper);
        strategy.report();
        cumulativeProfit += profit2;

        uint256 donationSharesAfterFullRecovery = strategy.balanceOf(donationAddress);

        if (cumulativeProfit > cumulativeLoss) {
            // Should now have shares for the net profit
            assertGt(donationSharesAfterFullRecovery, 0, "Should have shares after profit exceeds total losses");
        }
    }

    /**
     * @notice Test withdraw behavior during stored losses
     */
    function test_lossProtection_withdrawDuringStoredLoss(uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS / 2));

        // Setup initial deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Simulate a loss
        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        // Report the loss
        vm.prank(keeper);
        strategy.report();

        // User should be able to withdraw with loss
        uint256 userShares = strategy.balanceOf(user);
        uint256 expectedAssets = _amount - toLose; // What should actually be available

        uint256 beforeBalance = asset.balanceOf(user);
        vm.prank(user);
        uint256 assetsReceived = strategy.redeem(userShares, user, user);

        // Should receive the reduced amount
        assertEq(assetsReceived, expectedAssets, "Should receive expected assets after loss");
        assertEq(asset.balanceOf(user) - beforeBalance, expectedAssets, "Balance should match");

        // Strategy should be empty after full withdrawal
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    /**
     * @notice Test edge case: loss exactly equals profit
     */
    function test_lossProtection_lossEqualsProfitEdgeCase(uint256 _amount, uint16 _factor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _factor = uint16(bound(uint256(_factor), 10, MAX_BPS / 2));

        // Setup initial deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 lossAmount = (_amount * _factor) / MAX_BPS;

        // Simulate a loss
        vm.prank(address(yieldSource));
        asset.transfer(address(69), lossAmount);
        vm.prank(keeper);
        strategy.report();

        uint256 donationSharesAfterLoss = strategy.balanceOf(donationAddress);

        // mint the profit to the yield source
        asset.mint(address(strategy), lossAmount);

        // Now mock report call to return the loss amount as profit
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IBaseStrategy.harvestAndReport.selector),
            abi.encode(strategy.totalAssets() + lossAmount, 0)
        );
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        assertEq(profit, lossAmount, "Should report correct profit");
        assertEq(loss, 0, "Should report no loss");

        uint256 donationSharesAfterProfit = strategy.balanceOf(donationAddress);

        // Should have no net effect on donation shares
        assertEq(
            donationSharesAfterProfit,
            donationSharesAfterLoss,
            "Equal loss and profit should result in no net shares minted"
        );

        // PPS should remain stable
        assertEq(strategy.pricePerShare(), wad, "PPS should remain at 1");

        // Total assets should be back to original amount
        assertEq(strategy.totalAssets(), _amount, "Total assets should be restored");
    }

    /**
     * @notice Test maximum possible loss scenario
     */
    function test_lossProtection_maximumLossScenario(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // Setup initial deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Simulate total loss (100%)
        vm.prank(address(yieldSource));
        asset.transfer(address(69), _amount);

        // Report the loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "Should report no profit");
        assertEq(loss, _amount, "Should report total loss");
        assertEq(strategy.totalAssets(), 0, "Should have no assets left");
        assertEq(strategy.balanceOf(donationAddress), 0, "Donation address should have no shares");

        // Even with total loss, PPS calculation should handle gracefully
        // (may be 0 or undefined, but shouldn't revert)
        uint256 pps = strategy.pricePerShare();
        assertEq(pps, 0, "PPS should be 0 when no assets remain");
    }

    // ===== BURN CONVERSION TESTS =====

    /**
     * @notice Test burn conversion accounting fix for dragon loss protection
     * @dev Verifies that asset value is calculated before burning shares to prevent inflated loss coverage
     */
    function test_burnConversion_correctAccounting() public {
        // Enable burning for this test
        vm.prank(management);
        YieldDonatingTokenizedStrategy(address(strategy)).setEnableBurning(true);

        // Setup: totalShares == totalAssets == 100, dragon has 20 shares, loss = 25
        mintAndDepositIntoStrategy(strategy, user, 100e18);
        vm.prank(keeper);
        strategy.report();

        vm.prank(user);
        strategy.transfer(donationAddress, 20e18);

        // Simulate 25 token loss
        yieldSource.simulateLoss(25e18);

        // Calculate what 20 shares are worth BEFORE burning (this is what the fix does)
        uint256 shareValueBeforeBurn = strategy.convertToAssets(20e18);
        assertEq(shareValueBeforeBurn, 20e18, "20 shares should be worth 20 assets before burn");

        // Report the loss (triggers the fixed _handleDragonLossProtection)
        vm.prank(keeper);
        (, uint256 reportedLoss) = strategy.report();

        assertEq(reportedLoss, 25e18, "Should report full 25 token loss");

        // VERIFICATION: Fix ensures correct accounting
        // 1. All dragon shares burned
        assertEq(strategy.balanceOf(donationAddress), 0, "All dragon shares should be burned");

        // 2. Shares reduced by burned amount only
        assertEq(strategy.totalSupply(), 80e18, "Should have 80 shares (100 - 20 burned)");

        // 3. Assets reduced by full loss amount
        assertEq(strategy.totalAssets(), 75e18, "Should have 75 assets (100 - 25 loss)");

        // 4. User gets fair share of remaining assets
        uint256 userShares = strategy.balanceOf(user);
        uint256 userAssetValue = strategy.convertToAssets(userShares);
        assertEq(userAssetValue, 75e18, "User should get fair share of 75 remaining assets");
    }

    /**
     * @notice Test burn conversion across different scenarios
     */
    function test_burnConversion_variousScenarios() public {
        // Enable burning
        vm.prank(management);
        YieldDonatingTokenizedStrategy(address(strategy)).setEnableBurning(true);

        // Scenario 1: Loss fully covered by dragon shares
        mintAndDepositIntoStrategy(strategy, user, 100e18);
        vm.prank(keeper);
        strategy.report();

        vm.prank(user);
        strategy.transfer(donationAddress, 30e18);

        yieldSource.simulateLoss(20e18);
        vm.prank(keeper);
        strategy.report();

        // Should only burn 20 shares to cover 20 token loss
        assertEq(strategy.balanceOf(donationAddress), 10e18, "10 dragon shares should remain");
        assertEq(strategy.totalSupply(), 80e18, "Should have 80 total shares (100 - 20 burned)");
        assertEq(strategy.totalAssets(), 80e18, "Should have 80 total assets (100 - 20 loss)");

        // Scenario 2: Minimal dragon shares, large loss
        vm.startPrank(user);
        strategy.transfer(donationAddress, 9e18); // Dragon router now has 19 total shares
        vm.stopPrank();

        yieldSource.simulateLoss(50e18);
        vm.prank(keeper);
        strategy.report();

        // Should burn all 19 dragon shares, covering 19 tokens
        assertEq(strategy.balanceOf(donationAddress), 0, "All dragon shares should be burned");
        assertEq(strategy.totalSupply(), 61e18, "Should have 61 total shares (80 - 19)");
        assertEq(strategy.totalAssets(), 30e18, "Should have 30 total assets (80 - 50)");
    }

    /**
     * @notice Test burn conversion with burning disabled
     */
    function test_burnConversion_burningDisabled() public {
        // Disable burning
        vm.prank(management);
        YieldDonatingTokenizedStrategy(address(strategy)).setEnableBurning(false);

        mintAndDepositIntoStrategy(strategy, user, 100e18);
        vm.prank(keeper);
        strategy.report();

        // Transfer shares to dragon
        vm.prank(user);
        strategy.transfer(donationAddress, 30e18);

        // Simulate loss
        yieldSource.simulateLoss(25e18);

        uint256 dragonBalanceBefore = strategy.balanceOf(donationAddress);

        // Report the loss
        vm.prank(keeper);
        (, uint256 loss) = strategy.report();

        assertEq(loss, 25e18, "Should report 25 token loss");

        // Verify no shares were burned
        assertEq(
            strategy.balanceOf(donationAddress),
            dragonBalanceBefore,
            "Dragon balance should remain unchanged when burning disabled"
        );

        // Verify assets reduced but shares unchanged
        assertEq(strategy.totalAssets(), 75e18, "Total assets should be 75 after loss");
        assertEq(strategy.totalSupply(), 100e18, "Total shares should remain 100");
    }

    /**
     * @notice Test conversion rate consistency during burn operations
     */
    function test_burnConversion_rateConsistency() public {
        // Enable burning
        vm.prank(management);
        YieldDonatingTokenizedStrategy(address(strategy)).setEnableBurning(true);

        mintAndDepositIntoStrategy(strategy, user, 100e18);
        vm.prank(keeper);
        strategy.report();

        // Transfer 20 shares to dragon
        vm.prank(user);
        strategy.transfer(donationAddress, 20e18);

        // Calculate value of 20 shares BEFORE any loss/burn
        uint256 shareValue = strategy.convertToAssets(20e18);
        assertEq(shareValue, 20e18, "20 shares should be worth 20 assets at 1:1");

        // Simulate loss and report
        yieldSource.simulateLoss(25e18);
        vm.prank(keeper);
        strategy.report();

        // After the fix, the 20 burned shares should have covered exactly 20 assets of loss
        assertEq(strategy.totalAssets(), 75e18, "Should have 75 assets (100 - 25 loss)");
        assertEq(strategy.totalSupply(), 80e18, "Should have 80 shares (100 - 20 burned)");
    }
}
