// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { DragonBaseStrategy } from "../DragonBaseStrategy.sol";
import { DragonTokenizedStrategy } from "../DragonTokenizedStrategy.sol";

/**
 * @title YieldSkimmingTokenizedStrategy
 * @author octant.finance
 * @notice A specialized version of DragonTokenizedStrategy designed for yield-bearing tokens
 * like mETH whose value in ETH terms appreciates over time.
 * @dev This strategy implements a yield skimming mechanism by:
 *      - Recognizing appreciation of the underlying asset during report()
 *      - Diluting existing shares by minting new ones to dragonRouter
 *      - Using a modified asset-to-shares conversion that accounts for dilution
 *      - Calling report() during deposits to ensure up-to-date exchange rates
 */
contract YieldSkimmingTokenizedStrategy is DragonTokenizedStrategy {
    using Math for uint256;

    /**
     * @inheritdoc DragonTokenizedStrategy
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
    function report() 
        public 
        override(TokenizedStrategy)
        nonReentrant
        onlyKeepers
        returns (uint256 profit, uint256 loss) 
    {
        StrategyData storage S = super._strategyStorage();

        // Get the profit in mETH terms
        profit = IBaseStrategy(address(this)).harvestAndReport();
        address _dragonRouter = S.dragonRouter;

        if (profit > 0) {
            // Mint shares based on the adjusted profit amount
            uint256 shares = _convertToSharesFromReport(S, profit, Math.Rounding.Floor);
            // mint the mETH value
            _mint(S, _dragonRouter, shares);
        }

        // Update the new total assets value
        S.lastReport = uint96(block.timestamp);

        emit Reported(
            profit,
            loss
        );

        return (profit, loss);
    }

    /**
     * @dev Override _deposit to ensure the exchange rate is updated before depositing
     * @param assets The amount of assets being deposited
     * @param receiver The address that will receive the shares
     * @return shares The number of shares minted to the receiver
     * 
     * This function calls report() first to ensure the latest exchange rate is used
     * when converting assets to shares, preventing stale exchange rates which could
     * lead to incorrect share issuance.
     */
    function _deposit(uint256 assets, address receiver) internal override returns (uint256 shares) {
        // report to update the exchange rate
        ITokenizedStrategy(address(this)).report();

        shares = super._deposit(assets, receiver, lockupDuration);

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
}
