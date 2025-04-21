// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626Payable } from "../../interfaces/IERC4626Payable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IAccountant } from "../../interfaces/IAccountant.sol";
import { IVaultFactory } from "../../interfaces/IVaultFactory.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice Library with all actions that can be performed on strategies
library StrategyManagementLib {
    struct StrategyAssessment {
        address asset;
        address strategy;
        uint256 totalAssets;
        uint256 currentDebt;
        uint256 gain;
        uint256 loss;
        uint256 totalFees;
        uint256 totalRefunds;
        uint16 protocolFeeBps;
        address protocolFeeRecipient;
        uint256 profitMaxUnlockTime;
        uint256 sharesToBurn;
        uint256 totalFeesShares;
        uint256 protocolFeesShares;
        uint256 sharesToLock;
    }

    /// CONSTANTS ///

    // 100% in Basis Points.
    uint256 internal constant MAX_BPS = 10_000;
    // Extended for profit locking calculations.
    uint256 internal constant MAX_BPS_EXTENDED = 1_000_000_000_000;

    /// STRATEGY MANAGEMENT FUNCTIONS ///

    /**
     * @notice Add a new strategy to the vault
     * @param strategies Storage mapping of strategy parameters
     * @param defaultQueue Storage array of the default withdrawal queue
     * @param newStrategy The new strategy to add
     * @param addToQueue Whether to add the strategy to the default queue
     * @param vaultAsset The vault's underlying asset
     * @param maxQueueLength The maximum length allowed for the queue
     */
    function addStrategy(
        mapping(address => IVault.StrategyParams) storage strategies,
        address[] storage defaultQueue,
        address newStrategy,
        bool addToQueue,
        address vaultAsset,
        uint256 maxQueueLength
    ) external {
        // Validate the strategy
        if (newStrategy == address(0)) revert IVault.StrategyCannotBeZeroAddress();

        // Verify the strategy asset matches the vault's asset
        if (IERC4626Payable(newStrategy).asset() != vaultAsset) revert IVault.InvalidAsset();

        // Check the strategy is not already active
        if (strategies[newStrategy].activation != 0) revert IVault.StrategyAlreadyActive();

        // Add the new strategy to the mapping with initialization parameters
        strategies[newStrategy] = IVault.StrategyParams({
            activation: block.timestamp,
            lastReport: block.timestamp,
            currentDebt: 0,
            maxDebt: 0
        });

        // If requested and there's room, add to the default queue
        if (addToQueue && defaultQueue.length < maxQueueLength) {
            defaultQueue.push(newStrategy);
        }
    }

    /**
     * @notice Revoke a strategy from the vault
     * @param strategies Storage mapping of strategy parameters
     * @param defaultQueue Storage array of the default withdrawal queue
     * @param strategy The strategy to revoke
     * @param force Whether to force revoke if the strategy has debt
     * @return lossAmount The amount of loss realized if force revoking a strategy with debt
     */
    function revokeStrategy(
        mapping(address => IVault.StrategyParams) storage strategies,
        address[] storage defaultQueue,
        address strategy,
        bool force
    ) external returns (uint256 lossAmount) {
        if (strategies[strategy].activation == 0) revert IVault.StrategyNotActive();

        uint256 currentDebt = strategies[strategy].currentDebt;
        if (currentDebt != 0) {
            if (!force) revert IVault.StrategyHasDebt();

            // If force is true, we realize the full loss of outstanding debt
            lossAmount = currentDebt;

            // Note: The caller is responsible for adjusting totalDebt_ and emitting events
        }

        // Set strategy params all back to 0 (WARNING: it can be re-added)
        strategies[strategy] = IVault.StrategyParams({ activation: 0, lastReport: 0, currentDebt: 0, maxDebt: 0 });

        // First count how many strategies we'll keep to properly size the new array
        uint256 strategiesInQueue = 0;
        bool strategyFound = false;

        for (uint256 i = 0; i < defaultQueue.length; i++) {
            if (defaultQueue[i] == strategy) {
                strategyFound = true;
            } else {
                strategiesInQueue++;
            }
        }

        // Only create a new queue if the strategy was actually in the queue
        if (strategyFound) {
            address[] memory newQueue = new address[](strategiesInQueue);
            uint256 j = 0;

            for (uint256 i = 0; i < defaultQueue.length; i++) {
                // Add all strategies to the new queue besides the one revoked
                if (defaultQueue[i] != strategy) {
                    newQueue[j] = defaultQueue[i];
                    j++;
                }
            }

            // Replace the default queue with our new queue
            // First clear the existing queue
            while (defaultQueue.length > 0) {
                defaultQueue.pop();
            }

            // Then add all items from the new queue
            for (uint256 i = 0; i < newQueue.length; i++) {
                defaultQueue.push(newQueue[i]);
            }
        }

        return lossAmount;
    }

    function assessStrategy(
        mapping(address => IVault.StrategyParams) storage strategies,
        address strategy,
        address accountant,
        address asset,
        uint256 totalIdle,
        address vaultAddress,
        address factory,
        uint256 profitMaxUnlockTime
    ) external returns (StrategyAssessment memory assessment) {
        // Cache asset for repeated use
        assessment.asset = asset;

        if (strategy != vaultAddress) {
            // Make sure we have a valid strategy
            if (strategies[strategy].activation == 0) revert IVault.InactiveStrategy();

            // Vault assesses profits using 4626 compliant interface
            uint256 strategyShares = IERC4626(strategy).balanceOf(vaultAddress);
            // How much the vault's position is worth
            assessment.totalAssets = IERC4626(strategy).convertToAssets(strategyShares);
            // How much the vault had deposited to the strategy
            assessment.currentDebt = strategies[strategy].currentDebt;
        } else {
            // Accrue any airdropped asset into totalIdle
            assessment.totalAssets = IERC20(assessment.asset).balanceOf(vaultAddress);
            assessment.currentDebt = totalIdle;
        }

        // Assess Gain or Loss
        if (assessment.totalAssets > assessment.currentDebt) {
            // We have a gain
            assessment.gain = assessment.totalAssets - assessment.currentDebt;
        } else {
            // We have a loss
            assessment.loss = assessment.currentDebt - assessment.totalAssets;
        }

        // Assess Fees and Refunds
        if (accountant != address(0)) {
            (assessment.totalFees, assessment.totalRefunds) = IAccountant(accountant).report(
                strategy,
                assessment.gain,
                assessment.loss
            );

            if (assessment.totalRefunds > 0) {
                // Make sure we have enough approval and enough asset to pull
                assessment.totalRefunds = Math.min(
                    assessment.totalRefunds,
                    Math.min(
                        IERC20(assessment.asset).balanceOf(accountant),
                        IERC20(assessment.asset).allowance(accountant, vaultAddress)
                    )
                );
            }
        }

        // Protocol fee config information
        if (assessment.totalFees > 0) {
            (assessment.protocolFeeBps, assessment.protocolFeeRecipient) = IVaultFactory(factory).protocolFeeConfig(
                vaultAddress
            );
        }

        // Store profit max unlock time for later use in the vault
        assessment.profitMaxUnlockTime = profitMaxUnlockTime;

        // Store the strategy for later use
        assessment.strategy = strategy;

        // Calculate shares for losses/fees and profit locking
        if (assessment.loss + assessment.totalFees > 0) {
            // Calculate shares to burn for losses and fees
            assessment.sharesToBurn = IERC4626(vaultAddress).previewWithdraw(assessment.loss + assessment.totalFees);

            // If we have fees, calculate shares for fee distribution
            if (assessment.totalFees > 0) {
                // Get the total amount of shares to issue for the fees
                assessment.totalFeesShares =
                    (assessment.sharesToBurn * assessment.totalFees) /
                    (assessment.loss + assessment.totalFees);

                // If there is a protocol fee
                if (assessment.protocolFeeBps > 0) {
                    // Get the percent of fees to go to protocol fees
                    assessment.protocolFeesShares =
                        (assessment.totalFeesShares * uint256(assessment.protocolFeeBps)) /
                        MAX_BPS;
                }
            }
        }

        // Calculate shares to lock for profits
        if (assessment.gain + assessment.totalRefunds > 0 && assessment.profitMaxUnlockTime != 0) {
            assessment.sharesToLock = IERC4626(vaultAddress).convertToShares(assessment.gain + assessment.totalRefunds);
        }

        return assessment;
    }

    /**
     * @notice Assess the share of unrealised losses that a strategy has.
     * @param strategy The address of the strategy
     * @param strategyCurrentDebt The current debt of the strategy
     * @param assetsNeeded The amount of assets needed to be withdrawn
     * @return The share of unrealised losses that the strategy has
     */
    function assessShareOfUnrealisedLosses(
        address strategy,
        uint256 strategyCurrentDebt,
        uint256 assetsNeeded
    ) external view returns (uint256) {
        if (strategyCurrentDebt < assetsNeeded) revert IVault.NotEnoughDebt();

        // The actual amount that the debt is currently worth.
        uint256 vaultShares = IERC4626Payable(strategy).balanceOf(address(this));
        uint256 strategyAssets = IERC4626Payable(strategy).convertToAssets(vaultShares);

        // If no losses, return 0
        if (strategyAssets >= strategyCurrentDebt || strategyCurrentDebt == 0) {
            return 0;
        }

        // Users will withdraw assetsNeeded divided by loss ratio (strategyAssets / strategyCurrentDebt - 1).
        // NOTE: If there are unrealised losses, the user will take his share.
        uint256 numerator = assetsNeeded * strategyAssets;
        uint256 usersShareOfLoss = assetsNeeded - numerator / strategyCurrentDebt;

        // Always round up.
        if (numerator % strategyCurrentDebt != 0) {
            usersShareOfLoss += 1;
        }

        return usersShareOfLoss;
    }

    /**
     * @notice Withdraw assets from a strategy
     * @param strategy The strategy to withdraw from
     * @param assetsToWithdraw The amount of assets to withdraw
     * @return The amount of assets actually withdrawn
     */
    function withdrawFromStrategy(address strategy, uint256 assetsToWithdraw) internal returns (uint256) {
        // Need to get shares since we use redeem to be able to take on losses.
        uint256 sharesToRedeem = Math.min(
            // Use previewWithdraw since it should round up.
            IERC4626Payable(strategy).previewWithdraw(assetsToWithdraw),
            // And check against our actual balance.
            IERC4626Payable(strategy).balanceOf(address(this))
        );

        uint256 preBalance = IERC20(IERC4626Payable(strategy).asset()).balanceOf(address(this));

        // Redeem the shares.
        IERC4626Payable(strategy).redeem(sharesToRedeem, address(this), address(this));

        uint256 postBalance = IERC20(IERC4626Payable(strategy).asset()).balanceOf(address(this));

        return postBalance - preBalance;
    }
}
