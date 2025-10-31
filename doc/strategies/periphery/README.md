# Yearn Tokenized Strategy Periphery Contracts

This collection contains periphery contracts for extending the functionality of Dragon Strategies based on the Yearn V3 Tokenized Strategy framework. These components provide optional functionality to enhance the capabilities of your strategies.

## Overview

The Yearn V3 Tokenized Strategy periphery contracts in this directory offer battle-tested, modular components that can be integrated with your Dragon strategies to add common functionality without having to reimplement it from scratch.

## Contracts

### 1. BaseHealthCheck

The `BaseHealthCheck` contract provides a safety mechanism for strategy reports to prevent unexpected large profits or losses from being recorded without manual intervention. 

**Key Features:**
- Configurable profit and loss ratio limits in basis points
- Automatic health checking during reports
- Management ability to temporarily disable health checks for specific reports
- Prevents MEV attacks and unexpected behavior from being recorded

**How to Use:**
```solidity
// Example implementation
contract MyStrategy is BaseHealthCheck {
    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress
    ) DragonBaseStrategy(_asset, _name, _management, _keeper, _emergencyAdmin, _donationAddress) {
        // Set your custom profit limit (e.g., 50% max profit per report)
        _setProfitLimitRatio(5000); // 50% in basis points
        
        // Set your custom loss limit (e.g., 10% max loss per report)
        _setLossLimitRatio(1000); // 10% in basis points
    }
    
    // Your implementation of required functions...
}
```

### 2. UniswapV3Swapper

The `UniswapV3Swapper` contract provides functionality for swapping tokens through Uniswap V3, useful for strategies that need to swap reward tokens back into the strategy's underlying asset.

**Key Features:**
- Multiple fee tier support
- Configurable slippage protection
- Automatic fee tier selection
- Efficient path encoding for swaps
- Permission-controlled router updates

**How to Use:**
```solidity
// Example implementation
contract MyStrategy is UniswapV3Swapper {
    address public rewardToken;

    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        address _uniswapV3Router,
        address _rewardToken
    ) 
        DragonBaseStrategy(_asset, _name, _management, _keeper, _emergencyAdmin, _donationAddress)
        UniswapV3Swapper(_uniswapV3Router)
    {
        rewardToken = _rewardToken;
    }
    
    function _harvestAndReport() internal override returns (uint256) {
        // Claim rewards...
        
        // Swap rewards for underlying asset
        uint256 rewardBalance = ERC20(rewardToken).balanceOf(address(this));
        if (rewardBalance > 0) {
            // Determine minimum amount out based on price oracle or fixed slippage
            uint256 minAmountOut = calculateMinAmountOut(rewardBalance);
            
            // Execute the swap
            _swapFrom(rewardToken, address(asset), rewardBalance, minAmountOut);
        }
        
        // Return total assets including the swapped rewards
        return _calculateTotalAssets();
    }
    
    // Your implementation of other required functions...
}
```

## Notes on Integration

1. **Inheritance Order**: When inheriting multiple periphery contracts, pay attention to the inheritance order to ensure correct function resolution.

2. **Constructor Setup**: Each periphery contract might require specific parameters to be passed to its constructor. Ensure all required parameters are provided when inheriting.

3. **Gas Optimization**: These contracts are designed to be gas-efficient, but you should still test thoroughly in a forked environment to ensure acceptable gas costs for your specific use case.

4. **Upgrades & Maintenance**: The management address of your strategy can update configuration settings of these periphery components, allowing for adjustments without redeploying the entire strategy.

## References

- [Yearn V3 Tokenized Strategy Documentation](https://docs.yearn.fi/developers/v3/strategy_writing_guide)
- [Yearn V3 Periphery GitHub Repository](https://github.com/yearn/tokenized-strategy-periphery) 