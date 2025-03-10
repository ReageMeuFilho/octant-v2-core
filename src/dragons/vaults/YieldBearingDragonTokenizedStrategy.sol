// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { DragonTokenizedStrategy, IBaseStrategy, TokenizedStrategy, Math } from "./DragonTokenizedStrategy.sol";
import { IMethYieldStrategy } from "src/interfaces/IMethYieldStrategy.sol";

/**
 * @title YieldBearingDragonTokenizedStrategy
 * @notice A specialized version of DragonTokenizedStrategy designed for yield-bearing tokens
 * like mETH whose value in ETH terms appreciates over time.
 *
 * @dev This strategy implements custom conversion functions to handle the exchange rate
 * between the yield-bearing token (e.g., mETH) and its underlying value (ETH).
 *
 * Key features:
 * 1. Accounts for exchange rate changes when calculating shares and assets
 * 2. Preserves ETH value during deposits and withdrawals by adjusting for the current exchange rate
 * 3. When depositing: multiplies assets by the exchange rate to give users the correct share amount
 * 4. When withdrawing: divides by the exchange rate to give users the correct token amount
 *
 * This strategy ensures that users' deposits maintain their ETH value regardless of
 * fluctuations in the exchange rate between the yield-bearing token and ETH.
 * This allows for strategies to capture yield from the yield-bearing token and
 * report it as profit in ETH terms.
 */
contract YieldBearingDragonTokenizedStrategy is DragonTokenizedStrategy {
    /**
     * @dev Override the _convertToShares function to account for the exchange rate
     * When depositing, we multiply by the exchange rate to give users more shares
     * based on the ETH value of their mETH
     */
    function _convertToShares(
        StrategyData storage S,
        uint256 assets,
        Math.Rounding rounding
    ) internal view override returns (uint256 shares) {
        uint256 currentExchangeRate = IMethYieldStrategy(address(this)).getCurrentExchangeRate();

        // Calculate ETH value of the mETH assets
        uint256 ethValue = (assets * currentExchangeRate) / 1e18;

        // Convert to shares based on ETH value
        shares = super._convertToShares(S, ethValue, rounding);
        return shares;
    }

    /**
     * @dev Override the _convertToAssets function to account for the exchange rate
     * When withdrawing, we divide by the exchange rate to return the correct amount
     * of mETH based on the ETH value of shares
     */
    function _convertToAssets(
        StrategyData storage S,
        uint256 shares,
        Math.Rounding rounding
    ) internal view override returns (uint256 assets) {
        uint256 currentExchangeRate = IMethYieldStrategy(address(this)).getCurrentExchangeRate();

        // First, get the ETH value of these shares
        uint256 ethValue = super._convertToAssets(S, shares, rounding);

        // Then convert ETH value to mETH amount
        assets = (ethValue * 1e18) / currentExchangeRate;
        return assets;
    }
}
