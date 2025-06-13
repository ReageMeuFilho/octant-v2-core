// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { DragonTokenizedYieldSkimmingStrategy } from "src/zodiac-core/vaults/DragonTokenizedYieldSkimmingStrategy.sol";
import { ITokenizedStrategy } from "src/zodiac-core/interfaces/ITokenizedStrategy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IBaseYieldSkimmingStrategy } from "src/core/interfaces/IBaseYieldSkimmingStrategy.sol";

/**
 * @title YieldSkimmingDragonTokenizedStrategy
 * @notice A specialized version of DragonTokenizedYieldSkimmingStrategy designed for yield-bearing tokens
 * like mETH whose value in ETH terms appreciates over time.
 */
contract YieldSkimmingDragonTokenizedStrategy is DragonTokenizedYieldSkimmingStrategy {
    using Math for uint256;

    /**
     * @inheritdoc DragonTokenizedYieldSkimmingStrategy
     * @dev Overrides report to handle asset appreciation in yield-bearing tokens.
     * This implementation specifically:
     * 1. Calls harvestAndReport to get profit in the asset's terms
     * 2. Converts that profit to shares using a specialized formula that accounts for dilution
     * 3. Mints these shares to dragonRouter, effectively diluting existing shares
     * 4. Updates lastReport timestamp for accounting
     *
     * This approach works well for assets like LSTs (Liquid Staking Tokens) that
     * continuously appreciate in value.
     */
    function report() public override(DragonTokenizedYieldSkimmingStrategy) returns (uint256 profit, uint256 loss) {
        StrategyData storage S = super._strategyStorage();

        // Get the delta
        int256 delta = IBaseYieldSkimmingStrategy(address(this)).harvestAndReport();

        address _dragonRouter = S.dragonRouter;

        S.totalAssets = S.asset.balanceOf(address(this));

        if (delta > 0) {
            // Mint shares based on the adjusted profit amount
            uint256 shares = _convertToSharesFromReport(S, uint256(delta), Math.Rounding.Floor);
            profit = uint256(delta);
            // mint the value
            _mint(S, _dragonRouter, shares);
        } else if (delta < 0) {
            profit = 0;
            loss = uint256(-delta);
            _handleDragonLossProtection(S, loss);
        }

        // Update the new total assets value
        S.lastReport = uint96(block.timestamp);

        emit Reported(profit, loss, 0, 0);

        return (profit, loss);
    }

    /**
     * @dev Override _depositWithLockup to track the ETH value
     */
    function _depositWithLockup(
        uint256 assets,
        address receiver,
        uint256 lockupDuration
    ) internal override returns (uint256 shares) {
        // report to update the exchange rate
        ITokenizedStrategy(address(this)).report();

        shares = super._depositWithLockup(assets, receiver, lockupDuration);

        return shares;
    }

    /**
     * @dev Helper function to convert assets to shares during a report
     * @param S Storage struct pointer to access strategy's storage variables
     * @param assets The amount of assets to convert to shares
     * @param _rounding The rounding direction to use in calculations
     * @return The number of shares that correspond to the given assets
     *
     * Modified from standard ERC4626 conversion to handle the totalAssets_ - assets
     * calculation so that shares issued account for the fact that profit
     * is being recognized and dilution is occurring simultaneously.
     * This prevents undervaluation of newly minted shares.
     */
    function _convertToSharesFromReport(
        StrategyData storage S,
        uint256 assets,
        Math.Rounding _rounding
    ) internal view virtual returns (uint256) {
        // Saves an extra SLOAD if values are non-zero.
        uint256 totalSupply_ = _totalSupply(S);
        // If supply is 0, PPS = 1.
        if (totalSupply_ == 0) return assets;

        uint256 totalAssets_ = _totalAssets(S);
        // If assets are 0 but supply is not PPS = 0.
        if (totalAssets_ == 0) return 0;

        return assets.mulDiv(totalSupply_, totalAssets_ - assets, _rounding);
    }

    /**
     * @dev Internal function to handle loss protection for dragon principal
     * @param S Storage struct pointer to access strategy's storage variables
     * @param loss The amount of loss in terms of asset to protect against
     *
     * This function calculates how many shares would be equivalent to the loss amount,
     * then burns up to that amount of shares from dragonRouter, limited by the router's
     * actual balance. This effectively socializes the loss among all shareholders by
     * burning shares from the donation recipient rather than reducing the value of all shares.
     */
    function _handleDragonLossProtection(StrategyData storage S, uint256 loss) internal override {
        // Can only burn up to available shares
        uint256 sharesBurned = Math.min(
            _convertToSharesFromReport(S, loss, Math.Rounding.Floor),
            S.balances[S.dragonRouter]
        );

        if (sharesBurned > 0) {
            // Burn shares from dragon router
            _burn(S, S.dragonRouter, sharesBurned);
        }
    }
}
