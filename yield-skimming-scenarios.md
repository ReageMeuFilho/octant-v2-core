# Yield Skimming Strategy - Scenario Analysis with Dragon Shares

## Overview

This document tracks various scenarios for the YieldSkimmingTokenizedStrategy to understand how the conversion mechanism works under different rate conditions, including the dragon share minting/burning mechanism.

## 🎉 KEY IMPROVEMENTS IMPLEMENTED

### **Fixed Unfair FIFO Problem**
- **BEFORE**: Early withdrawers could escape losses while late withdrawers bore disproportionate losses
- **AFTER**: ALL users share losses proportionally based on vault solvency, regardless of withdrawal order

### **Enhanced Dragon Protection**
- **NEW**: Dragon cannot withdraw/transfer shares during insolvency
- **BENEFIT**: Ensures dragon buffer remains available to protect users when needed most

### **Fair Solvency Logic**
- **LOGIC**: Check if `currentVaultValue < totalShares` (insolvency)
- **RESULT**: When insolvent, ALL withdrawals use proportional distribution: `shares × totalAssets ÷ totalShares`

### **🎯 CLEANER: Solvency-Aware Conversion Functions**
- **`_convertToShares()`**: Returns shares needed accounting for insolvency
- **`_convertToAssets()`**: Returns assets user would actually receive
- **SYSTEM-WIDE**: All ERC4626 functions automatically use realistic values

### **Enhanced Standard Functions (Auto-Improved)**
- **`convertToShares/Assets()`**: Now return realistic values during insolvency
- **`previewDeposit/Mint/Withdraw/Redeem()`**: All previews now accurate
- **`withdraw()` & `redeem()`**: Simplified - just use standard conversion logic

### **New Query Functions for Transparency**
- **`isVaultSolvent()`**: Check if vault can cover all obligations
- **`getSolvencyRatio()`**: Get vault health ratio (1e27 = 100% solvent)

## Key Formulas

### 🎯 CLEANER: Solvency-Aware Operations (Automatic!)
- **Deposit**: `shares = assets × currentRate ÷ 1e27` (always)
- **Convert To Assets**: 
  - **If Solvent**: `assets = shares × 1e27 ÷ currentRate`
  - **If Insolvent**: `assets = shares × totalAssets ÷ totalShares` (FAIR!)
- **Convert To Shares**:
  - **If Solvent**: `shares = assets × currentRate ÷ 1e27`  
  - **If Insolvent**: `shares = assets × totalShares ÷ totalAssets`

### 🎉 IMPROVED: Solvency Calculations
- **Current Value**: `currentValue = totalAssets × currentRate`
- **Total Owed**: `totalShares` (since 1 share = 1 ETH value)
- **✅ Solvency Check**: `currentValue ≥ totalShares` → Normal conversions
- **❌ Insolvency**: `currentValue < totalShares` → ALL conversions use proportional logic

### Dragon Share Reporting
- **Profit Case**: If `currentValue > totalOwedValue`:
  - `profitValue = currentValue - totalOwedValue`
  - Mint `profitValue` dragon shares (1 share = 1 ETH value)
  - `dragonValueDebt += profitValue`
- **Loss Case**: If `currentValue < totalOwedValue` and `dragonValueDebt > 0`:
  - `lossValue = totalOwedValue - currentValue`
  - `dragonBurn = min(lossValue, dragonValueDebt)`
  - Burn `dragonBurn` dragon shares
  - `dragonValueDebt -= dragonBurn`
  - If `lossValue > dragonBurn`: `totalValueDebt -= (lossValue - dragonBurn)`

## Scenario 1: Basic Profit Capture with Dragon Shares

User deposits, rate increases, report captures profit as dragon shares, another user deposits, both withdraw.

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0 | - | Initial | - | - | - | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | Empty vault |
| 1 | 1.3 | d1 | 10 wstETH | 10×1.3=**13** | - | 10 | 13 | 13 ETH | 0 | 0 ETH | 13 ETH | User1 deposits |
| 2 | 1.4 | Rate↑ | - | - | - | 10 | 13 | 13 ETH | 0 | 0 ETH | 14 ETH | +1 ETH unrealized |
| 3 | 1.4 | Report | - | Profit: 1 | - | 10 | 14 | 13 ETH | 1 | 1 ETH | 14 ETH | Dragon minted 1 share |
| 4 | 1.4 | d2 | 10 wstETH | 10×1.4=**14** | - | 20 | 28 | 27 ETH | 1 | 1 ETH | 28 ETH | User2 deposits |
| 5 | 1.4 | w1 | 13 shares | - | 13÷1.4=**9.29** | 10.71 | 15 | 14 ETH | 1 | 1 ETH | 15 ETH | User1 withdraws |
| 6 | 1.4 | w2 | 14 shares | - | 14÷1.4=**10** | 0.71 | 1 | 0 ETH | 1 | 1 ETH | 1 ETH | User2 withdraws |

