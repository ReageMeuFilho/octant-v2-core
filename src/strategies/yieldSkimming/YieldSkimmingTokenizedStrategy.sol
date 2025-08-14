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
        uint256 totalValueDebt; // Track ETH value owed to users
        uint256 dragonValueDebt; // ETH value allocated to dragon
    }

    // exchange rate storage slot
    bytes32 private constant YIELD_SKIMMING_STORAGE_SLOT = keccak256("octant.yieldSkimming.exchangeRate");

    /// @dev Event emitted when harvest is performed
    event Harvest(address indexed caller, uint256 currentRate);

    /// @dev Events for donation tracking
    event DonationMinted(address indexed dragonRouter, uint256 amount, uint256 exchangeRate);
    event DonationBurned(address indexed dragonRouter, uint256 amount, uint256 exchangeRate);

    /**
     * @dev Modifier to protect deposits when strategy is in loss state
     * Ensures dragon buffer is sufficient to cover any current losses
     */
    modifier depositProtection() {
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();
        StrategyData storage S = _strategyStorage();

        uint256 currentRate = _currentRateRay();
        uint256 totalAssets = S.totalAssets;
        uint256 currentValue = totalAssets.mulDiv(currentRate, WadRayMath.RAY);
        uint256 totalOwedValue = YS.totalValueDebt + YS.dragonValueDebt;

        if (currentValue < totalOwedValue) {
            // Loss state - check if dragon buffer sufficient
            uint256 valueLoss = totalOwedValue - currentValue;
            require(YS.dragonValueDebt >= valueLoss, "Insufficient dragon buffer for deposits");
        }
        _;
    }

    /**
     * @notice Deposit assets into the strategy with value debt tracking
     * @dev Implements deposit protection and tracks ETH value debt
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the shares
     * @return shares The amount of shares minted (1 share = 1 ETH value)
     */
    function deposit(
        uint256 assets,
        address receiver
    ) external override nonReentrant depositProtection returns (uint256 shares) {
        StrategyData storage S = _strategyStorage();
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();

        // Deposit full balance if using max uint.
        if (assets == type(uint256).max) {
            assets = S.asset.balanceOf(msg.sender);
        }

        // Checking max deposit will also check if shutdown.
        require(assets <= _maxDeposit(S, receiver), "ERC4626: deposit more than max");

        uint256 currentRate = _currentRateRay();
        
        // Issue shares based on value (1 share = 1 ETH value)
        shares = assets.mulDiv(currentRate, WadRayMath.RAY);
        require(shares != 0, "ZERO_SHARES");

        // Update value debt
        YS.totalValueDebt += shares;

        // Call internal deposit to handle transfers and minting
        _deposit(S, receiver, assets, shares);

        return shares;
    }

    /**
     * @notice Redeem shares from the strategy with value debt tracking
     * @dev Shares represent ETH value (1 share = 1 ETH value)
     * @param shares The amount of shares to redeem
     * @param receiver The address to receive the assets
     * @param owner The address whose shares are being redeemed
     * @return assets The amount of assets returned
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external override nonReentrant returns (uint256 assets) {
        StrategyData storage S = _strategyStorage();
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();

        // Check share ownership
        require(_balanceOf(S, owner) >= shares, "ERC4626: redeem more than max");

        // If msg.sender is not owner, check allowance
        if (msg.sender != owner) {
            _spendAllowance(S, owner, msg.sender, shares);
        }

        uint256 currentRate = _currentRateRay();
        uint256 totalShares = _totalSupply(S);

        // Shares represent ETH value
        uint256 valueToReturn = shares; // 1 share = 1 ETH value

        // Convert value to assets at current rate
        assets = valueToReturn.mulDiv(WadRayMath.RAY, currentRate);

        // Check available assets
        uint256 availableAssets = S.totalAssets;
        if (assets > availableAssets) {
            // Proportional distribution if insufficient
            assets = shares.mulDiv(availableAssets, totalShares);
            valueToReturn = assets.mulDiv(currentRate, WadRayMath.RAY);
        }

        // Update value debt
        if (owner == S.dragonRouter) {
            YS.dragonValueDebt = YS.dragonValueDebt > valueToReturn ? YS.dragonValueDebt - valueToReturn : 0;
        } else {
            YS.totalValueDebt = YS.totalValueDebt > valueToReturn ? YS.totalValueDebt - valueToReturn : 0;
        }

        // Burn shares
        _burn(S, owner, shares);

        // Update total assets
        S.totalAssets -= assets;

        // Withdraw from strategy and transfer
        IBaseStrategy(address(this)).freeFunds(assets);
        S.asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @inheritdoc TokenizedStrategy
     * @dev Overrides report to handle yield appreciation and loss recovery using value debt approach.
     *
     * Key behaviors:
     * 1. **Value Debt Tracking**: Compares current total value vs owed value (totalValueDebt + dragonValueDebt)
     * 2. **Profit Capture**: When current value exceeds owed value, mints shares to dragonRouter
     * 3. **Loss Protection**: When current value is less than owed value, burns dragon shares
     * 4. **User Protection**: If dragon buffer insufficient, reduces user value debt proportionally
     *
     * @return profit The profit in assets
     * @return loss The loss in assets
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

        // Update total assets from harvest
        uint256 currentTotalAssets = IBaseStrategy(address(this)).harvestAndReport();
        uint256 totalAssetsBalance = S.asset.balanceOf(address(this));
        if (totalAssetsBalance != currentTotalAssets) {
            S.totalAssets = totalAssetsBalance;
        }

        uint256 currentRate = _currentRateRay();
        uint256 totalAssets = S.totalAssets;
        uint256 currentValue = totalAssets.mulDiv(currentRate, WadRayMath.RAY);
        uint256 totalOwedValue = YS.totalValueDebt + YS.dragonValueDebt;

        if (currentValue > totalOwedValue) {
            // Yield captured!
            uint256 profitValue = currentValue - totalOwedValue;
            uint256 profitShares = profitValue; // 1 share = 1 ETH value

            // Convert profit value to assets for reporting
            profit = profitValue.mulDiv(WadRayMath.RAY, currentRate);

            _mint(S, S.dragonRouter, profitShares);
            YS.dragonValueDebt += profitValue;

            emit DonationMinted(S.dragonRouter, profitShares, currentRate.rayToWad());
        } else if (currentValue < totalOwedValue && YS.dragonValueDebt > 0) {
            // Loss - burn dragon shares to protect users
            uint256 lossValue = totalOwedValue - currentValue;
            uint256 dragonBurn = Math.min(lossValue, YS.dragonValueDebt);

            // Convert loss value to assets for reporting
            loss = lossValue.mulDiv(WadRayMath.RAY, currentRate);

            _burn(S, S.dragonRouter, dragonBurn);
            YS.dragonValueDebt -= dragonBurn;

            emit DonationBurned(S.dragonRouter, dragonBurn, currentRate.rayToWad());

            // If loss exceeds dragon buffer, reduce user value debt
            if (lossValue > dragonBurn) {
                uint256 userLoss = lossValue - dragonBurn;
                YS.totalValueDebt = YS.totalValueDebt > userLoss ? YS.totalValueDebt - userLoss : 0;
            }
        }

        // Update last report timestamp
        S.lastReport = uint96(block.timestamp);
        emit Harvest(msg.sender, currentRate.rayToWad());
        emit Reported(profit, loss);

        return (profit, loss);
    }

    /**
     * @dev Internal deposit function that handles asset transfers and share minting
     * @param S The strategy data storage
     * @param receiver The address that will receive the minted shares
     * @param assets The amount of assets being deposited
     * @param shares The amount of shares to mint
     */
    function _deposit(StrategyData storage S, address receiver, uint256 assets, uint256 shares) internal override {
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
     * @notice Withdraw assets from the strategy
     * @dev Converts assets to shares and calls redeem
     * @param assets The amount of assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The address whose shares are being redeemed
     * @return shares The amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {
        uint256 currentRate = _currentRateRay();
        shares = assets.mulDiv(currentRate, WadRayMath.RAY, Math.Rounding.Ceil);

        uint256 actualAssets = this.redeem(shares, receiver, owner);
        require(actualAssets >= assets, "Insufficient assets");

        return shares;
    }

    /**
     * @dev Converts assets to shares using value debt approach
     * @param assets The amount of assets to convert
     * @param rounding The rounding mode for division
     * @return The amount of shares (1 share = 1 ETH value)
     */
    function _convertToShares(
        StrategyData storage,
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        uint256 currentRate = _currentRateRay();
        return assets.mulDiv(currentRate, WadRayMath.RAY, rounding);
    }

    /**
     * @dev Converts shares to assets using value debt approach
     * @param shares The amount of shares to convert
     * @param rounding The rounding mode for division
     * @return The amount of assets
     */
    function _convertToAssets(
        StrategyData storage,
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        uint256 currentRate = _currentRateRay();
        // shares represent ETH value, convert to assets
        return shares.mulDiv(WadRayMath.RAY, currentRate, rounding);
    }

    /**
     * @notice Get the total ETH value debt owed to users
     * @return The total value debt
     */
    function getTotalValueDebt() external view returns (uint256) {
        return _strategyYieldSkimmingStorage().totalValueDebt;
    }

    /**
     * @notice Get the ETH value debt allocated to dragon router
     * @return The dragon value debt
     */
    function getDragonValueDebt() external view returns (uint256) {
        return _strategyYieldSkimmingStorage().dragonValueDebt;
    }

    /**
     * @notice Get the total owed value (user debt + dragon debt)
     * @return The total owed value
     */
    function getTotalOwedValue() external view returns (uint256) {
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();
        return YS.totalValueDebt + YS.dragonValueDebt;
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

    function _strategyYieldSkimmingStorage() internal pure returns (YieldSkimmingStorage storage S) {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = YIELD_SKIMMING_STORAGE_SLOT;
        assembly {
            S.slot := slot
        }
    }
}
