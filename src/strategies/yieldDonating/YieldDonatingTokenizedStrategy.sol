// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;
import { TokenizedStrategy, Math } from "src/core/TokenizedStrategy.sol";
import { IBaseStrategy } from "src/core/interfaces/IBaseStrategy.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
/**
 * @title YieldDonatingTokenizedStrategy
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Specialized TokenizedStrategy for productive assets with discrete harvesting; profits are donated by minting shares to the dragon router.
 * @dev Behavior overview:
 *      - On report(), harvests the underlying position via BaseStrategy.harvestAndReport()
 *      - If newTotalAssets > oldTotalAssets, mints shares equal to the profit (asset value) to the dragon router
 *      - If losses occur and burning is enabled, burns dragon router shares (up to its balance) using rounding-up shares-to-burn
 *      - No tracked-loss bucket exists; any loss not covered by dragon router burning reduces totalAssets and affects PPS for all holders
 *
 * Economic notes:
 *      - Profit donations are realized via share mints at the time of report
 *      - Losses first attempt dragon share burning when enabled; residual losses decrease PPS
 *      - Dragon router change follows TokenizedStrategy cooldown and two-step finalization
 */
contract YieldDonatingTokenizedStrategy is TokenizedStrategy {
    using Math for uint256;

    /// @dev Events for donation tracking
    /// @param dragonRouter Address receiving or burning donation shares
    /// @param amount Amount of shares minted or burned (denominated in shares)
    event DonationMinted(address indexed dragonRouter, uint256 amount);
    /// @dev Emitted when dragon shares are burned to cover losses
    event DonationBurned(address indexed dragonRouter, uint256 amount);
    /**
     * @inheritdoc TokenizedStrategy
     * @dev Mints profit-derived shares to dragon router when newTotalAssets > oldTotalAssets; on loss, attempts
     *      dragon share burning if enabled. Residual loss reduces PPS (no tracked-loss bucket).
     */
    function report()
        public
        virtual
        override(TokenizedStrategy)
        nonReentrant
        onlyKeepers
        returns (uint256 profit, uint256 loss)
    {
        // Cache storage pointer since its used repeatedly.
        StrategyData storage S = super._strategyStorage();

        uint256 newTotalAssets = IBaseStrategy(address(this)).harvestAndReport();
        uint256 oldTotalAssets = _totalAssets(S);
        address _dragonRouter = S.dragonRouter;

        if (newTotalAssets > oldTotalAssets) {
            unchecked {
                profit = newTotalAssets - oldTotalAssets;
            }
            uint256 sharesToMint = _convertToShares(S, profit, Math.Rounding.Floor);

            // mint the shares to the dragon router
            _mint(S, _dragonRouter, sharesToMint);
            emit DonationMinted(_dragonRouter, profit);
        } else {
            unchecked {
                loss = oldTotalAssets - newTotalAssets;
            }

            if (loss != 0) {
                // Handle loss protection
                _handleDragonLossProtection(S, loss);
            }
        }

        // Update the new total assets value
        S.totalAssets = newTotalAssets;
        S.lastReport = uint96(block.timestamp);

        emit Reported(profit, loss);
    }

    /**
     * @dev Internal function to handle loss protection for dragon principal
     * @param S Storage struct pointer to access strategy's storage variables
     * @param loss The amount of loss in terms of asset to protect against
     *
     * If burning is enabled, this function will try to burn shares from the dragon router
     * equivalent to the loss amount.
     */
    function _handleDragonLossProtection(StrategyData storage S, uint256 loss) internal {
        if (S.enableBurning) {
            // Convert loss to shares that should be burned
            uint256 sharesToBurn = _convertToShares(S, loss, Math.Rounding.Ceil);

            // Can only burn up to available shares from dragon router
            uint256 sharesBurned = Math.min(sharesToBurn, S.balances[S.dragonRouter]);

            if (sharesBurned > 0) {
                // Convert shares to assets BEFORE burning to get correct value
                uint256 assetValueBurned = _convertToAssets(S, sharesBurned, Math.Rounding.Floor);

                // Burn shares from dragon router
                _burn(S, S.dragonRouter, sharesBurned);
                emit DonationBurned(S.dragonRouter, assetValueBurned);
            }
        }
    }
}
