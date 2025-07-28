// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IBaseStrategy } from "src/core/interfaces/IBaseStrategy.sol";
import { TokenizedStrategy, Math } from "src/core/TokenizedStrategy.sol";
import { WadRayMath } from "src/utils/libs/Maths/WadRay.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYieldSkimmingStrategy } from "src/strategies/yieldSkimming/IYieldSkimmingStrategy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
    using SafeERC20 for ERC20;

    /// @dev Storage for yield skimming strategy
    struct YieldSkimmingStorage {
        uint256 lastRateRay; // Rate from last report (for calculating underlying value changes)
        uint256 recoveryRateRay; // Rate at which users would break even (used for share minting during recovery)
    }

    // exchange rate storage slot
    bytes32 private constant YIELD_SKIMMING_STORAGE_SLOT = keccak256("octant.yieldSkimming.exchangeRate");

    /// @dev Event emitted when harvest is performed
    event Harvest(address indexed caller, uint256 currentRate);

    /// @dev Events for donation tracking
    event DonationMinted(address indexed dragonRouter, uint256 amount, uint256 exchangeRate);
    event DonationBurned(address indexed dragonRouter, uint256 amount, uint256 exchangeRate);

    /**
     * @inheritdoc TokenizedStrategy
     * @dev Overrides report to handle yield appreciation and loss recovery in yield-bearing tokens.
     *
     * Key behaviors:
     * 1. **Exchange Rate Tracking**: Compares current vs. previous exchange rates to detect yield changes
     * 2. **Loss Handling**: When exchange rates drop, tracks losses in `S.lossAmount` and attempts
     *    to burn dragonRouter shares for protection
     * 3. **Recovery Logic**: During recovery from losses, only mints shares for excess profit beyond
     *    full loss recovery to ensure depositors can withdraw their initial underlying value
     * 4. **Yield Capture**: For regular profits or excess recovery profits, mints shares to dragonRouter
     * 5. **Rate Persistence**: Updates `lastRateRay` for future comparisons
     *
     * @return profit The profit in assets (converted from underlying appreciation)
     * @return loss The loss in assets (converted from underlying depreciation)
     */
    function report()
        public
        override(TokenizedStrategy)
        nonReentrant
        onlyKeepers
        returns (uint256 profit, uint256 loss)
    {
        StrategyData storage S = super._strategyStorage();
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();

        // Cache frequently used values
        uint256 rateNow = _currentRateRay();
        uint256 lastRateRay = YS.lastRateRay;

        uint256 previousValue = S.totalAssets.mulDiv(lastRateRay, WadRayMath.RAY);

        // Update total assets from harvest
        uint256 currentTotalAssets = IBaseStrategy(address(this)).harvestAndReport();
        uint256 totalAssetsBalance = S.asset.balanceOf(address(this));
        if (totalAssetsBalance != currentTotalAssets) {
            S.totalAssets = totalAssetsBalance;
        }

        uint256 currentValue = S.totalAssets.mulDiv(rateNow, WadRayMath.RAY); // asset → underlying value

        // Handle total loss scenario (rate = 0)
        if (rateNow == 0) {
            loss = S.totalAssets;
            uint256 burnable = _handleDragonLossProtection(S, loss, 0);
            S.lossAmount += loss - burnable;
            _finalizeReport(S, 0, rateNow);
            emit Reported(0, loss);
            return (0, loss);
        }

        // Calculate profit/loss based on underlying value changes
        if (currentValue > previousValue) {
            uint256 underlyingGain = currentValue - previousValue;
            profit = (underlyingGain * WadRayMath.RAY) / rateNow;

            if (S.lossAmount > 0) {
                // Handle loss recovery scenario
                uint256 lossInUnderlying = (S.lossAmount * lastRateRay) / WadRayMath.RAY;

                if (underlyingGain > lossInUnderlying) {
                    // Full recovery + excess profit
                    S.lossAmount = 0;
                    uint256 excessUnderlying = underlyingGain - lossInUnderlying;
                    if (excessUnderlying > 0) {
                        _handleDonationMinting(S, rateNow);
                        // Update recovery rate now that we're fully recovered and have excess profit
                        YS.recoveryRateRay = rateNow;
                    }
                    profit = excessUnderlying.mulDiv(WadRayMath.RAY, rateNow);
                } else {
                    // Partial recovery
                    S.lossAmount = ((lossInUnderlying - underlyingGain) * WadRayMath.RAY) / rateNow;
                    profit = 0;
                }
            } else if (profit > 0) {
                // Regular profit case - no losses, so mint shares and update recovery rate
                _handleDonationMinting(S, rateNow);
                YS.recoveryRateRay = rateNow;
            }
        } else if (currentValue < previousValue) {
            // Negative yield (slashing event)
            uint256 underlyingLoss = previousValue - currentValue;
            loss = (underlyingLoss * WadRayMath.RAY) / rateNow;

            uint256 burnable = _handleDragonLossProtection(S, loss, rateNow.rayToWad());

            // Update total loss amount
            uint256 oldLossInUnderlying = (S.lossAmount * lastRateRay) / WadRayMath.RAY;
            uint256 adjustedOldLoss = (oldLossInUnderlying * WadRayMath.RAY) / rateNow;
            S.lossAmount = adjustedOldLoss + (loss - burnable);
        }

        _finalizeReport(S, rateNow, rateNow);
        emit Reported(profit, loss);
        return (profit, loss);
    }

    /**
     * @dev Get the last reported exchange rate
     * @return The last exchange rate in RAY format
     */
    function getLastRateRay() external view returns (uint256) {
        return _strategyYieldSkimmingStorage().lastRateRay;
    }

    /**
     * @dev Get the current exchange rate
     * @return The current exchange rate in RAY format
     */
    function getCurrentRateRay() external view returns (uint256) {
        return _currentRateRay();
    }

    /**
     * @dev Handles burning dragon router shares for loss protection
     * @param S The strategy data storage
     * @param lossAmount The amount of loss in assets
     * @param exchangeRate The current exchange rate (for events)
     * @return burnable The amount that was actually burned
     */
    function _handleDragonLossProtection(
        StrategyData storage S,
        uint256 lossAmount,
        uint256 exchangeRate
    ) internal returns (uint256 burnable) {
        uint256 dragonRouterAssets = _convertToAssets(S, _balanceOf(S, S.dragonRouter), Math.Rounding.Floor);

        burnable = Math.min(lossAmount, dragonRouterAssets);

        if (burnable > 0) {
            uint256 sharesToBurn = super._convertToShares(S, burnable, Math.Rounding.Floor);
            _burn(S, S.dragonRouter, sharesToBurn);
            emit DonationBurned(S.dragonRouter, burnable, exchangeRate);
        }

        return burnable;
    }

    /**
     * @dev Handles minting shares to dragon router for profit capture
     * @param S The strategy data storage
     * @param currentRate The current exchange rate
     */
    function _handleDonationMinting(StrategyData storage S, uint256 currentRate) internal {
        uint256 tunedM = _calculateTunedM(_totalSupply(S), S.totalAssets, currentRate);
        if (tunedM > 0) {
            _mint(S, S.dragonRouter, tunedM);
            emit DonationMinted(S.dragonRouter, tunedM, currentRate.rayToWad());
        }
    }

    /**
     * @dev Finalizes the report by updating timestamps and rates
     * @param S The strategy data storage
     * @param rateToStore The exchange rate to store
     * @param rateForEvent The exchange rate for the harvest event
     */
    function _finalizeReport(StrategyData storage S, uint256 rateToStore, uint256 rateForEvent) internal {
        S.lastReport = uint96(block.timestamp);
        _strategyYieldSkimmingStorage().lastRateRay = rateToStore;
        emit Harvest(msg.sender, rateForEvent.rayToWad());
    }

    function _deposit(StrategyData storage S, address receiver, uint256 assets, uint256 shares) internal override {
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();

        // // tracking the last rate ray for the first deposit
        if (YS.recoveryRateRay == 0) {
            uint256 currentRate = _currentRateRay();
            YS.lastRateRay = currentRate;
            YS.recoveryRateRay = currentRate;
        }

        // Cache storage variables used more than once.
        ERC20 _asset = S.asset;

        // Need to transfer before minting or ERC777s could reenter.
        _asset.safeTransferFrom(msg.sender, address(this), assets);

        // We can deploy the full loose balance currently held.
        IBaseStrategy(address(this)).deployFunds(_asset.balanceOf(address(this)));

        // Adjust total Assets.
        S.totalAssets += assets;

        // mint shares
        _mint(S, receiver, shares);

        // Add minted shares to principal

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @dev Convert assets to shares
     * @param S The strategy data storage
     * @param assets The amount of assets to convert
     * @param rounding The rounding mode
     * @dev This function is overridden to account for the loss amount
     * @return The amount of shares
     */
    function _convertToShares(
        StrategyData storage S,
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        return _convertToSharesWithLoss(S, assets, rounding);
    }

    /**
     * @dev Get the current exchange rate scaled to RAY precision
     * @return The current exchange rate in RAY format (1e27)
     */
    function _currentRateRay() internal view virtual returns (uint256) {
        uint256 exchangeRate = IYieldSkimmingStrategy(address(this)).getCurrentExchangeRate();
        uint256 exchangeRateDecimals = IYieldSkimmingStrategy(address(this)).decimalsOfExchangeRate();

        // Convert directly to RAY (27 decimals) to avoid precision loss
        if (exchangeRateDecimals == 27) {
            return exchangeRate;
        } else if (exchangeRateDecimals < 27) {
            return exchangeRate * 10 ** (27 - exchangeRateDecimals);
        } else {
            return exchangeRate / 10 ** (exchangeRateDecimals - 27);
        }
    }
    function _calculateTunedM(
        uint256 totalSupplyAmount,
        uint256 totalAssetsAmount,
        uint256 currentRate
    ) internal view returns (uint256) {
        if (totalSupplyAmount == 0) return 0;

        YieldSkimmingStorage storage S = _strategyYieldSkimmingStorage();
        uint256 recoveryRate = S.recoveryRateRay;

        // Only mint shares if current rate exceeds the recovery rate (break-even point)
        if (currentRate > recoveryRate && recoveryRate > 0) {
            // Calculate how many shares we need to mint for appreciation beyond recovery
            // M = totalSupply * (currentRate - recoveryRate) / recoveryRate
            uint256 rateDifference = currentRate - recoveryRate;
            return totalSupplyAmount.mulDiv(rateDifference, recoveryRate);
        }

        // Second, handle direct asset increases (airdrops) when rate unchanged
        // To maintain PPS = currentRate, we need totalAssets * currentRate = totalSupply
        uint256 expectedSupply = totalAssetsAmount.mulDiv(currentRate, WadRayMath.RAY);
        if (expectedSupply > totalSupplyAmount) {
            return expectedSupply - totalSupplyAmount;
        }
        return 0;
    }

    function _strategyYieldSkimmingStorage() internal pure returns (YieldSkimmingStorage storage S) {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = YIELD_SKIMMING_STORAGE_SLOT;
        assembly {
            S.slot := slot
        }
    }
}
