# YearnTokenizedStrategy.sol

## High-Level Overview

YearnTokenizedStrategy is a foundational contract that borrows heavily from Yearn's tokenized vault strategy pattern. It provides the core infrastructure for psuedo-ERC4626-compliant tokenized vaults with additional features for strategy-specific implementations. The contract serves as the base layer for more specialized strategies like YearnTokenizedImpactStrategy with the goal here being able to reuse as much of the logic as possible. Unlike traditional Yearn ERC4626 vaults, this contract uses a unique storage pattern and implements custom transfer restrictions.

The contract's architecture utilizes:

1. Storage patterns using a custom storage slot
2. Pseudo ERC20/ERC4626 compliance (transfers are disabled, shares are calculated by voting weight)
3. Access control and security measures 
4. Emergency controls and shutdown mechanisms

## Functionality Breakdown

The contract implements several core systems that form the foundation for specialized strategies:

### 1. Storage Management System:
- Safely stores and organizes all strategy information in one place
- Allows other strategies to build on top without risking data corruption
- Makes it easy to add new features without breaking existing ones

### 2. Access Control System:
- Different roles for different responsibilities:
    - Managers can change strategy settings and parameters
    - Keepers can perform routine maintenance and updates
    - Emergency admins can pause things if something goes wrong
- Safe transfer of control through a two-step process
- Emergency stops to protect user funds if issues arise
- Clear boundaries about who can do what and when

## Contract Summary

The contract provides these foundational functions:

### Strategy Initialization & Configuration:
- initialize(address,string,address,address): Sets up initial strategy parameters including asset, name, and roles
- setName(string): Updates strategy name
- setPendingManagement(address): Initiates management transfer (step 1)
- acceptManagement(): Completes management transfer (step 2)
- setKeeper(address): Updates keeper role
- setEmergencyAdmin(address): Updates emergency admin role

### Asset Management (ERC4626-like):
- totalAssets(): Returns total assets under management
- totalSupply(): Returns total share supply
- convertToShares(uint256): Converts asset amount to shares
- convertToAssets(uint256): Converts shares to asset amount
- previewDeposit(uint256): Simulates deposit outcome
- previewWithdraw(uint256): Simulates withdrawal outcome
- previewRedeem(uint256): Simulates redemption outcome
- maxDeposit(address): Returns maximum deposit possible
- maxRedeem(address): Returns maximum redemption possible

### ERC20 Functionality:
- name(): Returns strategy token name
- symbol(): Returns strategy token symbol ("?" + asset symbol)
- decimals(): Returns token decimals
- balanceOf(address): Returns account balance
- transfer(address,uint256): Transfers shares between accounts
- approve(address,uint256): Approves spender for shares
- transferFrom(address,address,uint256): Transfers shares using allowance

### EIP-2612 Support:
- permit(address,address,uint256,uint256,uint8,bytes32,bytes32): EIP-2612 permit
- nonces(address): Returns current nonce for permit
- DOMAIN_SEPARATOR(): Returns domain separator for permits

### Emergency Controls:
- shutdownStrategy(): Disables new deposits while allowing withdrawals
- isShutdown(): Returns strategy shutdown status

### Access Control:
- requireManagement(address): Validates management access
- requireKeeperOrManagement(address): Validates keeper/management access
- requireEmergencyAuthorized(address): Validates emergency access

### Internal Core Functions:
- _strategyStorage(): Returns storage pointer for strategy data
- _transfer(StrategyData,address,address,uint256): Internal transfer logic
- _mint(StrategyData,address,uint256): Internal mint logic
- _burn(StrategyData,address,uint256): Internal burn logic
- _approve(StrategyData,address,address,uint256): Internal approve logic
- _spendAllowance(StrategyData,address,address,uint256): Internal allowance spending logic

## Inherited By

### YearnTokenizedImpactStrategy:
- Extends base functionality with voting mechanics
- Adds project funding distribution
- Implements specialized share accounting
- Overrides transfer restrictions during voting phase


## Operational Risks

### Emergency Shutdown Abuse
- Emergency controls could be triggered unnecessarily
- Multiple admin roles reduce single point of failure 
- Need clear procedures for emergency situations

### Storage Collision
- Inherited contracts could accidentally override storage
- Protected by custom storage slot pattern
- Requires careful audit of inheriting contracts

## Integration Risks

### Incompatible Token Types
- Non-standard ERC20 tokens might behave unexpectedly
- Fee-on-transfer tokens need special handling
- Rebasing tokens could break share calculations