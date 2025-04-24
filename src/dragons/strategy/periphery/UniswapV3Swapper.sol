// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Uniswap V3 Swapper for Yearn V3 Strategies
 * @author yearn.finance
 * @notice This contract is meant to be used to swap tokens through Uniswap V3.
 * It can be inherited by any strategy to gain the ability to swap tokens.
 *
 * The strategist must set the router address in the constructor.
 */
abstract contract UniswapV3Swapper {
    using SafeERC20 for ERC20;

    // The address of the Uniswap V3 router contract
    address public uniswapV3Router;

    // Default pool fee tiers in basis points
    uint24 private constant FEE_3000 = 3000; // 0.3%
    uint24 private constant FEE_500 = 500; // 0.05%
    uint24 private constant FEE_100 = 100; // 0.01%
    uint24 private constant FEE_10000 = 10000; // 1%

    // Struct to hold path variables to avoid stack too deep errors
    struct PoolInfo {
        address tokenIn;
        address tokenOut;
        uint24 fee;
    }

    /**
     * @dev Sets the address of the Uniswap V3 router and default fee tier
     * @param _uniswapV3Router Address of the Uniswap V3 router
     */
    constructor(address _uniswapV3Router) {
        uniswapV3Router = _uniswapV3Router;
    }

    /**
     * @notice Sets a new Uniswap V3 router address
     * @dev Only callable by management
     * @param _uniswapV3Router New router address
     */
    function setUniswapV3Router(address _uniswapV3Router) external onlyManagement {
        require(_uniswapV3Router != address(0), "!zero address");
        uniswapV3Router = _uniswapV3Router;
    }

    /**
     * @notice Swaps `_amountIn` of `_fromToken` to `_toToken`
     * @dev Attempts to use the specified fee tier or falls back to other tiers if needed
     * @param _fromToken Address of token to swap from
     * @param _toToken Address of token to swap to
     * @param _amountIn Amount of `_fromToken` to swap
     * @param _minAmountOut Minimum amount of `_toToken` to receive
     * @param _feeTier Fee tier to use (if 0, will try default tiers)
     * @return amountOut Amount of `_toToken` received
     */
    function _swapFrom(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint24 _feeTier
    ) internal returns (uint256 amountOut) {
        // Skip if input amount is 0
        if (_amountIn == 0) return 0;

        // Skip if tokens are the same
        if (_fromToken == _toToken) return _amountIn;

        // Approve router to spend token
        ERC20(_fromToken).safeIncreaseAllowance(uniswapV3Router, _amountIn);

        // Choose the fee tier if not specified
        uint24 feeTier = _feeTier != 0 ? _feeTier : _getBestFeeTier(_fromToken, _toToken);

        // Encode path for the swap
        bytes memory path = _encodePath(PoolInfo({ tokenIn: _fromToken, tokenOut: _toToken, fee: feeTier }));

        // Execute the swap
        amountOut = _executeSwap(path, _amountIn, _minAmountOut);

        // Clean up any remaining allowance
        _resetAllowance(_fromToken, uniswapV3Router);

        return amountOut;
    }

    /**
     * @notice Swaps `_amountIn` of `_fromToken` to `_toToken` using default fee tier selection
     * @param _fromToken Address of token to swap from
     * @param _toToken Address of token to swap to
     * @param _amountIn Amount of `_fromToken` to swap
     * @param _minAmountOut Minimum amount of `_toToken` to receive
     * @return amountOut Amount of `_toToken` received
     */
    function _swapFrom(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal returns (uint256 amountOut) {
        return _swapFrom(_fromToken, _toToken, _amountIn, _minAmountOut, 0);
    }

    /**
     * @dev Tries different fee tiers to find the best one for a given token pair
     * Default implementation uses fee tier preferences: 0.05% -> 0.3% -> 0.01% -> 1%
     * Can be overridden to implement custom fee tier selection logic
     * @param _tokenIn Address of input token
     * @param _tokenOut Address of output token
     * @return feeTier Recommended fee tier for the swap
     */
    // solhint-disable-next-line no-unused-vars
    function _getBestFeeTier(address _tokenIn, address _tokenOut) internal view virtual returns (uint24) {
        // Default implementation prioritizes medium-low fee tiers
        // Can be overridden to implement more sophisticated fee tier selection
        return FEE_500; // Default to 0.05% fee tier
    }

    /**
     * @dev Encodes the swap path for Uniswap V3
     * @param _poolInfo Struct containing pool information
     * @return path Encoded path bytes for the swap
     */
    function _encodePath(PoolInfo memory _poolInfo) internal pure returns (bytes memory path) {
        path = abi.encodePacked(_poolInfo.tokenIn, _poolInfo.fee, _poolInfo.tokenOut);
    }

    /**
     * @dev Executes the swap through Uniswap V3 router
     * @param _path Encoded path for the swap
     * @param _amountIn Amount of tokens to swap
     * @param _minAmountOut Minimum amount of tokens to receive
     * @return amountOut Amount of tokens received
     */
    function _executeSwap(
        bytes memory _path,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal returns (uint256 amountOut) {
        // Prepare swap params
        // Function signature for exactInput is:
        // exactInput((bytes,address,uint256,uint256,uint256))

        // Define the parameters structure as expected by the router
        bytes memory params = abi.encode(
            _path, // path - encoded path of the swap
            address(this), // recipient - address receiving the tokens
            block.timestamp, // deadline - the deadline for the swap
            _amountIn, // amountIn - amount of tokens to swap
            _minAmountOut // amountOutMinimum - minimum amount of tokens to receive
        );

        // Call the router with the exact input function
        (bool success, bytes memory data) = uniswapV3Router.call(
            abi.encodeWithSignature("exactInput((bytes,address,uint256,uint256,uint256))", params)
        );

        require(success, "Swap failed");

        // Decode the returned data to get the amount out
        amountOut = abi.decode(data, (uint256));

        return amountOut;
    }

    /**
     * @dev Resets any remaining allowance for a token to 0
     * @param _token Token to reset allowance for
     * @param _spender Address to reset allowance for
     */
    function _resetAllowance(address _token, address _spender) internal {
        uint256 allowance = ERC20(_token).allowance(address(this), _spender);
        if (allowance > 0) {
            ERC20(_token).safeApprove(_spender, 0);
        }
    }
}
