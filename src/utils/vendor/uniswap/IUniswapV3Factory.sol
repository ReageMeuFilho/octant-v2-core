// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

/**
 * @title IUniswapV3Factory
 * @author Uniswap Labs
 * @custom:vendor Uniswap V3
 * @notice Minimal interface for Uniswap V3 factory
 */
interface IUniswapV3Factory {
    function getPool(address, address, uint24) external returns (address);
}