**Result**: Both users receive full value. Dragon holds 1 share (0.71 wstETH) representing captured yield.

## Scenario 2: Dragon Loss Protection - RECALCULATED

Rate increases with reporting, then drops, dragon shares protect users from loss.

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0 | - | Initial | - | - | - | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | Empty vault |
| 1 | 1.3 | d1 | 10 wstETH | 10×1.3=**13** | - | 10 | 13 | 13 ETH | 0 | 0 ETH | 13 ETH | User1 deposits |
| 2 | 1.5 | Rate↑ | - | - | - | 10 | 13 | 13 ETH | 0 | 0 ETH | 15 ETH | +2 ETH unrealized |
| 3 | 1.5 | Report | - | Profit: 2 | - | 10 | 15 | 13 ETH | 2 | 2 ETH | 15 ETH | Dragon minted 2 shares |
| 4 | 1.5 | d2 | 10 wstETH | 10×1.5=**15** | - | 20 | 30 | 28 ETH | 2 | 2 ETH | 30 ETH | User2 deposits |
| 5 | 1.2 | Rate↓ | - | - | - | 20 | 30 | 28 ETH | 2 | 2 ETH | 24 ETH | -6 ETH loss |
| 6 | 1.2 | Report | - | Loss: 6, Burn: 2 | - | 20 | 28 | 24 ETH | 0 | 0 ETH | 24 ETH | Dragon absorbed 2 ETH loss |
| 7 | 1.2 | w1 | 13 shares | - | 13÷1.2=**10.83** | 9.17 | 15 | 10.17 ETH | 0 | 0 ETH | 11 ETH | User1 full withdrawal |
| 8 | 1.2 | w2 | 15 shares | - | 15÷1.2=**12.5** | -3.33 | 0 | -2.5 ETH | 0 | 0 ETH | 0 ETH | ERROR: Insufficient assets! |

**CORRECTION**: After step 6, vault is SOLVENT (24 ETH value = 24 ETH owed), but insufficient assets for both full withdrawals.

**Fixed Calculation**:
- After step 6: 20 wstETH, 28 total shares (all user shares after dragon burn)
- Vault value = 20 × 1.2 = 24 ETH
- Total owed = 28 shares = 28 ETH
- **24 < 28 → INSOLVENT** → Proportional distribution for ALL

| 7 | 1.2 | w1 | 13 shares | - | 13×20÷28=**9.29** | 10.71 | 15 | - | 0 | 0 ETH | - | User1 proportional |
| 8 | 1.2 | w2 | 15 shares | - | 15×10.71÷15=**10.71** | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | User2 gets remainder |

**Results**:
- **User1**: Deposited 13 ETH, received 11.15 ETH → **Loss: 1.85 ETH**
- **User2**: Deposited 15 ETH, received 12.85 ETH → **Loss: 2.15 ETH**

## Scenario 3: Dragon Withdrawal After Profit

Dragon accumulates profit shares then withdraws, affecting subsequent user withdrawals.

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0 | - | Initial | - | - | - | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | Empty vault |
| 1 | 1.2 | d1 | 10 wstETH | 10×1.2=**12** | - | 10 | 12 | 12 ETH | 0 | 0 ETH | 12 ETH | User1 deposits |
| 2 | 1.4 | Rate↑ | - | - | - | 10 | 12 | 12 ETH | 0 | 0 ETH | 14 ETH | +2 ETH unrealized |
| 3 | 1.4 | Report | - | Profit: 2 | - | 10 | 14 | 12 ETH | 2 | 2 ETH | 14 ETH | Dragon minted 2 shares |
| 4 | 1.5 | Rate↑ | - | - | - | 10 | 14 | 12 ETH | 2 | 2 ETH | 15 ETH | +1 ETH unrealized |
| 5 | 1.5 | Report | - | Profit: 1 | - | 10 | 15 | 12 ETH | 3 | 3 ETH | 15 ETH | Dragon +1 share (total 3) |
| 6 | 1.5 | d-wd | 3 shares | - | 3÷1.5=**2** | 8 | 12 | 12 ETH | 0 | 0 ETH | 12 ETH | Dragon withdraws all |
| 7 | 1.2 | Rate↓ | - | - | - | 8 | 12 | 12 ETH | 0 | 0 ETH | 9.6 ETH | -2.4 ETH shortfall |
| 8 | 1.2 | w1 | 12 shares | - | 12×8÷12=**8** | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | User1 gets all remaining |

