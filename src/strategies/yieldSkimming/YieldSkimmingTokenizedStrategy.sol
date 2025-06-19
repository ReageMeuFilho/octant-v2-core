// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IBaseStrategy } from "src/core/interfaces/IBaseStrategy.sol";
import { TokenizedStrategy, Math } from "src/core/TokenizedStrategy.sol";
import { WadRayMath } from "src/utils/libs/Maths/WadRay.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface IExchangeRate {
    function getCurrentExchangeRate() external view returns (uint256);
}

interface IWstETH {
    function stEthPerToken() external view returns (uint256);
}

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
    function report() public override(TokenizedStrategy) returns (uint256 profit, uint256 loss) {
        StrategyData storage S = super._strategyStorage();

        uint256 rateNow = _currentRateRay();

        IBaseStrategy(address(this)).harvestAndReport();

        uint256 totalETH = S.asset.balanceOf(address(this)).mulDiv(rateNow, WadRayMath.RAY); // asset → ETH
        uint256 supply = _totalSupply(S); // shares denom. in ETH

        if (totalETH > supply) {
            uint256 profitAmount = totalETH - supply; // positive yield
            _mint(S, S.dragonRouter, profitAmount); // Invariant B: PPS↦1
            profit = profitAmount;
            loss = 0;
        } else if (totalETH < supply) {
            // Rare: negative yield (slash). Burn dragon router shares first.
            uint256 lossAmount = supply - totalETH;
            uint256 dragonRouterBal = S.balances[S.dragonRouter];
            uint256 burnAmt = lossAmount > dragonRouterBal ? dragonRouterBal : lossAmount;
            if (burnAmt > 0) _burn(S, S.dragonRouter, burnAmt);
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

        emit Harvest(msg.sender, rateNow);
        emit Reported(profit, loss);

        return (profit, loss);
    }

    /**
     * @dev Get the current exchange rate scaled to RAY precision
     * @return The current exchange rate in RAY format (1e27)
     */
    function _currentRateRay() internal view virtual returns (uint256) {
        uint256 exchangeRate = IExchangeRate(address(this)).getCurrentExchangeRate();

        return exchangeRate.wadToRay(); // Convert from WAD (1e18) to RAY (1e27)
    }

    function _getCurrentExchangeRate() internal view virtual returns (uint256) {
        address assetAddress = address(_strategyStorage().asset);
        return IWstETH(assetAddress).stEthPerToken();
    }

    function _convertToShares(
        StrategyData storage,
        uint256 assets,
        Math.Rounding
    ) internal view virtual override returns (uint256) {
        return (assets * _currentRateRay()) / WadRayMath.RAY;
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
