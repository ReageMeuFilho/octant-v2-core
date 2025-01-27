/* SPDX-License-Identifier: GPL-3.0 */

pragma solidity ^0.8.23;

interface IUniswapV3Pool {
    function token0() external returns (address);
    function token1() external returns (address);
    function fee() external returns (uint24);
}