**Result**: Dragon withdrew profit early. User1 bears loss when rate drops after dragon exit.

## Proposed Scenarios for Analysis

### A. Multiple Reporting Cycles - DETAILED ANALYSIS
**Description**: Track how dragon buffer builds up over multiple profit cycles before a major loss event.

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0 | - | Initial | - | - | - | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | Empty vault |
| 1 | 1.2 | d1 | 10 wstETH | 10×1.2=**12** | - | 10 | 12 | 12 ETH | 0 | 0 ETH | 12 ETH | User1 deposits |
| 2 | 1.3 | Rate↑ | - | - | - | 10 | 12 | 12 ETH | 0 | 0 ETH | 13 ETH | +1 ETH profit |
| 3 | 1.3 | Report | - | Profit: 1 | - | 10 | 13 | 12 ETH | 1 | 1 ETH | 13 ETH | Dragon +1 share |
| 4 | 1.4 | Rate↑ | - | - | - | 10 | 13 | 12 ETH | 1 | 1 ETH | 14 ETH | +1 ETH profit |
| 5 | 1.4 | Report | - | Profit: 1 | - | 10 | 14 | 12 ETH | 2 | 2 ETH | 14 ETH | Dragon +1 share |
| 6 | 1.5 | Rate↑ | - | - | - | 10 | 14 | 12 ETH | 2 | 2 ETH | 15 ETH | +1 ETH profit |
| 7 | 1.5 | Report | - | Profit: 1 | - | 10 | 15 | 12 ETH | 3 | 3 ETH | 15 ETH | Dragon +1 share |
| 8 | 1.3 | Rate↓ | - | - | - | 10 | 15 | 12 ETH | 3 | 3 ETH | 13 ETH | -2 ETH loss |
| 9 | 1.3 | Report | - | Loss: 2, Burn: 2 | - | 10 | 13 | 12 ETH | 1 | 1 ETH | 13 ETH | Dragon absorbed loss |
| 10 | 1.3 | w1 | 12 shares | - | 12÷1.3=**9.23** | 0.77 | 1 | 0 ETH | 1 | 1 ETH | 1 ETH | User1 full value! |

**Result**: Dragon buffer fully protected User1 from the 2 ETH loss. User1 received full 12 ETH value despite rate volatility.

### B. Cascading User Exits During Loss - FIXED WITH FAIR PROPORTIONAL LOGIC
**Description**: Multiple users trying to exit as rates decline - NOW WITH FAIR LOSS SHARING!

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0 | - | Initial | - | - | - | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | Empty vault |
| 1 | 1.2 | d1 | 10 wstETH | 10×1.2=**12** | - | 10 | 12 | 12 ETH | 0 | 0 ETH | 12 ETH | User1 deposits |
| 2 | 1.3 | Rate↑ | - | - | - | 10 | 12 | 12 ETH | 0 | 0 ETH | 13 ETH | +1 ETH profit |
| 3 | 1.3 | Report | - | Profit: 1 | - | 10 | 13 | 12 ETH | 1 | 1 ETH | 13 ETH | Dragon +1 share |
| 4 | 1.3 | d2 | 10 wstETH | 10×1.3=**13** | - | 20 | 26 | 25 ETH | 1 | 1 ETH | 26 ETH | User2 deposits |
| 5 | 1.4 | Rate↑ | - | - | - | 20 | 26 | 25 ETH | 1 | 1 ETH | 28 ETH | +2 ETH profit |
| 6 | 1.4 | Report | - | Profit: 2 | - | 20 | 28 | 25 ETH | 3 | 3 ETH | 28 ETH | Dragon +2 shares |
| 7 | 1.4 | d3 | 10 wstETH | 10×1.4=**14** | - | 30 | 42 | 39 ETH | 3 | 3 ETH | 42 ETH | User3 deposits |
| 8 | 1.0 | Rate↓ | - | - | - | 30 | 42 | 39 ETH | 3 | 3 ETH | 30 ETH | -12 ETH loss! |
| 9 | 1.0 | Report | - | Loss: 12, Burn: 3 | - | 30 | 39 | 30 ETH | 0 | 0 ETH | 30 ETH | Dragon depleted, 9 ETH user loss |

