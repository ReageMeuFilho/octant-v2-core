// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IBaseStrategy } from "src/core/interfaces/IBaseStrategy.sol";
import { TokenizedStrategy, Math } from "src/core/TokenizedStrategy.sol";
import { WadRayMath } from "src/utils/libs/Maths/WadRay.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYieldSkimmingStrategy } from "src/strategies/yieldSkimming/IYieldSkimmingStrategy.sol";

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
    using WadRayMath for uint256;

    /// @dev The exchange rate at the last harvest, scaled by RAY (1e27)
    struct ExchangeRate {
        uint256 lastRateRay;
    }

    // exchange rate storage slot
    bytes32 private constant EXCHANGE_RATE_STORAGE_SLOT = keccak256("octant.yieldSkimming.exchangeRate");

    /// @dev Event emitted when harvest is performed
    event Harvest(address indexed caller, uint256 currentRate);

    /// @dev Events for donation tracking
    event DonationMinted(address indexed dragonRouter, uint256 amount, uint256 exchangeRate);
    event DonationBurned(address indexed dragonRouter, uint256 amount, uint256 exchangeRate);

    /**
     * @inheritdoc TokenizedStrategy
     * @dev Overrides report to handle asset appreciation in yield-bearing tokens.
     * This implementation specifically:
     * 1. Gets current exchange rate and calculates total ETH value
     * 2. Compares total ETH to current supply to determine profit/loss
     * 3. For profit: mints shares to dragonRouter (feeRecipient)
     * 4. For loss: burns shares from dragonRouter (donationAddress) for protection
     * 5. Updates exchange rate and emits harvest event
     *
     * This approach maintains PPS ≈ 1 by diluting/concentrating shares based on yield.
     */
    function report()
        public
        override(TokenizedStrategy)
        nonReentrant
        onlyKeepers
        returns (uint256 profit, uint256 loss)
    {
        StrategyData storage S = super._strategyStorage();

        uint256 rateNow = _currentRateRay();

        uint256 currentTotalAssets = IBaseStrategy(address(this)).harvestAndReport();

        uint256 totalAssetsBalance = S.asset.balanceOf(address(this));

        if (totalAssetsBalance != currentTotalAssets) {
            // update total assets
            S.totalAssets = totalAssetsBalance;
        }

        uint256 totalETH = totalAssetsBalance.mulDiv(rateNow, WadRayMath.RAY); // asset → ETH
        uint256 supply = _totalSupply(S); // shares denom. in ETH

        if (totalETH > supply) {
            uint256 profitAmount = totalETH - supply; // positive yield
            uint256 lossAmount = S.lossAmount;

            if (profitAmount > lossAmount) {
                // Profit exceeds accumulated losses, mint shares for net profit
                uint256 sharesToMint = _convertToShares(S, profitAmount - lossAmount, Math.Rounding.Floor);

                S.lossAmount = 0; // Clear accumulated losses
                _mint(S, S.dragonRouter, sharesToMint);
                emit DonationMinted(S.dragonRouter, sharesToMint, rateNow.rayToWad());
            } else {
                // Profit doesn't exceed losses, reduce accumulated loss
                S.lossAmount -= profitAmount;
            }
            profit = profitAmount;
            loss = 0;
        } else if (totalETH < supply) {
            // Rare: negative yield (slash). Use loss protection mechanism.
            uint256 lossAmount = supply - totalETH;
            _handleDragonLossProtection(S, lossAmount, rateNow);
            // residual loss (if any) will lower PPS < 1
            profit = 0;
            loss = lossAmount;
        } else {
            // No change
            profit = 0;
            loss = 0;
        }

        _strategyStorageExchangeRate().lastRateRay = rateNow;
        S.lastReport = uint96(block.timestamp);

        emit Harvest(msg.sender, rateNow.rayToWad());
        emit Reported(profit, loss);

        return (profit, loss);
    }

    /**
     * @dev Get the current exchange rate scaled to RAY precision
     * @return The current exchange rate in RAY format (1e27)
     */
    function _currentRateRay() internal view virtual returns (uint256) {
        uint256 exchangeRate = IYieldSkimmingStrategy(address(this)).getCurrentExchangeRate();

        return exchangeRate.wadToRay(); // Convert from WAD (1e18) to RAY (1e27)
    }

    function _convertToShares(
        StrategyData storage,
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        return assets.mulDiv(_currentRateRay(), WadRayMath.RAY, rounding);
    }

    /**
     * @dev Get the last reported exchange rate
     * @return The last exchange rate in RAY format
     */
    function getLastRateRay() external view returns (uint256) {
        return _strategyStorageExchangeRate().lastRateRay;
    }

    /**
     * @dev Get the current exchange rate
     * @return The current exchange rate in RAY format
     */
    function getCurrentRateRay() external view returns (uint256) {
        return _currentRateRay();
    }

    function _strategyStorageExchangeRate() internal pure returns (ExchangeRate storage S) {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = EXCHANGE_RATE_STORAGE_SLOT;
        assembly {
            S.slot := slot
        }
    }

    /**
     * @dev Internal function to handle loss protection for dragon principal
     * @param S Storage struct pointer to access strategy's storage variables
     * @param loss The amount of loss in terms of asset to protect against
     * @param rateNow The current exchange rate for event emission
     *
     * This function accumulates losses in the strategy storage. When future profits occur,
     * they will first offset accumulated losses before minting new shares to dragonRouter.
     * This approach provides better accounting and ensures losses are properly tracked
     * across multiple reporting periods.
     */
    function _handleDragonLossProtection(StrategyData storage S, uint256 loss, uint256 rateNow) internal {
        // Accumulate loss for future offset against profits
        S.lossAmount += loss;

        // Emit event for transparency (even though no shares are burned immediately)
        emit DonationBurned(S.dragonRouter, 0, rateNow.rayToWad());
    }
}
