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
        uint256 totalValueDebt; // Track ETH value owed to users only
        uint256 lastReportedRate; // Track the last reported rate
        uint256 dragonValueDebt; // Track the ETH value owed to dragon router
    }

    // exchange rate storage slot
    bytes32 private constant YIELD_SKIMMING_STORAGE_SLOT = keccak256("octant.yieldSkimming.exchangeRate");

    /// @dev Event emitted when harvest is performed
    event Harvest(address indexed caller, uint256 currentRate);

    /// @dev Events for donation tracking
    event DonationMinted(address indexed dragonRouter, uint256 amount, uint256 exchangeRate);
    event DonationBurned(address indexed dragonRouter, uint256 amount, uint256 exchangeRate);

    /**
     * @notice Deposit assets into the strategy with value debt tracking
     * @dev Implements deposit protection and tracks ETH value debt
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the shares
     * @return shares The amount of shares minted (1 share = 1 ETH value)
     */
    function deposit(uint256 assets, address receiver) external override nonReentrant returns (uint256 shares) {
        // Block deposits during vault insolvency
        _requireVaultSolvency();

        StrategyData storage S = _strategyStorage();
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();
        uint256 currentRate = _currentRateRay();

        // dragon router cannot deposit
        require(receiver != S.dragonRouter, "Dragon cannot deposit");

        // for the first report, we need to set the last reported rate to max
        if (YS.lastReportedRate == 0) {
            YS.lastReportedRate = currentRate;
        }

        // Deposit full balance if using max uint.
        if (assets == type(uint256).max) {
            assets = S.asset.balanceOf(msg.sender);
        }

        // Checking max deposit will also check if shutdown.
        require(assets <= _maxDeposit(S, receiver), "ERC4626: deposit more than max");

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
     * @notice Mint exact shares from the strategy with value debt tracking
     * @dev Implements insolvency protection and tracks ETH value debt
     * @param shares The amount of shares to mint
     * @param receiver The address to receive the shares
     * @return assets The amount of assets deposited (1 share = 1 ETH value)
     */
    function mint(uint256 shares, address receiver) external override nonReentrant returns (uint256 assets) {
        // Block mints during vault insolvency
        _requireVaultSolvency();

        StrategyData storage S = _strategyStorage();
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();

        // dragon router cannot mint
        require(receiver != S.dragonRouter, "Dragon cannot mint");

        uint256 currentRate = _currentRateRay();
        // for the first report, we need to set the last reported rate to max
        if (YS.lastReportedRate == 0) {
            YS.lastReportedRate = currentRate;
        }

        // Checking max mint will also check if shutdown
        require(shares <= _maxMint(S, receiver), "ERC4626: mint more than max");

        // Calculate assets needed based on value (1 share = 1 ETH value)
        assets = shares.mulDiv(WadRayMath.RAY, currentRate, Math.Rounding.Ceil);
        require(assets != 0, "ZERO_ASSETS");

        // Update value debt
        YS.totalValueDebt += shares;

        // Call internal deposit to handle transfers and minting
        _deposit(S, receiver, assets, shares);

        return assets;
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

        // Dragon cannot withdraw during insolvency - must protect users
        _requireDragonSolvency(owner);

        // Calculate actual value returned for debt tracking (before redemption)
        uint256 valueToReturn = shares; // 1 share = 1 ETH value (regardless of actual assets received)

        // Use super.redeem for standard ERC4626 mechanics (allowance, conversion, transfer, etc.)
        assets = super.redeem(shares, receiver, owner, MAX_BPS);

        // Update value debt after successful redemption (only for users)
        if (owner != S.dragonRouter) {
            YS.totalValueDebt = YS.totalValueDebt > valueToReturn ? YS.totalValueDebt - valueToReturn : 0;
            // if actual shares is the total shares, then we can reset the total value debt to 0
            if (shares == _totalSupply(S)) {
                YS.totalValueDebt = 0;
            }
        } else {
            YS.dragonValueDebt = YS.dragonValueDebt > valueToReturn ? YS.dragonValueDebt - valueToReturn : 0;
        }
        // Dragon withdrawals don't affect user debt tracking

        return assets;
    }

    /**
     * @notice Withdraw assets from the strategy with value debt tracking
     * @dev Calculates shares needed for the asset amount requested
     * @param assets The amount of assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The address whose shares are being redeemed
     * @param maxLoss The maximum acceptable loss in basis points
     * @return shares The amount of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public override nonReentrant returns (uint256 shares) {
        StrategyData storage S = _strategyStorage();
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();

        // Dragon cannot withdraw during insolvency - must protect users
        _requireDragonSolvency(owner);

        // Convert assets to shares using solvency-aware logic
        shares = _convertToShares(S, assets, Math.Rounding.Ceil);

        // Calculate actual value returned for debt tracking (before withdrawal)
        uint256 valueToReturn = shares; // 1 share = 1 ETH value

        // Use super.withdraw for standard ERC4626 mechanics
        uint256 actualShares = super.withdraw(assets, receiver, owner, maxLoss);

        // Update value debt after successful withdrawal (only for users)
        if (owner != S.dragonRouter) {
            YS.totalValueDebt = YS.totalValueDebt > valueToReturn ? YS.totalValueDebt - valueToReturn : 0;
            // if actual shares is the total shares, then we can reset the total value debt to 0
            if (actualShares == _totalSupply(S)) {
                YS.totalValueDebt = 0;
            }
        } else {
            YS.dragonValueDebt = YS.dragonValueDebt > valueToReturn ? YS.dragonValueDebt - valueToReturn : 0;
        }

        return actualShares;
    }

    /**
     * @notice Withdraw assets from the strategy with default maxLoss
     * @dev Wrapper that calls the full withdraw function with 0 maxLoss
     * @param assets The amount of assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The address whose shares are being redeemed
     * @return shares The amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {
        return withdraw(assets, receiver, owner, 0);
    }

    /**
     * @notice Get the total ETH value debt owed to users
     * @return The total value debt
     */
    function getTotalValueDebt() external view returns (uint256) {
        return _strategyYieldSkimmingStorage().totalValueDebt;
    }

    /**
     * @notice Transfer shares with dragon solvency protection
     * @dev Allows dragon transfers when solvent, blocks during insolvency
     * @param to The address to transfer shares to
     * @param amount The amount of shares to transfer
     * @return success Whether the transfer succeeded
     */
    function transfer(address to, uint256 amount) external override returns (bool success) {
        StrategyData storage S = _strategyStorage();

        // Dragon can only transfer when vault is solvent
        _requireDragonSolvency(msg.sender);

        // Handle debt rebalancing if dragon is transferring
        if (msg.sender == S.dragonRouter) {
            _rebalanceDebtOnDragonTransfer(amount);
        }

        // Use base contract logic for actual transfer
        _transfer(S, msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Transfer shares from one address to another with dragon solvency protection
     * @dev Allows dragon transfers when solvent, blocks during insolvency
     * @param from The address to transfer shares from
     * @param to The address to transfer shares to
     * @param amount The amount of shares to transfer
     * @return success Whether the transfer succeeded
     */
    function transferFrom(address from, address to, uint256 amount) external override returns (bool success) {
        StrategyData storage S = _strategyStorage();

        // Dragon can only transfer when vault is solvent
        _requireDragonSolvency(from);

        // Handle debt rebalancing if dragon is transferring
        if (from == S.dragonRouter) {
            _rebalanceDebtOnDragonTransfer(amount);
        }

        // Use base contract logic for actual transfer
        _spendAllowance(S, from, msg.sender, amount);
        _transfer(S, from, to, amount);
        return true;
    }

    /**
     * @inheritdoc TokenizedStrategy
     * @dev Overrides report to handle yield appreciation and loss recovery using value debt approach.
     *
     * Key behaviors:
     * 1. **Value Debt Tracking**: Compares current total value vs user debt (totalValueDebt only)
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
        // Compare current value to user debt only (dragon shares are pure profit buffer)

        if (currentValue > YS.totalValueDebt + YS.dragonValueDebt) {
            // Yield captured! Mint profit shares to dragon
            uint256 profitValue = currentValue > YS.totalValueDebt + YS.dragonValueDebt
                ? currentValue - YS.totalValueDebt - YS.dragonValueDebt
                : 0;

            uint256 profitShares = profitValue; // 1 share = 1 ETH value

            // Convert profit value to assets for reporting
            profit = profitValue.mulDiv(WadRayMath.RAY, currentRate);

            _mint(S, S.dragonRouter, profitShares);

            // update the dragon value debt
            YS.dragonValueDebt += profitValue;

            emit DonationMinted(S.dragonRouter, profitShares, currentRate.rayToWad());
        } else if (currentValue < YS.totalValueDebt + YS.dragonValueDebt && currentRate < YS.lastReportedRate) {
            // Loss - burn dragon shares first
            uint256 lossValue = YS.totalValueDebt + YS.dragonValueDebt - currentValue;
            uint256 dragonBalance = _balanceOf(S, S.dragonRouter);

            if (dragonBalance > 0) {
                uint256 dragonBurn = Math.min(lossValue, dragonBalance);

                // Convert loss value to assets for reporting
                loss = lossValue.mulDiv(WadRayMath.RAY, currentRate);

                _burn(S, S.dragonRouter, dragonBurn);

                // update the dragon value debt
                YS.dragonValueDebt -= dragonBurn;

                emit DonationBurned(S.dragonRouter, dragonBurn, currentRate.rayToWad());
            }

            YS.lastReportedRate = currentRate;
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
     * @dev Converts assets to shares using value debt approach with solvency awareness
     * @param S Strategy storage
     * @param assets The amount of assets to convert
     * @param rounding The rounding mode for division
     * @return The amount of shares (1 share = 1 ETH value)
     */
    function _convertToShares(
        StrategyData storage S,
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        uint256 currentRate = _currentRateRay();
        uint256 totalShares = _totalSupply(S);
        uint256 currentVaultValue = S.totalAssets.mulDiv(currentRate, WadRayMath.RAY);

        if (totalShares > 0 && currentVaultValue < totalShares) {
            // Vault insolvent - reverse the proportional calculation
            // If assets get proportionally reduced, shares needed are higher
            return assets.mulDiv(totalShares, S.totalAssets, rounding);
        } else {
            // Vault solvent - normal rate-based conversion
            return assets.mulDiv(currentRate, WadRayMath.RAY, rounding);
        }
    }

    /**
     * @dev Converts shares to assets using value debt approach with solvency awareness
     * @param S Strategy storage
     * @param shares The amount of shares to convert
     * @param rounding The rounding mode for division
     * @return The amount of assets user would actually receive
     */
    function _convertToAssets(
        StrategyData storage S,
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        uint256 currentRate = _currentRateRay();
        uint256 totalShares = _totalSupply(S);
        uint256 currentVaultValue = S.totalAssets.mulDiv(currentRate, WadRayMath.RAY);

        if (totalShares > 0 && currentVaultValue < totalShares) {
            // Vault insolvent - proportional distribution
            return shares.mulDiv(S.totalAssets, totalShares, rounding);
        } else {
            // Vault solvent - normal rate-based conversion
            return shares.mulDiv(WadRayMath.RAY, currentRate, rounding);
        }
    }

    /**
     * @dev Checks if the vault is currently insolvent
     * @return isInsolvent True if vault cannot cover user value debt
     */
    function _isVaultInsolvent() internal view returns (bool isInsolvent) {
        StrategyData storage S = _strategyStorage();
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();
        uint256 currentRate = _currentRateRay();
        uint256 currentVaultValue = S.totalAssets.mulDiv(currentRate, WadRayMath.RAY);

        return YS.totalValueDebt > 0 && currentVaultValue < YS.totalValueDebt;
    }

    /**
     * @dev Rebalances debt tracking when dragon transfers shares
     * @param transferAmount The amount of shares being transferred
     */
    function _rebalanceDebtOnDragonTransfer(uint256 transferAmount) internal {
        YieldSkimmingStorage storage YS = _strategyYieldSkimmingStorage();
        
        // Direct transfer: shares represent ETH value 1:1 in this system
        // Dragon loses debt obligation, users gain debt obligation
        YS.dragonValueDebt -= transferAmount;
        YS.totalValueDebt += transferAmount;
    }

    /**
     * @dev Blocks dragon router from withdrawing during vault insolvency
     * @param account The address to check (only blocks if it's the dragon router)
     */
    function _requireDragonSolvency(address account) internal view {
        StrategyData storage S = _strategyStorage();

        // Only check if account is dragon router
        if (account == S.dragonRouter && _isVaultInsolvent()) {
            revert("Dragon cannot operate during insolvency");
        }
    }

    /**
     * @dev Blocks all operations when vault is insolvent
     */
    function _requireVaultSolvency() internal view {
        if (_isVaultInsolvent()) {
            revert("Cannot operate when vault is insolvent");
        }
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