**SOLVENCY CHECK**: Vault value = 30 ETH, Total owed = 39 ETH → **INSOLVENT** → All users get proportional distribution

| 10 | 1.0 | w1 | 12 shares | - | 12×30÷39=**9.23** | 20.77 | 27 | 20.77 ETH | 0 | 0 ETH | 20.77 ETH | User1 proportional |
| 11 | 1.0 | w2 | 13 shares | - | 13×20.77÷27=**10** | 10.77 | 14 | 10.77 ETH | 0 | 0 ETH | 10.77 ETH | User2 proportional |
| 12 | 1.0 | w3 | 14 shares | - | All remaining=**10.77** | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | User3 gets remainder |

**FAIR RESULTS**:
- **User1**: Deposited 12 ETH, received 9.23 ETH → **Loss: 2.77 ETH (23.1%)**
- **User2**: Deposited 13 ETH, received 10 ETH → **Loss: 3 ETH (23.1%)**
- **User3**: Deposited 14 ETH, received 10.77 ETH → **Loss: 3.23 ETH (23.1%)**

**🎉 KEY IMPROVEMENT**: ALL users now share the same 23.1% loss rate - NO MORE FIFO ADVANTAGE!

### C. Dragon Buffer Exhaustion - RECALCULATED WITH FAIR DISTRIBUTION
**Description**: Extreme loss scenario where dragon buffer is completely depleted.

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0 | - | Initial | - | - | - | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | Empty vault |
| 1 | 1.0 | d1 | 20 wstETH | 20×1.0=**20** | - | 20 | 20 | 20 ETH | 0 | 0 ETH | 20 ETH | User1 large deposit |
| 2 | 1.2 | Rate↑ | - | - | - | 20 | 20 | 20 ETH | 0 | 0 ETH | 24 ETH | +4 ETH profit |
| 3 | 1.2 | Report | - | Profit: 4 | - | 20 | 24 | 20 ETH | 4 | 4 ETH | 24 ETH | Dragon +4 shares |
| 4 | 1.3 | Rate↑ | - | - | - | 20 | 24 | 20 ETH | 4 | 4 ETH | 26 ETH | +2 ETH profit |
| 5 | 1.3 | Report | - | Profit: 2 | - | 20 | 26 | 20 ETH | 6 | 6 ETH | 26 ETH | Dragon +2 shares |
| 6 | 1.3 | d2 | 10 wstETH | 10×1.3=**13** | - | 30 | 39 | 33 ETH | 6 | 6 ETH | 39 ETH | User2 deposits |
| 7 | 1.3 | d3 | 10 wstETH | 10×1.3=**13** | - | 40 | 52 | 46 ETH | 6 | 6 ETH | 52 ETH | User3 deposits |
| 8 | 0.7 | CRASH | - | - | - | 40 | 52 | 46 ETH | 6 | 6 ETH | 28 ETH | -24 ETH loss! |
| 9 | 0.7 | Report | - | Loss: 24, Burn: 6 | - | 40 | 46 | 28 ETH | 0 | 0 ETH | 28 ETH | Dragon depleted! |

**SOLVENCY CHECK**: Vault value = 28 ETH, Total owed = 46 ETH → **INSOLVENT** → All users get proportional

| 10 | 0.7 | w1 | 20 shares | - | 20×40÷46=**17.39** | 22.61 | 26 | - | 0 | 0 ETH | - | User1 proportional |
| 11 | 0.7 | w2 | 13 shares | - | 13×22.61÷26=**11.31** | 11.30 | 13 | - | 0 | 0 ETH | - | User2 proportional |
| 12 | 0.7 | w3 | 13 shares | - | All remaining=**11.30** | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | User3 gets remainder |

