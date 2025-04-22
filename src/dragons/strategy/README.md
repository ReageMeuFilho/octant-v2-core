# Octant V2 TokenizedStrategy

## Overview

This repository contains a specialized fork of Yearn V3's TokenizedStrategy contracts with significant modifications for Octant V2's yield distribution mechanism. These contracts provide a framework for creating ERC-4626 compliant tokenized investment strategies with yield distribution capabilities through a "Dragon Router" pattern.

## Key Differences from Yearn V3

1. **Dragon Router Mechanism**
   - Added `dragonRouter` parameter and storage variable to direct yield to a specified address
   - Different implementation strategies for yield distribution (Donating vs Skimming)

2. **Removed Features**
   - Eliminated performance fees and fee distribution mechanism
   - Removed profit unlocking mechanism (profits are immediately realized)
   - Removed factory references

3. **Security Enhancements**
   - Added validation checks for all critical addresses
   - Standardized error messages

4. **Architecture Changes**
   - Made base contracts abstract to support specialized implementations
   - Made the `report()` function virtual to enable customized yield handling

## Architecture Overview

The system consists of the following core components:

1. **Interfaces**
   - `ITokenizedStrategy`: Main interface for interacting with the strategy
   - `IBaseStrategy`: Interface for strategy-specific callbacks

2. **Base Contracts**
   - `DragonTokenizedStrategy`: Abstract base implementation with core ERC-4626 functionality
   - `DragonBaseStrategy`: Base strategy implementation to inherit from

3. **Specialized Strategy Implementations**
   - `YieldDonatingTokenizedStrategy`: Mints profit-derived shares directly to the dragon router
   - `YieldSkimmingTokenizedStrategy`: Skims asset appreciation by diluting existing shares

## Creating a New Strategy

To create a new yield-generating strategy, follow these steps:

### 1. Inherit from the Base Strategy

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { DragonBaseStrategy } from "../DragonBaseStrategy.sol";

contract MyStrategy is DragonBaseStrategy {
    // Your strategy implementation
}
```

### 2. Implement Required Functions

At minimum, you must implement these three abstract functions:

```solidity
/**
 * @dev Deploy funds to your yield-generating mechanism
 */
function _deployFunds(uint256 _amount) internal override {
    // Logic to deploy funds to yield source
}

/**
 * @dev Free up funds when withdrawals are requested
 */
function _freeFunds(uint256 _amount) internal override {
    // Logic to withdraw funds from yield source
}

/**
 * @dev Harvest rewards and report current asset values
 */
function _harvestAndReport() internal override returns (uint256 _totalAssets) {
    // Logic to harvest rewards, compound if needed
    // Return the total assets currently managed
}
```

### 3. Optional Overrides

You can also override these functions for more control:

```solidity
/**
 * @dev Perform regular maintenance between reports (optional)
 */
function _tend(uint256 _totalIdle) internal override {
    // Logic for interim maintenance (e.g., compounding)
}

/**
 * @dev Determine if tending is needed (optional)
 */
function _tendTrigger() internal view override returns (bool) {
    // Logic to determine if tend should be called
    return /* condition for tending */;
}

/**
 * @dev Emergency withdraw implementation (optional but recommended)
 */
function _emergencyWithdraw(uint256 _amount) internal override {
    // Logic for emergency withdrawals after shutdown
}
```

## Specialized Yield Distribution Strategies

### YieldDonatingTokenizedStrategy

Used for productive assets to generate and donate profits to the dragon router:

```solidity
import { DragonTokenizedStrategy } from "../DragonTokenizedStrategy.sol";

contract MyYieldDonatingStrategy is YieldDonatingTokenizedStrategy {
    // Override specific functions as needed
}
```

Key characteristics:
- Mints new shares from profits directly to dragon router
- During loss scenarios, can burn dragon router shares to protect user principal
- Best for strategies with discrete profit events

### YieldSkimmingTokenizedStrategy

Used for continuously appreciating assets like liquid staking tokens:

```solidity
import { DragonTokenizedStrategy } from "../DragonTokenizedStrategy.sol";

