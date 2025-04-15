// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { BaseStrategy } from "../DragonBaseStrategy.sol";
import { DragonTokenizedStrategy } from "../DragonTokenizedStrategy.sol";

/**
 * @title YieldDonatingTokenizedStrategy
 * @notice A specialized version of DragonTokenizedStrategy designed for productive assets to generate and donate profits to the donation address
 */
contract YieldDonatingTokenizedStrategy is DragonTokenizedStrategy {
    using Math for uint256;

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function report()
        public
        virtual
        override(TokenizedStrategy, ITokenizedStrategy)
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

        emit Reported(
            profit,
            loss,
            0, // Protocol fees
            0 // Performance Fees
        );
    }

    /**
     * @dev Internal function to handle loss protection for dragon principal
     * @param loss The amount of loss to protect against
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