**RESULTS**:
- **Dragon Buffer**: Built up 6 ETH, completely exhausted absorbing loss
- **User1**: Deposited 20 ETH, received 12.17 ETH → **Loss: 7.83 ETH (39.1%)**
- **User2**: Deposited 13 ETH, received 7.92 ETH → **Loss: 5.08 ETH (39.1%)**
- **User3**: Deposited 13 ETH, received 7.92 ETH → **Loss: 5.08 ETH (39.1%)**

**Key Insight**: Even with proportional logic, all users share the same 39.1% loss rate fairly.

### D. Partial Dragon Withdrawal Strategy - DETAILED ANALYSIS
**Description**: Dragon withdraws some profit while maintaining buffer.

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0 | - | Initial | - | - | - | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | Empty vault |
| 1 | 1.0 | d1 | 15 wstETH | 15×1.0=**15** | - | 15 | 15 | 15 ETH | 0 | 0 ETH | 15 ETH | User1 deposits |
| 2 | 1.3 | Rate↑ | - | - | - | 15 | 15 | 15 ETH | 0 | 0 ETH | 19.5 ETH | +4.5 ETH profit |
| 3 | 1.3 | Report | - | Profit: 4.5 | - | 15 | 19.5 | 15 ETH | 4.5 | 4.5 ETH | 19.5 ETH | Dragon +4.5 shares |
| 4 | 1.4 | Rate↑ | - | - | - | 15 | 19.5 | 15 ETH | 4.5 | 4.5 ETH | 21 ETH | +1.5 ETH profit |
| 5 | 1.4 | Report | - | Profit: 1.5 | - | 15 | 21 | 15 ETH | 6 | 6 ETH | 21 ETH | Dragon +1.5 shares |
| 6 | 1.4 | d-wd | 3 shares | - | 3÷1.4=**2.14** | 12.86 | 18 | 15 ETH | 3 | 3 ETH | 18 ETH | Dragon partial withdrawal |
| 7 | 1.4 | d2 | 10 wstETH | 10×1.4=**14** | - | 22.86 | 32 | 29 ETH | 3 | 3 ETH | 32 ETH | User2 deposits |
| 8 | 1.1 | Rate↓ | - | - | - | 22.86 | 32 | 29 ETH | 3 | 3 ETH | 25.15 ETH | -6.85 ETH loss |
| 9 | 1.1 | Report | - | Loss: 6.85, Burn: 3 | - | 22.86 | 29 | 25.15 ETH | 0 | 0 ETH | 25.15 ETH | Dragon buffer used |
| 10 | 1.1 | w1 | 15 shares | - | 15×22.86÷29=**11.83** | 11.03 | 14 | 12.13 ETH | 0 | 0 ETH | 12.13 ETH | User1 proportional |
| 11 | 1.1 | w2 | 14 shares | - | All remaining=**11.03** | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | User2 gets remainder |

**Results**:
- **Dragon**: Withdrew 2.14 wstETH profit early, lost 3 ETH buffer value protecting users
- **User1**: Deposited 15 ETH, received 13.01 ETH → **Loss: 1.99 ETH** 
- **User2**: Deposited 14 ETH, received 12.13 ETH → **Loss: 1.87 ETH**

**Comparison - If Dragon Withdrew All 6 Shares**:
- Dragon would get 4.29 wstETH immediately
- No buffer → Users face full 6.85 ETH loss
- User losses would be ~3.5 ETH each (much worse!)

**Key Insight**: Partial dragon withdrawals balance profit-taking with user protection.

