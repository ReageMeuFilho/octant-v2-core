# BaseStrategies & TokenizedStrategies

## Product Vision & Motivation

**Vision:** Create defipunk funding pools that aggregate and safeguard user principal to yield and automatically donates profits to public goods and causes. Vaults funtion kind of like Kickstarter but with continuous yield generation instead of one-time contributions.

**Principal Protection + Automatic Yield Routing + Trust Minimization + Time-Delayed Changes + Proportional Distribution = Defipunk Funding Pools**

**Core Motivation:**
- **Primary Use Case:** Function like Kickstarter but with continuous yield generation instead of one-time contributions - enabling collective funding of public goods through pooled capital that generates continuous donations while preserving user principal
- **Extended Applications:** Automate treasury management, subscription models, and any scenario requiring automatic yield distribution
- **Trust Minimization:** Eliminate counterparty risk through mathematical guarantees, time-delayed changes, and transparent fund routing
- **Capital Efficiency:** Preserve principal while generating continuous cash flows for designated purposes, creating sustainable funding models

## Strategy Variants

The system provides two specialized implementations optimized for different yield generation patterns:

#### YieldDonatingTokenizedStrategy
- **Use Case:** Traditional yield strategies with discrete harvest cycles (DeFi protocols, liquidity mining, lending)
- **Mechanism:** Mints new shares to dragon router equivalent to profit generated since last report
- **Implementation:** Overrides `report()` to call `harvestAndReport()` and mint profit-based shares
- **Loss Protection:** Burns dragon router shares to absorb losses before affecting user principal if flag is enabled
- **Optimal For:** Strategies where totalAssets can be precisely calculated and profits are harvested periodically

#### YieldSkimmingTokenizedStrategy  
- **Use Case:** Appreciating assets like liquid staking tokens (mETH, stETH) where value grows continuously
- **Mechanism:** Skims appreciation through share dilution while using vault shares to snapshot underlying principal on user deposit.
- **Implementation:** Tracks exchange rates in RAY precision (1e27), and relies on underlying strategy's conversion function as part of profit and loss calculation.
- **Loss Protection:** Burns shares from dragon router if flag is enabled, and absorbs losses before affecting user principal if flag is enabled.
- **Optimal For:** Assets that appreciate in value over time

#### Implementation Differences

**Harvest Reporting:**
- YieldDonating: Returns `uint256 totalAssets` from `_harvestAndReport()`
- YieldSkimming: Returns `(int256 deltaAtNewRate, int256 deltaAtOldRate)` from `_harvestAndReport()`

**Share Conversion:**
- YieldDonating: Standard ERC4626 conversion using total assets
- YieldSkimming: Exchange rate-based conversion 

**Exchange Rate Precision:**
- YieldDonating: No exchange rate tracking required
- YieldSkimming: RAY precision (1e27) exchange rate storage with WadRayMath library integration

**State Management:**
- YieldDonating: Standard ERC4626 state tracking
- YieldSkimming: Custom storage slot for exchange rate data, ETH value calculations vs share supply

**Update Timing:**
- YieldDonating: Manual keeper-triggered reports at optimal intervals generate and harvest profit.
- YieldSkimming: Manual keeper-triggered reports at optimal intervals skim value appreciation above principal.

## Trust Minimization

#### Fee Removal
- Eliminates protocol fee extraction present in standard Yearn implementations at the strategy level
- No management fees or performance fees charged to users at the strategy level
- Direct, defipunk, yield flow to dragon router without intermediaries 

#### Dragon Router Protection
- 14-day cooldown period for any dragon router changes
- Two-step process: initiate change → wait cooldown → finalize
- Management can cancel pending changes during cooldown
- Users have advance notice and exit window

#### Reduced Trust Requirements
- Remains composable with other 4626 vaults
- Transparent donation destination with change protection
- Yield flows directly to stated destination
- Distribution mechanics up to implementation address (see /mechanisms)

#### User Protection
- `PendingDragonRouterChange` event provides early warning
- Time to withdraw if disagreeing with new destination
- Cannot be changed instantly or without notice
- Preserves user agency in donation decisions


## Security Model and Trust Assumptions

### Trusted Parties

The following actors are considered **trusted** in the security model:

1. **Management**: Strategy management has administrative control and is assumed to act in good faith. Management can:
   - Modify health check parameters and disable health checks when necessary
   - Update keeper and emergency admin addresses
   - Initiate dragon router changes (subject to 14-day cooldown)

2. **Keepers**: Automated or manual actors responsible for calling `report()` functions. Keepers are trusted to:
   - Call reports at appropriate intervals
   - Not engage in MEV attacks or manipulation
   - Operate in the best interest of the strategy

3. **Emergency Admin**: Trusted party with emergency powers to:
   - Shutdown strategies in crisis situations
   - Execute emergency withdrawals when necessary

### Security Assumptions

The security model makes the following key assumptions:

1. **External Protocol Integrity**: The underlying protocols (RocketPool) are assumed to operate correctly and not be compromised.

2. **Asset Contract Validity**: The rETH token contract is assumed to implement the expected interface correctly.