contract MyYieldSkimmingStrategy is YieldSkimmingTokenizedStrategy {
    // Override specific functions as needed
}
```

Key characteristics:
- Skims asset appreciation
- Dilutes existing shares by minting new ones to dragon router
- Best for assets with built-in yield like LSTs (mETH, stETH)

## Deployment Pattern

1. Deploy your strategy:

```solidity
constructor(
    address _asset,         // Underlying token address
    string memory _name,    // Strategy name
    address _management,    // Management address
    address _keeper,        // Keeper address
    address _emergencyAdmin, // Emergency admin address
    address _donationAddress // Dragon router address that receives yield
) DragonBaseStrategy(
    _asset, _name, _management, _keeper, _emergencyAdmin, _donationAddress
) {}
```

2. Initialize the strategy (handled automatically by the constructor)

## Technical Deep Dive

### Share Price Calculations

The share price in these strategies is calculated differently depending on the yield distribution mechanism:

1. **Standard ERC-4626 Calculation** (Base implementation):
   ```
   pricePerShare = totalAssets / totalSupply
   ```

2. **YieldDonatingTokenizedStrategy** (For discrete profit events):
   - When profit is reported, new shares are minted to the dragon router
   - These shares represent the full amount of profit, thus diluting all shares slightly
   - Formula: `profit shares = convertToShares(profit)`

3. **YieldSkimmingTokenizedStrategy** (For appreciating assets):
   - Uses a specialized conversion formula that accounts for the dilution
   - When converting profit to shares: `shares = profit * totalSupply / (totalAssets - profit)`
   - This ensures proper accounting when the asset itself appreciates in value

### Funds Flow Diagram

```
User Deposits
     ↓
┌────────────┐     ┌──────────────┐     ┌──────────────┐
│ Strategy   │ ←── │ Yield Source │     │ Dragon       │
│ Contract   │ ──→ │ (e.g., AAVE) │     │ Router       │
└────────────┘     └──────────────┘     └──────────────┘
     │                                        ↑
     └────────────────────────────────────────┘
           Yield is distributed as shares
```

### Real-World Use Cases

1. **Lending Strategies** (YieldDonatingTokenizedStrategy)
   - Deploy funds to lending platforms like Aave or Compound 
   - Harvest interest periodically
   - Convert interest to shares and donate to dragon router

2. **Liquid Staking Tokens** (YieldSkimmingTokenizedStrategy)
   - Wrap LSTs like stETH or mETH
   - Capture the natural appreciation of the token
   - Convert appreciation to shares for the dragon router

3. **Productive Assets with Automated Compounding**
   - Deploy funds to vaults, farms, or other yield sources
   - Harvest rewards, swap for more of the underlying asset
   - Report increased asset balance as profit

## Security Considerations

### Strategy-Specific Risks

1. **Oracle Manipulation**
   - If your strategy relies on price oracles, ensure they are resistant to manipulation
   - Consider using time-weighted average prices (TWAPs) or multiple oracle sources

2. **Slippage Control**
   - Always implement slippage protection for any on-chain swaps
   - Set reasonable defaults and allow keepers to adjust as needed

3. **Flash Loan Attacks**
   - Be cautious of protocols vulnerable to flash loan attacks
   - Test your strategy against simulated flash loan scenarios

4. **Centralization Risks**
   - Minimize reliance on centralized components that could be compromised
   - Use multisigs for critical emergency functions

## Development and Testing

Robust testing is critical for any yield-generating strategy. Follow these guidelines to ensure your strategy is thoroughly tested:

### Test Setup

```bash
# Install dependencies
forge install

# Run all tests
forge test

# Run specific test files
forge test --match-path test/DragonTokenizedStrategy.t.sol
forge test --match-path test/YieldDonatingTokenizedStrategy.t.sol
forge test --match-path test/YieldSkimmingTokenizedStrategy.t.sol

# Run tests with gas reporting
forge test --gas-report

# Run fuzz tests with increased runs
forge test --match-contract FuzzTest --fuzz-runs 1000
```