### E. Volatile Rate Environment - DETAILED ANALYSIS
**Description**: Rapid rate changes with frequent reporting.

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0 | - | Initial | - | - | - | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | Empty vault |
| 1 | 1.2 | d1 | 12 wstETH | 12×1.2=**14.4** | - | 12 | 14.4 | 14.4 ETH | 0 | 0 ETH | 14.4 ETH | User1 deposits |
| 2 | 1.4 | Rate↑ | - | - | - | 12 | 14.4 | 14.4 ETH | 0 | 0 ETH | 16.8 ETH | +2.4 ETH profit |
| 3 | 1.4 | Report | - | Profit: 2.4 | - | 12 | 16.8 | 14.4 ETH | 2.4 | 2.4 ETH | 16.8 ETH | Dragon +2.4 shares |
| 4 | 1.1 | Rate↓ | - | - | - | 12 | 16.8 | 14.4 ETH | 2.4 | 2.4 ETH | 13.2 ETH | -3.6 ETH loss |
| 5 | 1.1 | Report | - | Loss: 3.6, Burn: 2.4 | - | 12 | 14.4 | 13.2 ETH | 0 | 0 ETH | 13.2 ETH | Dragon buffer used |
| 6 | 1.5 | Rate↑ | - | - | - | 12 | 14.4 | 13.2 ETH | 0 | 0 ETH | 18 ETH | +4.8 ETH profit |
| 7 | 1.5 | Report | - | Profit: 4.8 | - | 12 | 19.2 | 13.2 ETH | 4.8 | 4.8 ETH | 18 ETH | Dragon rebuilds |
| 8 | 1.5 | d2 | 8 wstETH | 8×1.5=**12** | - | 20 | 31.2 | 25.2 ETH | 4.8 | 4.8 ETH | 30 ETH | User2 deposits |
| 9 | 1.3 | Rate↓ | - | - | - | 20 | 31.2 | 25.2 ETH | 4.8 | 4.8 ETH | 26 ETH | -4 ETH loss |
| 10 | 1.3 | Report | - | Loss: 4, Burn: 4 | - | 20 | 27.2 | 25.2 ETH | 0.8 | 0.8 ETH | 26 ETH | Dragon mostly depleted |

**Results**: Volatility constantly changes dragon buffer. Frequent reporting helps capture profits and manage losses effectively.

**Key Insight**: High-frequency reporting in volatile environments maintains better user protection.

### F. Mixed User and Dragon Activity - DETAILED ANALYSIS
**Description**: Complex scenario with users and dragon both depositing/withdrawing.

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0 | - | Initial | - | - | - | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | Empty vault |
| 1 | 1.1 | d1 | 10 wstETH | 10×1.1=**11** | - | 10 | 11 | 11 ETH | 0 | 0 ETH | 11 ETH | User1 deposits |
| 2 | 1.3 | Rate↑ | - | - | - | 10 | 11 | 11 ETH | 0 | 0 ETH | 13 ETH | +2 ETH profit |
| 3 | 1.3 | Report | - | Profit: 2 | - | 10 | 13 | 11 ETH | 2 | 2 ETH | 13 ETH | Dragon +2 shares |
| 4 | 1.3 | d2 | 15 wstETH | 15×1.3=**19.5** | - | 25 | 32.5 | 30.5 ETH | 2 | 2 ETH | 32.5 ETH | User2 deposits |
| 5 | 1.4 | Rate↑ | - | - | - | 25 | 32.5 | 30.5 ETH | 2 | 2 ETH | 35 ETH | +2.5 ETH profit |
| 6 | 1.4 | Report | - | Profit: 2.5 | - | 25 | 35 | 30.5 ETH | 4.5 | 4.5 ETH | 35 ETH | Dragon +2.5 shares |
| 7 | 1.4 | d-wd | 2 shares | - | 2÷1.4=**1.43** | 23.57 | 33 | 30.5 ETH | 2.5 | 2.5 ETH | 33 ETH | Dragon partial withdrawal |
| 8 | 1.2 | Rate↓ | - | - | - | 23.57 | 33 | 30.5 ETH | 2.5 | 2.5 ETH | 28.28 ETH | -4.72 ETH loss |
| 9 | 1.2 | d3 | 8 wstETH | 8×1.2=**9.6** | - | 31.57 | 42.6 | 40.1 ETH | 2.5 | 2.5 ETH | 37.88 ETH | User3 deposits |
| 10 | 1.1 | Rate↓ | - | - | - | 31.57 | 42.6 | 40.1 ETH | 2.5 | 2.5 ETH | 34.73 ETH | -7.87 ETH loss |
| 11 | 1.1 | Report | - | Loss: 7.87, Burn: 2.5 | - | 31.57 | 40.1 | 34.73 ETH | 0 | 0 ETH | 34.73 ETH | Dragon depleted |
| 12 | 1.1 | w2 | 19.5 shares | - | 19.5×31.57÷40.1=**15.35** | 16.22 | 20.6 | 17.89 ETH | 0 | 0 ETH | 17.84 ETH | User2 exits first |
| 13 | 1.1 | w1 | 11 shares | - | 11×16.22÷20.6=**8.66** | 7.56 | 9.6 | 8.32 ETH | 0 | 0 ETH | 8.32 ETH | User1 exits |
| 14 | 1.1 | w3 | 9.6 shares | - | All remaining=**7.56** | 0 | 0 | 0 ETH | 0 | 0 ETH | 0 ETH | User3 gets remainder |