3. **Oracle Reliability**: Exchange rate data from RocketPool is assumed to be generally reliable, though validation bounds are implemented as defense-in-depth.

4. **Dragon Router Beneficiary**: The dragon router address is assumed to be a legitimate beneficiary for donated yield.

### Threat Model Boundaries

**In Scope Threats:**
- External attackers exploiting contract vulnerabilities
- Malicious users attempting to drain funds or manipulate calculations
- Oracle manipulation within reasonable bounds (see healthcheck mitigations)
- Precision attacks and edge case exploitation

**Out of Scope Threats:**
- Malicious management, keepers, or emergency admin actions
- Complete compromise of underlying yield source protocols (RocketPool)
- Governance attacks on trusted parties
- Social engineering or off-chain attacks

## Periphery Contracts

The system includes several utility contracts that extend strategy functionality:

#### BaseHealthCheck & BaseYieldSkimmingHealthCheck
- **Purpose:** Prevent unexpected profit/loss reporting through configurable bounds checking
- **Implementation:** Inherit from respective base contracts and override `_harvestAndReport()`
- **Configuration:** 
  - `profitLimitRatio`: Maximum acceptable profit as basis points (default 100% = 10,000 BPS)
  - `lossLimitRatio`: Maximum acceptable loss as basis points (default 0%)
  - `doHealthCheck`: Boolean flag to enable/disable checks (auto re-enables after bypass)
- **Behavior:** Transaction reverts if profit/loss exceeds configured limits, requiring manual intervention
- **Variants:** 
  - Standard version for BaseStrategy with totalAssets comparison
  - Specialized version for BaseYieldSkimmingStrategy with exchange rate-adjusted validation using `totalSupply()` vs exchange-rate-calculated total ETH value

#### UniswapV3Swapper
- **Purpose:** Standardized Uniswap V3 integration for token swapping within strategies
- **Features:**
  - Exact input swaps (`_swapFrom`) and exact output swaps (`_swapTo`)
  - Automatic routing via base token (default WETH) for multi-hop swaps
  - Configurable minimum swap amounts to avoid dust transactions
  - Automatic allowance management with safety checks
- **Configuration:**
  - `uniFees`: Mapping of token pairs to their respective pool fees
  - `minAmountToSell`: Minimum threshold to prevent dust swaps
  - `router`: Uniswap V3 router address (customizable per chain)
  - `base`: Base token for routing (default WETH mainnet)
- **Usage:** Strategies inherit this contract and call `_setUniFees()` during initialization to configure trading pairs

## Functional Requirements
WLOG, I refer to yield donating and yield skimming strategies as 'donation strategies' as requirements generally apply to both with the exception of FR-2 for which the first two acceptance criteria do not apply to yield skimming variants.

#### FR-1: Strategy Deployment & Initialization
- **Requirement:** The system must enable permissionless deployment of donation-generating yield strategies where users pool capital to fund causes, with standardized initialization parameters including asset, management roles, and dragon router beneficiary configuration.
- **Implementation:** `BaseStrategy` constructor, `TokenizedStrategy.initialize()`, immutable proxy pattern setup
- **Acceptance Criteria:**
  - Strategy deploys with valid asset, name, management, keeper, emergency admin, and dragon router addresses
  - Storage initialization prevents double-initialization through `initialized` flag check
  - EIP-1967 proxy implementation slot correctly stores TokenizedStrategy address for Etherscan interface detection
  - All critical addresses including dragon router donation destination are validated as non-zero during initialization

#### FR-2: Asset Management & Yield Operations
- **Requirement:** Strategies must efficiently deploy pooled user capital to yield sources, enable withdrawals of principal while preserving donation flow, and report accurate yield accounting that separates user principal from donated profits.
- **Implementation:** `_deployFunds()`, `_freeFunds()`, `_harvestAndReport()` virtual functions, `deployFunds()`, `freeFunds()`, `harvestAndReport()` callbacks
- **Acceptance Criteria:**
  - Pooled assets are automatically deployed to yield sources upon user deposits via `deployFunds` callback if applicable to the strategy
  - User withdrawal requests trigger `freeFunds` callback to liquidate necessary positions while maintaining donation capacity if applicable to the strategy
  - Harvest reports provide accurate accounting that distinguishes between user principal and profits destined for dragon router
  - Loss scenarios are properly handled with configurable maxLoss parameters protecting user principal through healthchecks

#### FR-3: Role-Based Access Control
- **Requirement:** The system must implement comprehensive role-based permissions ensuring proper governance of donation strategies, with management transfer capabilities, keeper operations for yield harvesting, and emergency administration powers to protect pooled funds.
- **Implementation:** `onlyManagement`, `onlyKeepers`, `onlyEmergencyAuthorized` modifiers, `setPendingManagement()`, `acceptManagement()`, role setter functions
- **Acceptance Criteria:**
  - Management can set keeper and emergency admin addresses with zero-address validation for strategy governance
  - Management transfer requires two-step process (setPending + accept) to prevent accidental control transfers of donation flows
  - Keepers can call `report()` and `tend()` functions for strategy maintenance and donation generation
  - Emergency admin can shutdown strategies and perform emergency withdrawals to protect pooled user capital

