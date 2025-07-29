# YieldSkimmingTokenizedStrategy Changes - Loss Recovery Fix

## Overview

This document outlines the critical changes made to the YieldSkimmingTokenizedStrategy to fix a broken loss recovery mechanism. The old version allowed new depositors to profit unfairly during recovery periods, breaking the fundamental invariant that depositors should never be able to withdraw more underlying asset value than they deposited.

## The Problem

### Broken Invariant in Old Version
When the strategy experienced a loss (e.g., from a slashing event), the old implementation had a flaw:
- New depositors during a loss period would receive shares at the normal exchange rate
- When the strategy recovered, these new depositors could withdraw more underlying value than they deposited
- This created an unfair advantage for depositors who entered during losses

### Example Scenario
1. Strategy starts with 100 assets and 100 shares (1:1 ratio)
2. Slashing event causes 20% loss in underlying value
3. New depositor deposits 100 assets and receives 100 shares (incorrect!)
4. Strategy recovers to original exchange rate
5. New depositor can now withdraw 120 underlying value (20% profit)

## Key Changes

### 1. Storage Structure Enhancement

**Old Version:**
```solidity
struct YieldSkimmingStorage {
    uint256 lastRateRay; // Only tracked last exchange rate
}
```

**New Version:**
```solidity
struct YieldSkimmingStorage {
    uint256 lastRateRay;     // Rate from last report
    uint256 recoveryRateRay; // Rate at which users would break even
}
```

The addition of `recoveryRateRay` allows the strategy to track when it has fully recovered from losses.

### 2. Loss Tracking in Base Strategy

The base TokenizedStrategy now includes:
```solidity
struct StrategyData {
    // ... existing fields ...
    uint256 lossAmount; // Accumulated losses to offset against future profits
    bool allowDepositDuringLoss; // Whether to allow deposits when there is an ongoing loss
}
```

### 3. Report Function Overhaul


**New Version:**

Key improvements in the new `report()`:
```solidity
// Tracks losses for future recovery
if (currentValue < previousValue) {
    loss = (underlyingLoss * WadRayMath.RAY) / rateNow;
    uint256 burnable = _handleDragonLossProtection(S, loss, rateNow.rayToWad());
    S.lossAmount = adjustedOldLoss + (loss - burnable);
}

// During recovery, only mints shares for excess profit
if (S.lossAmount > 0) {
    if (underlyingGain > lossInUnderlying) {
        // Full recovery + excess
        S.lossAmount = 0;
        _handleDonationMinting(S, rateNow);
        YS.recoveryRateRay = rateNow;
    } else {
        // Partial recovery - no minting
        S.lossAmount = ((lossInUnderlying - underlyingGain) * WadRayMath.RAY) / rateNow;
        profit = 0;
    }
}
```

### 4. Share Conversion with Loss Socialization

**Old Version:**
```solidity
function _convertToShares(
    StrategyData storage,
    uint256 assets,
    Math.Rounding rounding
) internal view virtual override returns (uint256) {
    return assets.mulDiv(_currentRateRay(), WadRayMath.RAY, rounding);
}
```

**New Version:**
```solidity
function _convertToShares(
    StrategyData storage S,
    uint256 assets,
    Math.Rounding rounding
) internal view virtual override returns (uint256) {
    return _convertToSharesWithLoss(S, assets, rounding);
}

// In TokenizedStrategy base:
function _convertToSharesWithLoss(
    StrategyData storage S,
    uint256 assets,
    Math.Rounding _rounding
) internal view returns (uint256) {
    uint256 totalSupply_ = _totalSupply(S);
    if (totalSupply_ == 0) return assets;
    
    uint256 totalAssets_ = _totalAssets(S);
    if (totalAssets_ == 0) return 0;
    
    // Key change: denominator includes lossAmount
    return assets.mulDiv(totalSupply_, totalAssets_ + S.lossAmount, _rounding);
}
```

This ensures new depositors receive fewer shares when there are unrealized losses, making them share proportionally in the loss.

### 5. Safe Deposit Functions

New functions added to TokenizedStrategy:
- `safeDeposit()`: Allows deposits with slippage protection
- `safeMint()`: Allows minting with slippage protection

Standard `deposit()` and `mint()` functions now revert when `lossAmount > 0`:
```solidity
function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
    StrategyData storage S = _strategyStorage();
    require(S.lossAmount == 0, "use safeDeposit");
    // ...
}
```

### 6. Recovery Rate Mechanism

The new `_calculateTunedM` function considers the recovery rate:
```solidity
function _calculateTunedM(
    uint256 totalSupplyAmount,
    uint256 totalAssetsAmount,
    uint256 currentRate
) internal view returns (uint256) {
    YieldSkimmingStorage storage S = _strategyYieldSkimmingStorage();
    uint256 recoveryRate = S.recoveryRateRay;
    
    // Only mint if current rate exceeds recovery rate
    if (currentRate > recoveryRate && recoveryRate > 0) {
        uint256 rateDifference = currentRate - recoveryRate;
        return totalSupplyAmount.mulDiv(rateDifference, recoveryRate);
    }
    // ...
}
```

## Impact on Users

### For Existing Depositors
- Protected from dilution during loss events
- Fair share of recovery profits
- No change to withdrawal mechanics

### For New Depositors During Loss
- Must use `safeDeposit()` or `safeMint()` with slippage protection
- Receive fewer shares (reflecting the current loss)
- Share proportionally in both the loss and subsequent recovery
- Cannot exploit the system for risk-free profits

### For Dragon Router (Donation Recipient)
- Shares may be burned during loss events (if burning enabled)
- No new shares minted until full recovery
- Receives shares only from profits exceeding the recovery threshold

## Configuration Options

Strategies can be configured with:
- `enableBurning`: Whether to burn dragonRouter shares during losses
- `allowDepositDuringLoss`: Whether to allow any deposits during loss periods

## Summary

The changes ensure that:
1. **Invariant Maintained**: No depositor can withdraw more underlying value than deposited
2. **Fair Loss Distribution**: New depositors share proportionally in existing losses
3. **Recovery Benefits**: All shareholders benefit equally from recovery
4. **Donation Integrity**: Dragon router only receives true excess profits

These modifications create a robust and fair system that properly handles loss scenarios while maintaining the yield skimming mechanism for genuine profits.