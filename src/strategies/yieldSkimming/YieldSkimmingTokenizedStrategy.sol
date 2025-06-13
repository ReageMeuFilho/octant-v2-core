// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { IBaseYieldSkimmingStrategy } from "src/core/interfaces/IBaseYieldSkimmingStrategy.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { TokenizedStrategy, Math } from "src/core/TokenizedStrategy.sol";

/**
 * @title YieldSkimmingTokenizedStrategy
 * @author octant.finance
 * @notice A specialized version of TokenizedStrategy designed for yield-bearing tokens
 * like mETH whose value appreciates over time.
 * @dev This strategy implements a yield skimming mechanism by:
 *      - Recognizing appreciation of the underlying asset during report()
 *      - Diluting existing shares by minting new ones to dragonRouter
 *      - Using a modified asset-to-shares conversion that accounts for dilution
 *      - Calling report() during deposits to ensure up-to-date exchange rates
 */
contract YieldSkimmingTokenizedStrategy is TokenizedStrategy {
    using Math for uint256;

    /**
     * @inheritdoc TokenizedStrategy
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
    function report() public override(TokenizedStrategy) returns (uint256 profit, uint256 loss) {
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

        emit Reported(profit, loss);

        return (profit, loss);
    }

    /**
     * @dev Override _deposit to ensure the exchange rate is updated before depositing
     * @param assets The amount of assets being deposited
     * @param receiver The address that will receive the shares
     *
     * This function calls report() first to ensure the latest exchange rate is used
     * when converting assets to shares, preventing stale exchange rates which could
     * lead to incorrect share issuance.
     */

    function _deposit(
        StrategyData storage S,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override(TokenizedStrategy) {
        super._deposit(S, receiver, assets, shares);
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
    function _handleDragonLossProtection(StrategyData storage S, uint256 loss) internal {
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
