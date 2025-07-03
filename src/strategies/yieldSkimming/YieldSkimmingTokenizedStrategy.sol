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

    /// @dev The exchange rate at the last harvest, scaled by RAY (1e27)
    struct YieldSkimmingStorage {
        uint256 lastRateRay;
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

        // airdropping tokens to the strategy results in profit to the dragon router
        if (totalAssetsBalance != currentTotalAssets) {
            // update total assets
            S.totalAssets = totalAssetsBalance;
        }

        uint256 totalETH = totalAssetsBalance.mulDiv(rateNow, WadRayMath.RAY); // asset → ETH
        uint256 supply = _totalSupply(S); // shares denom. in ETH

        if (totalETH > supply) {
            profit = totalETH - supply; // positive yield

            _mint(S, S.dragonRouter, profit);

            emit DonationMinted(S.dragonRouter, profit, rateNow.rayToWad());
            // do not burn shares if the rate is the same as the last rate
        } else if (totalETH < supply) {
            // Rare: negative yield (slash). Use loss protection mechanism.
            loss = supply - totalETH;
            _handleDragonLossProtection(S, loss);
        }

        S.lastReport = uint96(block.timestamp);
        _strategyYieldSkimmingStorage().lastRateRay = rateNow;

        emit Harvest(msg.sender, rateNow.rayToWad());

        uint256 profitInAssets = rateNow == 0 ? 0 : profit.mulDiv(WadRayMath.RAY, rateNow);

        // if the rate is 0, we need to use the total assets balance as the loss
        uint256 lossInAssets = rateNow == 0 ? totalAssetsBalance : loss.mulDiv(WadRayMath.RAY, rateNow);
        emit Reported(profitInAssets, lossInAssets);

        return (profitInAssets, lossInAssets);
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

    function _deposit(StrategyData storage S, address receiver, uint256 assets, uint256 shares) internal override {
        // tracking the last rate ray for the first deposit
        if (_strategyYieldSkimmingStorage().lastRateRay == 0) {
            _strategyYieldSkimmingStorage().lastRateRay = _currentRateRay();
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

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @dev Get the current exchange rate scaled to RAY precision
     * @return The current exchange rate in RAY format (1e27)
     */
    function _currentRateRay() internal view virtual returns (uint256) {
        uint256 exchangeRate = IYieldSkimmingStrategy(address(this)).getCurrentExchangeRate();
        uint256 exchangeRateDecimals = IYieldSkimmingStrategy(address(this)).decimalsOfExchangeRate();

        uint256 scaledRate = exchangeRateDecimals == 18
            ? exchangeRate
            : exchangeRateDecimals < 18
                ? exchangeRate * 10 ** (18 - exchangeRateDecimals)
                : exchangeRate / 10 ** (exchangeRateDecimals - 18);
        return scaledRate.wadToRay();
    }

    function _convertToShares(
        StrategyData storage,
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        return assets.mulDiv(_currentRateRay(), WadRayMath.RAY, rounding);
    }

    function _strategyYieldSkimmingStorage() internal pure returns (YieldSkimmingStorage storage S) {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = YIELD_SKIMMING_STORAGE_SLOT;
        assembly {
            S.slot := slot
        }
    }

    /**
     * This function handles loss protection by burning shares from the dragon router if burning is enabled.
     * Since yield skimming strategies don't track losses, they either burn shares or do nothing.
     * When burning is enabled, it burns up to the loss amount from dragonRouter, limited by the router's
     * actual balance. This effectively socializes the loss among all shareholders by
     * burning shares from the donation recipient rather than reducing the value of all shares.
     */
    function _handleDragonLossProtection(StrategyData storage S, uint256 loss) internal {
        if (S.enableBurning) {
            // Can only burn up to available shares
            uint256 sharesBurned = Math.min(loss, S.balances[S.dragonRouter]);

            if (sharesBurned > 0) {
                // Burn shares from dragon router
                _burn(S, S.dragonRouter, sharesBurned);
            }
        }
    }
}
