// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626Payable } from "src/zodiac-core/interfaces/IERC4626Payable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";
import { ERC20SafeApproveLib } from "src/core/libs/ERC20SafeApproveLib.sol";

/// @notice Library with all actions that can be performed on strategies
library DebtManagementLib {
    // Constants
    uint256 public constant MAX_BPS = 10_000;

    // Result struct to return updated storage values
    struct UpdateDebtResult {
        uint256 newDebt; // The new debt amount for the strategy
        uint256 newTotalIdle; // The new total idle amount for the vault
        uint256 newTotalDebt; // The new total debt amount for the vault
    }

    // Struct to organize calculation variables - following Vyper implementation
    struct UpdateDebtVars {
        uint256 newDebt; // How much we want the strategy to have
        uint256 currentDebt; // How much the strategy currently has
        uint256 assetsToWithdraw; // Amount to withdraw if reducing debt
        uint256 assetsToDeposit; // Amount to deposit if increasing debt
        uint256 minimumTotalIdle; // Minimum amount to keep in vault
        uint256 totalIdle; // Current idle in vault
        uint256 availableIdle; // Available idle after minimum
        uint256 withdrawable; // Max withdrawable from strategy
        uint256 maxDeposit; // Max deposit to strategy
        uint256 maxDebt; // Strategy's max debt
        address asset; // Vault's asset
        uint256 preBalance; // Balance before operation
        uint256 postBalance; // Balance after operation
        uint256 withdrawn; // Actual amount withdrawn
        uint256 actualDeposit; // Actual amount deposited
    }

    /**
     * @notice Update debt for a strategy
     * @dev The vault will re-balance the debt vs target debt. Target debt must be
     *      smaller or equal to strategy's max_debt. This function will compare the
     *      current debt with the target debt and will take funds or deposit new
     *      funds to the strategy.
     * @param strategies Storage mapping of strategies
     * @param totalIdle Current total idle in vault
     * @param totalDebt Current total debt in vault
     * @param strategy The strategy address
     * @param targetDebt The target debt amount
     * @param maxLoss Maximum acceptable loss in basis points
     * @param minimumTotalIdle Minimum idle to maintain in vault
     * @param asset The vault's asset address
     * @param isShutdown Whether vault is shutdown
     * @return result UpdateDebtResult with new debt, total idle, and total debt
     */
    /* solhint-disable code-complexity */
    function updateDebt(
        mapping(address => IMultistrategyVault.StrategyParams) storage strategies,
        uint256 totalIdle,
        uint256 totalDebt,
        address strategy,
        uint256 targetDebt,
        uint256 maxLoss,
        uint256 minimumTotalIdle,
        address asset,
        bool isShutdown
    ) external returns (UpdateDebtResult memory result) {
        // slither-disable-next-line uninitialized-local
        UpdateDebtVars memory vars;

        // Initialize result with current values
        result.newTotalIdle = totalIdle;
        result.newTotalDebt = totalDebt;

        // How much we want the strategy to have.
        vars.newDebt = targetDebt;
        // How much the strategy currently has.
        vars.currentDebt = strategies[strategy].currentDebt;
        vars.asset = asset;
        vars.minimumTotalIdle = minimumTotalIdle;
        vars.totalIdle = totalIdle;

        // If the vault is shutdown we can only pull funds.
        if (isShutdown) {
            vars.newDebt = 0;
        }

        // assert new_debt != current_debt, "new debt equals current debt"
        if (vars.newDebt == vars.currentDebt) {
            revert IMultistrategyVault.NewDebtEqualsCurrentDebt();
        }

        if (vars.currentDebt > vars.newDebt) {
            // Reduce debt.
            vars.assetsToWithdraw = vars.currentDebt - vars.newDebt;

            // Ensure we always have minimum_total_idle when updating debt.
            // Respect minimum total idle in vault
            if (vars.totalIdle + vars.assetsToWithdraw < vars.minimumTotalIdle) {
                vars.assetsToWithdraw = vars.minimumTotalIdle - vars.totalIdle;
                // Cant withdraw more than the strategy has.
                if (vars.assetsToWithdraw > vars.currentDebt) {
                    vars.assetsToWithdraw = vars.currentDebt;
                }
            }

            // Check how much we are able to withdraw.
            // Use maxRedeem and convert since we use redeem.
            vars.withdrawable = IERC4626Payable(strategy).convertToAssets(
                IERC4626Payable(strategy).maxRedeem(address(this))
            );

            // If insufficient withdrawable, withdraw what we can.
            if (vars.withdrawable < vars.assetsToWithdraw) {
                vars.assetsToWithdraw = vars.withdrawable;
            }

            if (vars.assetsToWithdraw == 0) {
                result.newDebt = vars.currentDebt;
                return result;
            }

            // If there are unrealised losses we don't let the vault reduce its debt until there is a new report
            uint256 unrealisedLossesShare = IMultistrategyVault(address(this)).assessShareOfUnrealisedLosses(
                strategy,
                vars.currentDebt,
                vars.assetsToWithdraw
            );
            if (unrealisedLossesShare != 0) {
                revert IMultistrategyVault.StrategyHasUnrealisedLosses();
            }

            // Always check the actual amount withdrawn.
            vars.preBalance = IERC20(vars.asset).balanceOf(address(this));
            _withdrawFromStrategy(strategy, vars.assetsToWithdraw);
            vars.postBalance = IERC20(vars.asset).balanceOf(address(this));

            // making sure we are changing idle according to the real result no matter what.
            // We pull funds with {redeem} so there can be losses or rounding differences.
            vars.withdrawn = Math.min(vars.postBalance - vars.preBalance, vars.currentDebt);

            // If we didn't get the amount we asked for and there is a max loss.
            if (vars.withdrawn < vars.assetsToWithdraw && maxLoss < MAX_BPS) {
                // Make sure the loss is within the allowed range.
                if (vars.assetsToWithdraw - vars.withdrawn > (vars.assetsToWithdraw * maxLoss) / MAX_BPS) {
                    revert IMultistrategyVault.TooMuchLoss();
                }
            }
            // If we got too much make sure not to increase PPS.
            else if (vars.withdrawn > vars.assetsToWithdraw) {
                vars.assetsToWithdraw = vars.withdrawn;
            }

            // Update storage.
            vars.totalIdle += vars.withdrawn; // actual amount we got.
            // Amount we tried to withdraw in case of losses
            result.newTotalDebt = totalDebt - vars.assetsToWithdraw;

            vars.newDebt = vars.currentDebt - vars.assetsToWithdraw;
        } else {
            // We are increasing the strategies debt

            // Respect the maximum amount allowed.
            vars.maxDebt = strategies[strategy].maxDebt;
            if (vars.newDebt > vars.maxDebt) {
                vars.newDebt = vars.maxDebt;
                // Possible for current to be greater than max from reports.
                if (vars.newDebt < vars.currentDebt) {
                    result.newDebt = vars.currentDebt;
                    return result;
                }
            }

            // Vault is increasing debt with the strategy by sending more funds.
            vars.maxDeposit = IERC4626Payable(strategy).maxDeposit(address(this));
            if (vars.maxDeposit == 0) {
                result.newDebt = vars.currentDebt;
                return result;
            }

            // Deposit the difference between desired and current.
            vars.assetsToDeposit = vars.newDebt - vars.currentDebt;
            if (vars.assetsToDeposit > vars.maxDeposit) {
                // Deposit as much as possible.
                vars.assetsToDeposit = vars.maxDeposit;
            }

            // Ensure we always have minimum_total_idle when updating debt.
            if (vars.totalIdle <= vars.minimumTotalIdle) {
                result.newDebt = vars.currentDebt;
                return result;
            }

            vars.availableIdle = vars.totalIdle - vars.minimumTotalIdle;

            // If insufficient funds to deposit, transfer only what is free.
            if (vars.assetsToDeposit > vars.availableIdle) {
                vars.assetsToDeposit = vars.availableIdle;
            }

            // Can't Deposit 0.
            if (vars.assetsToDeposit > 0) {
                // Approve the strategy to pull only what we are giving it.
                ERC20SafeApproveLib.safeApprove(vars.asset, strategy, vars.assetsToDeposit);

                // Always update based on actual amounts deposited.
                vars.preBalance = IERC20(vars.asset).balanceOf(address(this));
                IERC4626Payable(strategy).deposit(vars.assetsToDeposit, address(this));
                vars.postBalance = IERC20(vars.asset).balanceOf(address(this));

                // Make sure our approval is always back to 0.
                ERC20SafeApproveLib.safeApprove(vars.asset, strategy, 0);

                // Making sure we are changing according to the real result no
                // matter what. This will spend more gas but makes it more robust.
                vars.actualDeposit = vars.preBalance - vars.postBalance;

                // Update storage.
                vars.totalIdle -= vars.actualDeposit;
                result.newTotalDebt = totalDebt + vars.actualDeposit;
            }

            vars.newDebt = vars.currentDebt + vars.actualDeposit;
        }

        // Commit memory to storage.
        strategies[strategy].currentDebt = vars.newDebt;
        result.newTotalIdle = vars.totalIdle;
        result.newDebt = vars.newDebt;

        return result;
    }

    /**
     * @notice Internal function to withdraw from strategy
     * @param strategy The strategy to withdraw from
     * @param assetsToWithdraw Amount to withdraw
     */
    function _withdrawFromStrategy(address strategy, uint256 assetsToWithdraw) internal {
        // Need to get shares since we use redeem to be able to take on losses.
        uint256 sharesToRedeem = Math.min(
            // Use previewWithdraw since it should round up.
            IERC4626Payable(strategy).previewWithdraw(assetsToWithdraw),
            // And check against our actual balance.
            IERC4626Payable(strategy).balanceOf(address(this))
        );

        // Redeem the shares.
        IERC4626Payable(strategy).redeem(sharesToRedeem, address(this), address(this));
    }
}