**Results**:
- **Dragon**: Withdrew 1.43 wstETH profit, lost 2.5 ETH buffer protecting users
- **User1**: Deposited 11 ETH, received 9.53 ETH → **Loss: 1.47 ETH**
- **User2**: Deposited 19.5 ETH, received 16.89 ETH → **Loss: 2.61 ETH** 
- **User3**: Deposited 9.6 ETH, received 8.32 ETH → **Loss: 1.28 ETH**

**Key Insight**: Complex interactions show how dragon buffer protects users across multiple rate cycles and withdrawal timing patterns.

## Custom Scenario Template with Dragon Tracking

| Step | Rate | Action | Amount | Shares Calc | Assets Calc | Total Assets | Total Shares | User Debt | Dragon Shares | Dragon Debt | Current Value | Notes |
|------|------|--------|--------|-------------|-------------|--------------|--------------|-----------|---------------|-------------|---------------|-------|
| 0    | -    | Initial| -      | -           | -           | 0            | 0            | 0 ETH     | 0             | 0 ETH       | 0 ETH         | Empty |
| 1    | ___  | ___    | ___    | ___×___=___ | -           | ___          | ___          | ___ ETH   | ___           | ___ ETH     | ___ ETH       | ___   |
| 2    | ___  | ___    | ___    | ___         | ___         | ___          | ___          | ___ ETH   | ___           | ___ ETH     | ___ ETH       | ___   |

## Comprehensive Scenario Summary - UPDATED WITH FAIR PROPORTIONAL LOGIC

| Scenario | Dragon Buffer Peak | Dragon Strategy | Rate Pattern | User1 Outcome | User2 Outcome | User3 Outcome | Key Learning |
|----------|-------------------|-----------------|--------------|---------------|---------------|---------------|---------------|
| **A. Multiple Cycles** | 3 ETH | Hold buffer | 1.2→1.5→1.3 | 12→12 ETH ✅ | - | - | Buffer fully protects users |
| **B. Fair Exits** | 3 ETH | No withdrawal | 1.2→1.4→1.0 | 12→9.23 ETH (23.1% loss) | 13→10 ETH (23.1% loss) | 14→10.77 ETH (23.1% loss) | 🎉 FAIR: All users share same loss % |
| **C. Buffer Exhaustion** | 6 ETH | No withdrawal | 1.0→1.3→0.7 | 20→12.17 ETH (39.1% loss) | 13→7.92 ETH (39.1% loss) | 13→7.92 ETH (39.1% loss) | 🎉 FAIR: Equal loss distribution |
| **D. Partial Withdrawal** | 6 ETH | Withdraw 50% | 1.0→1.4→1.1 | 15→13.01 ETH ❌ | 14→12.13 ETH ❌ | - | Partial strategy balances risk |
| **E. Volatile Rates** | 4.8 ETH | No withdrawal | 1.2→1.4→1.1→1.5→1.3 | - | - | - | Frequent reporting rebuilds buffer |
| **F. Mixed Activity** | 4.5 ETH | Withdraw early | 1.1→1.4→1.1 | 11→9.53 ETH ❌ | 19.5→16.89 ETH ❌ | 9.6→8.32 ETH ❌ | Complex timing effects |

## Advanced Key Insights with Dragon Shares

### 1. **Dragon Buffer Mechanics**
- **Minting**: Dragon shares are minted 1:1 with profit value in ETH terms
- **Burning**: Dragon shares burn before users face losses (first-loss protection)
- **Withdrawal**: Dragon can withdraw at any time, converting shares to assets at current rate

### 2. **User Protection Levels**
- **Full Protection**: When dragon buffer ≥ total loss (Scenario A)
- **Partial Protection**: When dragon buffer < total loss, users share remaining proportionally (Scenarios C, D, F)
- **No Protection**: When no dragon buffer exists (rare, only if dragon fully exits before losses)

### 3. **🎉 IMPROVED: Timing and Fairness**
- **Deposit Timing**: Users lock in ETH value at deposit rate
- **✅ Withdrawal Timing**: NOW FAIR - all users share losses proportionally regardless of withdrawal order
- **Reporting Timing**: More frequent reporting = better profit capture and loss protection
- **🚫 Dragon Protection**: Dragon cannot withdraw/transfer during insolvency, ensuring buffer protection

