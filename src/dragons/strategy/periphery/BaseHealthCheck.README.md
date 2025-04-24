# BaseHealthCheck

A safety mechanism for Yearn V3 strategies to prevent unexpected large profits or losses from being recorded without manual intervention from management.

## Overview

The `BaseHealthCheck` contract acts as a safety net for Dragon strategies to ensure that automated reports don't record unexpectedly large profits or losses that might indicate an issue with the strategy or an attempted exploit.

By integrating this contract, strategies gain protection from MEV attacks, price manipulation, and other unforeseen circumstances that could lead to reporting incorrect or malicious values.

## Key Features

- **Configurable Limits**: Set custom maximum profit and loss limits as ratios in basis points.
- **Auto-restoration**: If turned off for a single report, the health check automatically reactivates for the next report.
- **Management Controls**: Only management can adjust limits or disable the health check for a single report.
- **Simple Integration**: Inherits from `DragonBaseStrategy` with no additional external dependencies.

## Usage

To use the BaseHealthCheck, simply inherit from it and set your desired profit and loss limit ratios:

```solidity
import {BaseHealthCheck} from "periphery/BaseHealthCheck.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyStrategy is BaseHealthCheck {
    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress
    ) DragonBaseStrategy(_asset, _name, _management, _keeper, _emergencyAdmin, _donationAddress) {
        // Set profit limit to 20% (2000 basis points)
        _setProfitLimitRatio(2000);
        
        // Set loss limit to 5% (500 basis points)
        _setLossLimitRatio(500);
    }
    
    function _deployFunds(uint256 _amount) internal override {
        // Strategy-specific deployment logic
    }
    
    function _freeFunds(uint256 _amount) internal override {
        // Strategy-specific withdrawal logic
    }
    
    function _harvestAndReport() internal override returns (uint256) {
        // Strategy-specific harvesting logic
        uint256 totalAssets = _calculateTotalAssets();
        
        // The BaseHealthCheck will automatically check if the profit/loss
        // is within acceptable bounds before finalizing the report
        return totalAssets;
    }
    
    // Add other strategy-specific functions here
}
```

## Function Reference

### View Functions

- `profitLimitRatio() public view returns (uint256)`: Returns the current profit limit ratio in basis points.
- `lossLimitRatio() public view returns (uint256)`: Returns the current loss limit ratio in basis points.
- `doHealthCheck() public view returns (bool)`: Returns whether health checks are currently enabled.

### Management Functions

- `setProfitLimitRatio(uint256 _newProfitLimitRatio) external onlyManagement`: Sets a new profit limit ratio in basis points.
- `setLossLimitRatio(uint256 _newLossLimitRatio) external onlyManagement`: Sets a new loss limit ratio in basis points.
- `setDoHealthCheck(bool _doHealthCheck) public onlyManagement`: Enables or disables health checking.

### Internal Functions

- `_executeHealthCheck(uint256 _newTotalAssets) internal virtual`: Validates reported assets against profit/loss limits.
- `_setProfitLimitRatio(uint256 _newProfitLimitRatio) internal`: Internal helper to set profit limit ratio.
- `_setLossLimitRatio(uint256 _newLossLimitRatio) internal`: Internal helper to set loss limit ratio.

## Best Practices

1. **Set Appropriate Limits**:
   - For stable strategies (lending, staking), use tighter limits (e.g., 1-5%)
   - For volatile strategies (yield farming, options), use wider limits (e.g., 10-30%)

2. **Handling Edge Cases**:
   - If a report should exceed limits for legitimate reasons, management can temporarily disable the health check for that single report

3. **Emergency Response**:
   - Keep monitoring systems in place to alert when a health check fails
   - Document procedures for manual intervention when needed

## Examples

### Scenario 1: Configuring for a Lending Strategy

```solidity
// A lending strategy with more conservative limits
contract LendingStrategy is BaseHealthCheck {
    constructor(...) DragonBaseStrategy(...) {
        // 5% max profit per report
        _setProfitLimitRatio(500);
        
        // 2% max loss per report
        _setLossLimitRatio(200);
    }
    
    // Strategy implementation...
}
```

### Scenario 2: Configuring for a Yield Farming Strategy

```solidity
// A yield farming strategy with higher limits due to volatility
contract YieldFarmingStrategy is BaseHealthCheck {
    constructor(...) DragonBaseStrategy(...) {
        // 30% max profit per report
        _setProfitLimitRatio(3000);
        
        // 15% max loss per report
        _setLossLimitRatio(1500);
    }
    
    // Strategy implementation...
}
```

## Under the Hood

The `BaseHealthCheck` implements an override of the standard `harvestAndReport()` function to wrap the strategy's `_harvestAndReport()` with health check logic. After the strategy calculates its total assets, the health check compares this value with the current total assets to determine if the profit or loss is within acceptable bounds.

If the profit or loss exceeds the configured limits, the transaction reverts with a "healthCheck" error, requiring manual intervention from management.

## References

- [Yearn V3 Tokenized Strategy Documentation](https://docs.yearn.fi/developers/v3/strategy_writing_guide)
- [Yearn V3 Periphery GitHub Repository](https://github.com/yearn/tokenized-strategy-periphery) 