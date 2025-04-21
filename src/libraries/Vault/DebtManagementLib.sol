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
library DebtManagementLib {
    struct UpdateDebtResult {
        uint256 newDebt; // The new debt amount for the strategy
        uint256 newTotalIdle; // The new total idle amount for the vault
        uint256 newTotalDebt; // The new total debt amount for the vault
        uint256 assetApprovalAmount; // Amount to approve if depositing
    }

    // New struct to organize calculation variables
    struct UpdateDebtVars {
        uint256 currentDebt; // The strategy's current debt
        uint256 newDebt; // The target debt
        uint256 maxDebt; // The strategy's max debt
        uint256 assetsToWithdraw; // Amount to withdraw (if decreasing debt)
        uint256 assetsToDeposit; // Amount to deposit (if increasing debt)
        uint256 availableIdle; // Available idle assets after minimum
        uint256 maxRedeemAmount; // Strategy's max redeem
        uint256 withdrawable; // Strategy's withdrawable amount
        uint256 maxDepositAmount; // Strategy's max deposit amount
        bool isDebtDecrease; // Whether we're decreasing debt
    }

    function updateDebt(
        mapping(address => IVault.StrategyParams) storage strategies,
        address strategy,
        uint256 targetDebt,
        uint256 totalIdle,
        uint256 totalDebt,
        uint256 minimumTotalIdle,
        address vaultAddress,
        bool isShutdown
    ) external view returns (UpdateDebtResult memory result) {
        // Initialize the result with current values
        result.newTotalIdle = totalIdle;
        result.newTotalDebt = totalDebt;

        // Initialize calculation variables
        UpdateDebtVars memory vars;
        vars.currentDebt = strategies[strategy].currentDebt;
        vars.newDebt = targetDebt;

        // If vault is shutdown, we can only withdraw
        if (isShutdown) {
            vars.newDebt = 0;
        }

        // Can't update to the same debt level
        if (vars.newDebt == vars.currentDebt) revert IVault.NewDebtEqualsCurrentDebt();

        // Determine if we're decreasing or increasing debt
        vars.isDebtDecrease = vars.currentDebt > vars.newDebt;

        if (vars.isDebtDecrease) {
            // DEBT DECREASE - Withdrawing from strategy
            // Calculate how much to withdraw
            vars.assetsToWithdraw = vars.currentDebt - vars.newDebt;

            // Respect minimum total idle in vault
            if (totalIdle + vars.assetsToWithdraw < minimumTotalIdle) {
                vars.assetsToWithdraw = minimumTotalIdle - totalIdle;
                // Can't withdraw more than the strategy has
                if (vars.assetsToWithdraw > vars.currentDebt) {
                    vars.assetsToWithdraw = vars.currentDebt;
                }
            }

            // Check how much we are able to withdraw based on strategy limits
            vars.maxRedeemAmount = IERC4626Payable(strategy).maxRedeem(vaultAddress);
            vars.withdrawable = IERC4626Payable(strategy).convertToAssets(vars.maxRedeemAmount);

            // If insufficient withdrawable, withdraw what we can
            if (vars.withdrawable < vars.assetsToWithdraw) {
                vars.assetsToWithdraw = vars.withdrawable;
            }

            // If nothing to withdraw, return current debt
            if (vars.assetsToWithdraw == 0) {
                result.newDebt = vars.currentDebt;
                return result;
            }

            // Check for unrealized losses
            uint256 unrealisedLossesShare = IVault(vaultAddress).assessShareOfUnrealisedLosses(
                strategy,
                vars.currentDebt,
                vars.assetsToWithdraw
            );

            // Strategy shouldn't have unrealized losses to proceed
            if (unrealisedLossesShare > 0) revert IVault.StrategyHasUnrealisedLosses();

            // Update tracking variables
            result.newTotalIdle += vars.assetsToWithdraw;
            result.newTotalDebt -= vars.assetsToWithdraw;
            result.newDebt = vars.currentDebt - vars.assetsToWithdraw;
        } else {
            // DEBT INCREASE - Depositing to strategy

            // Apply max debt limit
            vars.maxDebt = strategies[strategy].maxDebt;
            if (vars.newDebt > vars.maxDebt) {
                vars.newDebt = vars.maxDebt;
                // Possible for current to be greater than max from reports
                if (vars.newDebt < vars.currentDebt) {
                    result.newDebt = vars.currentDebt;
                    return result;
                }
            }

            // Check if strategy accepts deposits
            vars.maxDepositAmount = IERC4626Payable(strategy).maxDeposit(vaultAddress);
            if (vars.maxDepositAmount == 0) {
                result.newDebt = vars.currentDebt;
                return result;
            }

            // Calculate how much to deposit
            vars.assetsToDeposit = vars.newDebt - vars.currentDebt;
            if (vars.assetsToDeposit > vars.maxDepositAmount) {
                vars.assetsToDeposit = vars.maxDepositAmount;
            }

            // Check vault minimum idle requirement
            if (totalIdle <= minimumTotalIdle) {
                result.newDebt = vars.currentDebt;
                return result;
            }

            vars.availableIdle = totalIdle - minimumTotalIdle;

            // If insufficient funds to deposit, transfer only what is free
            if (vars.assetsToDeposit > vars.availableIdle) {
                vars.assetsToDeposit = vars.availableIdle;
            }

            // Skip if nothing to deposit
            if (vars.assetsToDeposit == 0) {
                result.newDebt = vars.currentDebt;
                return result;
            }

            // Set amount for approval
            result.assetApprovalAmount = vars.assetsToDeposit;

            // Update tracking variables
            result.newTotalIdle -= vars.assetsToDeposit;
            result.newTotalDebt += vars.assetsToDeposit;
            result.newDebt = vars.currentDebt + vars.assetsToDeposit;
        }

        return result;
    }
}