### 4. **Dragon Strategy Implications**
- **Hold All**: Maximum user protection but dragon bears all losses
- **Withdraw All**: Maximum dragon profit but zero user protection
- **Partial Withdrawal**: Balanced approach - take some profits, maintain protection (Scenario D)

### 5. **Rate Volatility Effects**
- **Upward Volatility**: Creates dragon buffer through profit capture
- **Downward Volatility**: Depletes dragon buffer through loss absorption
- **High Frequency**: Requires frequent reporting to maintain proper buffer levels

### 6. **🎉 IMPROVED: System Stability**
- **Progressive Loss Sharing**: Dragon buffer → **fair proportional user sharing for ALL**
- **Value Debt Tracking**: Maintains 1 share = 1 ETH value debt relationship
- **✅ Solvency-Based Distribution**: Proportional distribution when `vaultValue < totalShares` (FAIR!)
- **🔒 Dragon Lock**: Dragon cannot exit during insolvency, maintaining protection
- **⚖️ Equal Treatment**: All users share losses at same percentage regardless of withdrawal order

## Report Calculation Reference

### Profit Report
```
if (currentValue > totalOwedValue):
    profitValue = currentValue - totalOwedValue
    mint profitValue dragon shares
    dragonValueDebt += profitValue
```

### Loss Report
```
if (currentValue < totalOwedValue && dragonValueDebt > 0):
    lossValue = totalOwedValue - currentValue
    dragonBurn = min(lossValue, dragonValueDebt)
    burn dragonBurn dragon shares
    dragonValueDebt -= dragonBurn
    if (lossValue > dragonBurn):
        totalValueDebt -= (lossValue - dragonBurn)
```

## 🎉 SUMMARY OF IMPROVEMENTS

### **Before: Unfair System**
- ❌ Early withdrawers could escape losses (FIFO advantage)
- ❌ Dragon could withdraw during insolvency, abandoning users
- ❌ `withdraw()` function failed during shortfalls
- ❌ No transparency into vault solvency status

### **After: Fair & Robust System**  
- ✅ **Fair Loss Sharing**: All users share identical loss percentages
- ✅ **Dragon Protection**: Dragon locked during insolvency, ensuring buffer availability
- ✅ **Smart Withdrawals**: `withdraw()` automatically handles insolvency scenarios
- ✅ **Full Transparency**: Query functions provide real-time vault health
- ✅ **Proportional Logic**: Solvency-based distribution ensures fairness

### **🎯 CLEANER: Technical Implementation**
- **Core Logic**: Solvency-aware `_convertToShares()` and `_convertToAssets()` functions
- **Automatic Fairness**: ALL ERC4626 functions inherit proportional distribution during insolvency
- **Simplified Code**: `redeem()` and `withdraw()` use standard conversion logic
- **Dragon Lock**: `revert("Dragon cannot withdraw during insolvency")`
- **System-wide**: `convertToShares()`, `previewRedeem()`, etc. all automatically accurate

This creates a **trustworthy, predictable system** where users can confidently participate knowing they'll be treated fairly regardless of timing, while maintaining strong protection through the dragon buffer mechanism.

## ⭐ **Why the Conversion Function Approach is Superior**

### **Architectural Elegance:**
- **Single Source of Truth**: All conversions use the same solvency-aware logic
- **ERC4626 Compliance**: Standard functions return realistic, not theoretical values
- **Zero Duplication**: No repeated solvency checks across multiple functions
- **Future-Proof**: Any new functions automatically inherit correct behavior

### **User Experience:**
- **Honest Previews**: `previewRedeem()` shows what users actually get during insolvency
- **Consistent API**: All ERC4626 functions work as expected in all scenarios
- **No Surprises**: Conversion functions reflect reality, not ideal conditions

### **Developer Benefits:**
- **Simplified Implementation**: `redeem()` and `withdraw()` become standard implementations
- **Automatic Correctness**: New features automatically use fair distribution
- **Easier Testing**: Consistent behavior across all conversion functions
- **Clean Architecture**: Core logic centralized in conversion functions

This approach transforms the yield skimming strategy into a **robust, fair, and architecturally sound system** that handles complex solvency scenarios transparently while maintaining full ERC4626 compatibility.