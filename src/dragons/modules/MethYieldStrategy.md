# Contract Summary and Internal Security Audit Report on MethYieldStrategy

## MethYieldStrategy.sol

### High-Level Overview

MethYieldStrategy is a specialized module designed to manage mETH (Mantle liquid staked ETH) and capture yield from its appreciation in value. The strategy tracks the ETH value of mETH deposits through exchange rate monitoring and reports the appreciation as profit to the TokenizedStrategy layer without requiring any active management of the underlying tokens.

Unlike traditional yield strategies that deploy capital to external protocols, this strategy is passive and simply captures the natural appreciation of mETH as it accrues staking rewards. This approach minimizes smart contract risk while still providing a mechanism to extract value from yield-bearing tokens.

### Key Improvements & Updates

- **Storage Isolation** - Uses dedicated storage slots to prevent storage collisions in proxy patterns
- **YieldBearingDragonTokenizedStrategy Integration** - Works specifically with YieldBearingDragonTokenizedStrategy to track available yield
- **Fully Passive Yield Capture** - No active management required for yield generation

### Functionality Breakdown

#### Major Feature 1: Exchange Rate Tracking

- Stores the ETH:mETH exchange rate at each harvest
- Uses Mantle's staking contract as the authoritative source for exchange rates
- Detects exchange rate increases as a form of yield
- Provides public access to current exchange rate

```solidity
/// @dev The ETH value of 1 mETH at the last harvest, scaled by 1e18
uint256 public lastExchangeRate;

function getCurrentExchangeRate() public view returns (uint256) {
    return _getCurrentExchangeRate();
}

function _getCurrentExchangeRate() internal view virtual returns (uint256) {
    // Calculate the exchange rate by determining how much ETH 1e18 mETH is worth
    return MANTLE_STAKING.mETHToETH(1e18);
}
```

#### Major Feature 2: Yield Harvesting Through Exchange Rate Appreciation

- Calculates profit based on the increase in ETH value of held mETH tokens
- Tracks available yield separately from the deposited principal
- Converts ETH-denominated profit to mETH terms for TokenizedStrategy accounting
- Prevents reporting losses when exchange rate decreases
- Updates the stored exchange rate for future comparisons

```solidity
function _harvestAndReport() internal virtual override returns (uint256) {
  // Get current exchange rate
  uint256 currentExchangeRate = _getCurrentExchangeRate();

  // fetch available yield
  uint256 availableYield = IYieldBearingDragonTokenizedStrategy(address(this)).availableYield();

  // Get actual mETH balance (excluding yield)
  uint256 mEthBalance = asset.balanceOf(address(this)) - availableYield;

  uint256 accountingBalance = IERC4626Payable(address(this)).totalAssets();

  // Calculate the adjusted balance that accounts for value appreciation
  uint256 adjustedBalance;
  if (currentExchangeRate > lastExchangeRate) {
    // 1. Calculate the ETH value at current and previous rates
    uint256 currentEthValue = (mEthBalance * currentExchangeRate) / 1e18;
    uint256 previousEthValue = (mEthBalance * lastExchangeRate) / 1e18;

    // 2. The profit in ETH terms is the difference
    uint256 profitInEth = currentEthValue - previousEthValue;

    // 3. Convert this profit to mETH at the current exchange rate
    uint256 profitInMEth = (profitInEth * 1e18) / currentExchangeRate;

    // 4. Add this profit to the ACCOUNTING balance
    adjustedBalance = accountingBalance + profitInMEth;
  } else {
    // No appreciation or depreciation
    adjustedBalance = accountingBalance;
  }

  // Update the exchange rate for next time
  lastExchangeRate = currentExchangeRate;

  // Return the adjusted balance which includes the profit
  return adjustedBalance;
}
```

#### Major Feature 3: Passive Strategy Design

- Implements empty `_deployFunds` and `_freeFunds` functions since mETH is already yield-bearing
- No active management required - mETH appreciates on its own through Mantle's staking system
- No tending operations needed
- Simple emergency withdrawal process that just transfers tokens

```solidity
function _deployFunds(uint256 _amount) internal override {
  // No action needed - mETH is already a yield-bearing asset
}

function _freeFunds(uint256 _amount) internal override {
  // No action needed - we just need to transfer mETH tokens
}

function _emergencyWithdraw(uint256 _amount) internal override {
  // Transfer the mETH tokens to the emergency admin
  address emergencyAdmin = ITokenizedStrategy(address(this)).emergencyAdmin();
  asset.transfer(emergencyAdmin, _amount);
}

function _tend(uint256 /*_idle*/) internal override {
  // No action needed - mETH is already a yield-bearing asset
}

function _tendTrigger() internal pure override returns (bool) {
  return false;
}
```

#### Major Feature 4: Integration with YieldBearingDragonTokenizedStrategy

- Works directly with YieldBearingDragonTokenizedStrategy for yield tracking
- Accounts for available yield balance in all calculations
- Separates profit accounting from principal value accounting

### Contract Summary

**Main Functions:**

- `getCurrentExchangeRate() public view returns (uint256)`
- `_harvestAndReport() internal virtual override returns (uint256)`

**Key State Variables:**

- `IMantleStaking public immutable MANTLE_STAKING` - Interface to Mantle's staking contract
- `uint256 public lastExchangeRate` - The stored ETH:mETH exchange rate from last harvest

### Key Considerations

1. **Passive Yield Capture**

   - Strategy captures yield without active management
   - Relies on Mantle's staking mechanism for yield generation
   - No external protocol risk beyond Mantle's staking contract

2. **Economic Yield Accounting**

   - Properly accounts for yield in both ETH and mETH terms
   - Separates token balances from economic value
   - Uses accurate conversion between ETH and mETH values
   - Handles available yield separately from principal deposits

3. **Storage Security**
   - Implements storage isolation patterns to prevent proxy storage collisions
   - Uses dedicated storage slots for critical variables in the mock version
   - Follows best practices for upgradeable contracts

### Example Scenario

1. Strategy holds 100 mETH at exchange rate 1:1 (worth 100 ETH)

   - `lastExchangeRate` = 1e18
   - `availableYield` = 0 mETH
   - Total assets reported = 100 mETH

2. After time passes, exchange rate increases to 1.2:1

   - mETH balance remains 100 mETH
   - ETH value is now 120 ETH
   - Strategy calculates profit of 20 ETH

3. During \_harvestAndReport:

   - Converts 20 ETH profit to mETH: 20 ETH / 1.2 = 16.67 mETH
   - Reports adjusted balance of 116.67 mETH
   - Updates `lastExchangeRate` to 1.2e18 for future harvest cycles
   - Updates `availableYield` to 16.67 mETH

4. TokenizedStrategy layer mints shares worth 16.67 mETH to the dragonRouter

   - Strategy still holds only 100 mETH
   - Accounting tracks 116.67 mETH (100 mETH principal + 16.67 mETH yield)
   - Protocol has captured the yield

5. When withdrawing yield:
   - Yield can be withdrawn via redeemYield or withdrawYield functions
   - totalEthValueDeposited remains unchanged when withdrawing only yield
   - No impact on depositors' principal value

### Security Implications

1. **Exchange Rate Source Trust**

   - Complete dependency on Mantle's staking contract for exchange rates

2. **Precision Loss**

   - Multiple divisions in profit calculation may introduce rounding errors
   - Not a significant risk due to the large denomination of involved tokens

3. **Storage Safety**
   - Implementation uses dedicated storage slots to prevent storage collisions
   - Mock implementations follow the same pattern for testing consistency
   - Prevents potential cross-contract storage manipulation
