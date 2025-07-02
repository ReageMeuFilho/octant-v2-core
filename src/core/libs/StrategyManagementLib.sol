// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626Payable } from "src/zodiac-core/interfaces/IERC4626Payable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IAccountant } from "src/interfaces/IAccountant.sol";
import { IMultistrategyVaultFactory } from "src/factories/interfaces/IMultistrategyVaultFactory.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";
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
        mapping(address => IMultistrategyVault.StrategyParams) storage strategies,
        address[] storage defaultQueue,
        address newStrategy,
        bool addToQueue,
        address vaultAsset,
        uint256 maxQueueLength
    ) external {
        // Validate the strategy
        if (newStrategy == address(0)) revert IMultistrategyVault.StrategyCannotBeZeroAddress();

        // Verify the strategy asset matches the vault's asset
        if (IERC4626Payable(newStrategy).asset() != vaultAsset) revert IMultistrategyVault.InvalidAsset();

        // Check the strategy is not already active
        if (strategies[newStrategy].activation != 0) revert IMultistrategyVault.StrategyAlreadyActive();

        // Add the new strategy to the mapping with initialization parameters
        strategies[newStrategy] = IMultistrategyVault.StrategyParams({
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
        mapping(address => IMultistrategyVault.StrategyParams) storage strategies,
        address[] storage defaultQueue,
        address strategy,
        bool force
    ) external returns (uint256 lossAmount) {
        if (strategies[strategy].activation == 0) revert IMultistrategyVault.StrategyNotActive();

        uint256 currentDebt = strategies[strategy].currentDebt;
        if (currentDebt != 0) {
            if (!force) revert IMultistrategyVault.StrategyHasDebt();

            // If force is true, we realize the full loss of outstanding debt
            lossAmount = currentDebt;

            // Note: The caller is responsible for adjusting totalDebt_ and emitting events
        }

        // Set strategy params all back to 0 (WARNING: it can be re-added)
        strategies[strategy] = IMultistrategyVault.StrategyParams({
            activation: 0,
            lastReport: 0,
            currentDebt: 0,
            maxDebt: 0
        });

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
        if (strategyCurrentDebt < assetsNeeded) revert IMultistrategyVault.NotEnoughDebt();

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
