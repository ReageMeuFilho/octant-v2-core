// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

interface IMethYieldStrategy {
    /**
     * @notice Get the current exchange rate of mETH to ETH
     * @return The current exchange rate (mETH to ETH ratio, scaled by 1e18)
     */
    function getCurrentExchangeRate() external view returns (uint256);
}
