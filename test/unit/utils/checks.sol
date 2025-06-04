// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";

/**
 * @title Vault Checks
 * @notice Utility checks for validating vault and strategy states
 */
library Checks {
    /**
     * @notice Check that a vault is empty (no assets, no shares)
     * @param vault The vault to check
     */
    function checkVaultEmpty(IMultistrategyVault vault) internal view {
        require(vault.totalAssets() == 0, "Vault has assets");
        require(vault.totalSupply() == 0, "Vault has supply");
        require(vault.totalIdle() == 0, "Vault has idle assets");
        require(vault.totalDebt() == 0, "Vault has debt");
    }

    /**
     * @notice Check that a strategy has been properly revoked
     * @param vault The vault containing the strategy
     * @param strategy The strategy address to check
     */
    function checkRevokedStrategy(IMultistrategyVault vault, address strategy) internal view {
        // Get the strategy parameters
        IMultistrategyVault.StrategyParams memory strategyParams = vault.strategies(strategy);

        require(strategyParams.activation == 0, "Strategy is still activated");
        require(strategyParams.lastReport == 0, "Strategy still has last report");
        require(strategyParams.currentDebt == 0, "Strategy still has debt");
        require(strategyParams.maxDebt == 0, "Strategy still has max debt");
    }
}
