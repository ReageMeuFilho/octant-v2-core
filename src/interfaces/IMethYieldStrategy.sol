// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

interface IMethYieldStrategy {
    /**
     * @notice Get the last reported exchange rate of mETH to ETH
     * @return The last reported exchange rate (mETH to ETH ratio, scaled by 1e18)
     */
    function getLastReportedExchangeRate() external view returns (uint256);
}
