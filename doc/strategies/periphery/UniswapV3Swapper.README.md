# UniswapV3Swapper

A utility contract for Yearn V3 strategies to efficiently swap tokens using Uniswap V3 pools.

## Overview

The `UniswapV3Swapper` contract provides Dragon strategies with the ability to swap tokens via Uniswap V3, which is particularly useful for strategies that need to:

- Convert reward tokens back to the underlying asset
- Rebalance positions across different tokens
- Enter/exit positions that require token exchanges

This contract abstracts away the complexities of interacting with Uniswap V3, including path encoding, fee tier selection, and swap execution.

## Key Features

- **Multiple Fee Tier Support**: Includes functionality for all standard fee tiers (0.01%, 0.05%, 0.3%, 1%)
- **Dynamic Fee Selection**: Automatically selects the best fee tier based on token pair
- **Optimized Gas Usage**: Efficiently encodes paths and executes swaps to minimize gas costs
- **Slippage Protection**: Built-in minimum output enforcement to protect against unfavorable trades
- **Management Controls**: Only management can update the router address
- **Safe Approvals**: Properly handles token approvals and cleans up allowances after swaps

## Usage

To use the UniswapV3Swapper, inherit from it and specify the Uniswap V3 router address:

```solidity
import {UniswapV3Swapper} from "periphery/UniswapV3Swapper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyStrategy is UniswapV3Swapper {
    address public constant REWARD_TOKEN = 0x...;

    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        address _uniswapV3Router
    ) 
        DragonBaseStrategy(_asset, _name, _management, _keeper, _emergencyAdmin, _donationAddress)
        UniswapV3Swapper(_uniswapV3Router)
    {
        // Additional constructor logic if needed
    }
    
    function _deployFunds(uint256 _amount) internal override {
        // Strategy-specific deployment logic
    }
    
    function _freeFunds(uint256 _amount) internal override {
        // Strategy-specific withdrawal logic
    }
    
    function _harvestAndReport() internal override returns (uint256) {
        // 1. Claim rewards
        claimRewards();
        
        // 2. Get balance of reward token
        uint256 rewardBalance = ERC20(REWARD_TOKEN).balanceOf(address(this));
        
        // 3. Swap rewards for underlying asset if balance exists
        if (rewardBalance > 0) {
            // Calculate minimum expected output (e.g., 2% slippage)
            uint256 minAmountOut = rewardBalance * getExpectedRate() * 98 / 100;
            
            // Execute the swap
            _swapFrom(
                REWARD_TOKEN,       // from token
                address(asset),     // to token
                rewardBalance,      // amount to swap
                minAmountOut        // minimum amount to receive
            );
        }
        
        // 4. Return total strategy assets
        return _calculateTotalAssets();
    }
    
    function getExpectedRate() internal view returns (uint256) {
        // Logic to get expected exchange rate
        // Could use oracles, TWAP, or other price sources
        return /* expected rate */;
    }
    
    // Add other strategy-specific functions here
}
```

## Function Reference

### Constructor

- `constructor(address _uniswapV3Router)`: Sets the Uniswap V3 router address.

### Management Functions

- `setUniswapV3Router(address _uniswapV3Router) external onlyManagement`: Updates the Uniswap V3 router address.

### Swapping Functions

- `_swapFrom(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut) internal returns (uint256)`: Swaps tokens using the default fee tier.
- `_swapFrom(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut, uint24 _feeTier) internal returns (uint256)`: Swaps tokens using a specified fee tier.

### Internal Helper Functions

- `_getBestFeeTier(address _tokenIn, address _tokenOut) internal virtual view returns (uint24)`: Returns the recommended fee tier for a token pair.
- `_encodePath(PoolInfo memory _poolInfo) internal pure returns (bytes memory)`: Encodes a swap path.
- `_executeSwap(bytes memory _path, uint256 _amountIn, uint256 _minAmountOut) internal returns (uint256)`: Executes the swap through the router.
- `_resetAllowance(address _token, address _spender) internal`: Resets any remaining allowance to zero.

## Advanced Usage

### Custom Fee Tier Selection

Override the `_getBestFeeTier` function to implement your own fee tier selection logic:

```solidity
function _getBestFeeTier(address _tokenIn, address _tokenOut) internal override view returns (uint24) {
    // Example: Use 1% fee for specific stable pairs
    if (_tokenIn == USDC && _tokenOut == USDT) {
        return FEE_100; // 0.01%
    }
    
    // Example: Use 0.3% fee for more volatile pairs
    if (_tokenIn == WETH || _tokenOut == WETH) {
        return FEE_3000; // 0.3%
    }
    
    // Default to 0.05% for all other pairs
    return FEE_500;
}
```

### Multi-hop Swaps

For more complex swap paths involving multiple tokens:

```solidity
function _executeComplexSwap(
    address _tokenA,
    address _tokenB,
    address _tokenC,
    uint256 _amountIn,
    uint256 _minAmountOut
) internal returns (uint256) {
    // Approve token A
    ERC20(_tokenA).safeIncreaseAllowance(uniswapV3Router, _amountIn);
    
    // Create the multi-hop path
    bytes memory path = abi.encodePacked(
        _tokenA,
        FEE_500,
        _tokenB,
        FEE_3000,
        _tokenC
    );
    
    // Execute swap with multi-hop path
    uint256 amountOut = _executeSwap(path, _amountIn, _minAmountOut);
    
    // Reset allowance
    _resetAllowance(_tokenA, uniswapV3Router);
    
    return amountOut;
}
```

## Gas Optimization

To optimize gas usage when performing swaps:

1. **Batch Swaps**: If you need to swap multiple tokens, consider batching them to save on gas.
2. **Direct Routes**: Use direct routes where possible to avoid unnecessary hops.
3. **Fee Tier Selection**: Choose the appropriate fee tier based on the token pair's liquidity and volatility.
4. **Allowance Management**: Increase allowances only when needed and by the exact amount required.

## Transaction Safety

To ensure safe transactions when using this swapper:

1. **Always Use Minimum Output**: Never set `_minAmountOut` to 0, as this could lead to sandwich attacks.
2. **Verify Router Address**: Always double-check the router address to prevent interacting with malicious contracts.
3. **Test on Testnet**: Before deploying to mainnet, test swaps on testnet to ensure correct operation.
4. **Monitor Price Impact**: Large swaps might cause significant price impact; consider splitting into smaller transactions.

## References

- [Uniswap V3 Documentation](https://docs.uniswap.org/concepts/protocol/concentrated-liquidity)
- [Yearn V3 Tokenized Strategy Documentation](https://docs.yearn.fi/developers/v3/strategy_writing_guide)
- [Yearn V3 Periphery GitHub Repository](https://github.com/yearn/tokenized-strategy-periphery) 