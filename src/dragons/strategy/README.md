# Octant V2 TokenizedStrategy

## Overview

This repository contains a specialized fork of Yearn V3's TokenizedStrategy contracts with significant modifications for Octant V2's yield distribution mechanism. These contracts provide a framework for creating ERC-4626 compliant tokenized investment strategies with yield distribution capabilities through a "Dragon Router" pattern.

## Key Differences from Yearn V3

1. **Dragon Router Mechanism**
   - Added `dragonRouter` parameter and storage variable to direct yield to a specified address
   - Different implementation strategies for yield distribution (Donating vs Skimming)

2. **Removed Features**
   - Eliminated performance fees and fee distribution mechanism
   - Removed profit unlocking mechanism (profits are immediately donated)
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
    address _dragonRouter   // Dragon router address
) DragonBaseStrategy(
    _asset, _name, _management, _keeper, _emergencyAdmin, _dragonRouter
) {}
```

2. Initialize the strategy (handled automatically by the constructor)

## Development and Testing

```bash
# Install dependencies
forge install

# Run tests
# Run all tests
forge test

# Run specific test files
forge test --match-path test/DragonTokenizedStrategy.t.sol
forge test --match-path test/YieldDonatingTokenizedStrategy.t.sol
forge test --match-path test/YieldSkimmingTokenizedStrategy.t.sol

# Run tests with gas reporting
forge test --gas-report
