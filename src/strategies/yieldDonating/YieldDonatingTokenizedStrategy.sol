// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;
import { TokenizedStrategy, Math } from "src/core/TokenizedStrategy.sol";
import { IBaseStrategy } from "src/core/interfaces/IBaseStrategy.sol";
/**
 * @title YieldDonatingTokenizedStrategy
 * @author octant.finance
 * @notice A specialized version of DragonTokenizedStrategy designed for productive assets to generate and donate profits to the dragon router
 * @dev This strategy implements a yield donation mechanism by:
 *      - Calling harvestAndReport to collect all profits from the underlying strategy
 *      - Converting profits into shares using the standard conversion
 *      - Minting these shares directly to the dragonRouter address
 *      - Protecting against losses by burning shares from dragonRouter
 */
contract YieldDonatingTokenizedStrategy is TokenizedStrategy {
    /**
     * @inheritdoc TokenizedStrategy
     * @dev This implementation overrides the base report function to mint profit-derived shares to dragonRouter.
     * When the strategy generates profits (newTotalAssets > oldTotalAssets), the difference is converted to shares
     * and minted to the dragonRouter. When losses occur, those losses can be offset by burning shares from dragonRouter
     * through the _handleDragonLossProtection mechanism.
     */
    function report()
        public
        virtual
        override(TokenizedStrategy)
        nonReentrant
        onlyKeepers
        returns (
            uint256 profit,
            uint256 loss // TODO: check if this is of in the multistrategy vaults or if we need to pass it the fee amounts as zero anyway
        )
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
            _mint(S, _dragonRouter, _convertToShares(S, profit, Math.Rounding.Floor));
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
     * This function calculates how many shares would be equivalent to the loss amount,
     * then burns up to that amount of shares from dragonRouter, limited by the router's
     * actual balance. This effectively socializes the loss among all shareholders by
     * burning shares from the donation recipient rather than reducing the value of all shares.
     */
    function _handleDragonLossProtection(StrategyData storage S, uint256 loss) internal {
        // Can only burn up to available shares
        uint256 sharesBurned = Math.min(_convertToShares(S, loss, Math.Rounding.Floor), S.balances[S.dragonRouter]);

        if (sharesBurned > 0) {
            // Burn shares from dragon router
            _burn(S, S.dragonRouter, sharesBurned);
        }
    }
}
