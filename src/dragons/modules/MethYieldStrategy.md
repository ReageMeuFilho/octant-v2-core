# Contract Summary and Internal Security Audit Report on MethYieldStrategy

## MethYieldStrategy.sol

### High-Level Overview

MethYieldStrategy is a specialized module designed to manage mETH (Mantle liquid staked ETH) and capture yield from its appreciation in value. The strategy tracks the ETH value of mETH deposits through exchange rate monitoring and reports the appreciation as profit to the TokenizedStrategy layer without requiring any active management of the underlying tokens.

Unlike traditional yield strategies that deploy capital to external protocols, this strategy is passive and simply captures the natural appreciation of mETH as it accrues staking rewards. This approach minimizes smart contract risk while still providing a mechanism to extract value from yield-bearing tokens.

### Key Features

#### Exchange Rate Tracking

- Tracks the ETH:mETH exchange rate at each harvest
- Uses Mantle's staking contract as the authoritative source for exchange rates
- Detects exchange rate increases as a form of yield
- Provides public access to current exchange rate

```solidity
/// @dev The ETH value of 1 mETH at the last harvest, scaled by 1e18
uint256 public lastReportedExchangeRate;

```

#### Yield Harvesting Through Exchange Rate Appreciation

- Calculates profit based on the increase in ETH value of held mETH tokens
- Converts ETH-denominated profit to mETH terms for TokenizedStrategy accounting
- Updates the stored exchange rate for future comparisons

```solidity
function _harvestAndReport() internal virtual override returns (uint256) {
  uint256 currentExchangeRate = _getCurrentExchangeRate();

  // Get the current balance of mETH in the strategy
  address assetAddress = IERC4626Payable(address(this)).asset();
  uint256 mEthBalance = IERC20(assetAddress).balanceOf(address(this));

  // Calculate the profit in ETH terms
  uint256 deltaExchangeRate = currentExchangeRate - lastReportedExchangeRate;
  uint256 profitInEth = (mEthBalance.rayMul(deltaExchangeRate)).rayDiv(1e18);

  // Calculate the profit in mETH terms
  uint256 profitInMeth = (profitInEth.rayMul(1e18)).rayDiv(currentExchangeRate);

  lastReportedExchangeRate = currentExchangeRate;

  return profitInMeth;
}
```

#### Passive Strategy Design

- Implements empty `_deployFunds` and `_freeFunds` functions since mETH is already yield-bearing
- No active management required - mETH appreciates on its own through Mantle's staking system
- No tending operations needed
- Simple emergency withdrawal process that just transfers tokens

```solidity
function _deployFunds(uint256 _amount) internal override {
  // No action needed - mETH is already a yield-bearing asset
  // This function is required by the interface but doesn't need implementation
}

function _freeFunds(uint256 _amount) internal override {
  // No action needed - we just need to transfer mETH tokens
  // Withdrawal is handled by the TokenizedStrategy layer
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

### Contract Summary

**Main Functions:**

- `getCurrentExchangeRate() public view returns (uint256)`
- `_harvestAndReport() internal virtual override returns (uint256)`

**Key State Variables:**

- `IMantleStaking public immutable MANTLE_STAKING` - Interface to Mantle's staking contract
- `uint256 public lastReportedExchangeRate` - The stored ETH:mETH exchange rate from last harvest

### Key Considerations

1. **Passive Yield Capture**

   - Strategy captures yield without active management
   - Relies on Mantle's staking mechanism for yield generation
   - No external protocol risk beyond Mantle's staking contract

2. **Exchange Rate Calculations**

   - Uses WadRayMath library for precision in calculations
   - Carefully handles rate differences to calculate accurate profit amounts
   - Properly converts between ETH and mETH denominated values

3. **Integration with YieldBearingDragonTokenizedStrategy**
   - Works with YieldBearingDragonTokenizedStrategy to handle the yield-bearing nature of mETH
   - The TokenizedStrategy layer handles the actual profit distribution

### Example Scenario

1. Strategy holds 100 mETH at exchange rate 1:1 (worth 100 ETH)

   - `lastReportedExchangeRate` = 1e18
   - Total assets reported = 100 mETH

2. After time passes, exchange rate increases to 1.2:1

   - mETH balance remains 100 mETH
   - ETH value is now 120 ETH

3. During \_harvestAndReport:

   - Calculates deltaExchangeRate = 0.2e18
   - Calculates profitInEth = 100 mETH \* 0.2e18 / 1e18 = 20 ETH
   - Converts to profitInMeth = 20 ETH \* 1e18 / 1.2e18 = 16.67 mETH
   - Returns profitInMeth = 16.67 mETH
   - Updates `lastReportedExchangeRate` to 1.2e18

4. YieldBearingDragonTokenizedStrategy mints shares worth 16.67 mETH to the dragonRouter
   - Strategy still holds only 100 mETH
   - dragonRouter receives shares representing 16.67 mETH

### Security Implications

1. **Exchange Rate Source Trust**

   - Complete dependency on Mantle's staking contract for exchange rates
   - Contract is hard-coded to the Mantle staking contract address (0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f)

2. **Precision Handling**

   - Uses WadRayMath for ray-based math operations (10^27 precision)
   - Careful handling of division operations to prevent significant precision loss

3. **Yield Calculation**
   - Calculates yield based on exchange rate differences
   - Only captures positive yield (when exchange rate increases)
   - Simple, transparent approach that minimizes potential errors