#### FR-4: Dragon Router Donation Management
- **Requirement:** Strategies must support configurable dragon router beneficiary addresses ensuring donated yield flows to intended causes, with user protection through time-delayed changes preventing sudden redirection of donation streams.
- **Implementation:** `setDragonRouter()`, `finalizeDragonRouterChange()`, `cancelDragonRouterChange()`, 14-day cooldown mechanism
- **Acceptance Criteria:**
  - Dragon router changes require 14-day cooldown period before finalization to protect donor intent
  - Users receive `PendingDragonRouterChange` event notification with effective timestamp for donation transparency
  - Management can cancel pending changes during cooldown period if beneficiary change is inappropriate
  - Finalization only succeeds after cooldown elapsed with valid pending dragon router address

#### FR-5: Emergency Controls & Strategy Shutdown
- **Requirement:** The system must provide emergency mechanisms to halt donation strategy operations, prevent new deposits while protecting existing contributors, and enable fund recovery to safeguard pooled capital during crisis situations.
- **Implementation:** `shutdownStrategy()`, `emergencyWithdraw()`, `_emergencyWithdraw()` override, shutdown state checks
- **Acceptance Criteria:**
  - Strategy shutdown permanently prevents new deposits and mints while preserving existing donation commitments
  - Existing user withdrawals and redemptions continue functioning post-shutdown to protect contributor capital
  - Emergency withdrawals can only occur after shutdown by authorized roles to prevent fund misappropriation
  - Shutdown state is irreversible once activated to maintain contributor trust and donation integrity

#### FR-6: ERC4626 Vault Operations
- **Requirement:** Strategies must provide full ERC4626 compliance enabling users to contribute capital, track their principal, and withdraw funds while maintaining continuous donation flow to dragon router destinations.
- **Implementation:** `deposit()`, `mint()`, `withdraw()`, `redeem()` with maxLoss variants, preview functions, max functions
- **Acceptance Criteria:**
  - All ERC4626 core functions operate correctly with proper share/asset conversions maintaining separation between user principal and donated yield
  - MaxLoss parameters enable users to specify acceptable loss tolerance for withdrawals protecting their contributed capital
  - Preview functions accurately simulate transaction outcomes without affecting donation accounting or state changes
  - Max functions respect strategy-specific deposit/withdrawal limits and shutdown states while preserving donation mechanism integrity

## User Lifecycle Documentation

#### Phase 1: Strategy Discovery & Impact Assessment
**User Story:** "As a contributor, I want to discover and analyze available funding pools so that I can make informed decisions about where to allocate my capital for maximum public good impact."

**Flow:**
1. User browses available strategies through frontend or direct contract queries
2. System displays strategy metadata including asset, projected donation rates, beneficiary organizations, and risk metrics
3. User analyzes strategy implementation and historical donation performance
4. User evaluates cause alignment and social impact effectiveness
5. User decides to proceed with contribution or continue research

**NOTE:**
- Dragon router changes create uncertainty about future beneficiary destinations but require a 14 day delay.

#### Phase 2: Initial Contribution & Pool Entry
**User Story:** "As a backer, I want to easily contribute assets to funding pools so that I can start generating continuous donations to causes I support while preserving my principal."

**Flow:**
1. User approves asset spending for strategy contract
2. User calls `deposit(assets, receiver)` or `mint(shares, receiver)` function
3. System validates deposit limits and strategy operational status
4. System transfers assets, deploys to yield source via `deployFunds` callback
5. System mints proportional shares and emits `Deposit` event

**NOTE:**
- Deposit limits may reject transactions due to underlying yield source state

#### Phase 3: Donation Generation & Impact Monitoring
**User Story:** "As a funding pool participant, I want to monitor my principal preservation and the donation impact being generated so that I can make informed decisions about continued participation."

**Flow:**
1. User queries current share balance and principal value via `balanceOf` and `convertToAssets`
2. System displays real-time donation metrics and strategy health indicators
3. User monitors dragon router activities and public goods funding distributions
4. Keeper calls `report()` to harvest profits and update donation accounting
5. User observes preserved principal value and tracks donated yield to beneficiaries

**NOTE:**
- Strategy performance depends on external keeper activity for timely reporting
- Keeper should always use MEV protected mem pools to broadcast transactions safely

#### Phase 4: Principal Withdrawal & Exit Strategy
**User Story:** "As a funding pool participant, I want to withdraw my principal efficiently so that I can access my preserved capital when needed while understanding the impact on ongoing donations."

**Flow:**
1. User determines withdrawal amount and acceptable loss tolerance
2. User calls `withdraw(assets, receiver, owner, maxLoss)` or `redeem` variant
3. System checks withdrawal limits and validates maxLoss parameters
4. System frees assets from yield source via `freeFunds` callback
5. System transfers freed assets to receiver and burns corresponding shares

**NOTE:**
- Withdrawal timing depends on yield source liquidity and may incur losses without slippage checks