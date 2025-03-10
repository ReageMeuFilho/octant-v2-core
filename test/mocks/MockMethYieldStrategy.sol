// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { MethYieldStrategy } from "src/dragons/modules/MethYieldStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMantleStaking } from "src/interfaces/IMantleStaking.sol";
import { IERC4626Payable } from "src/interfaces/IERC4626Payable.sol";

/**
 * @title MockMethYieldStrategy
 * @notice Mock version of MethYieldStrategy for testing
 */
contract MockMethYieldStrategy is MethYieldStrategy {
    // Mock addresses that will be used instead of the hardcoded constants
    address public mockMantleStaking;
    address public mockMethToken;

    // Real addresses (for reference)
    address public constant REAL_MANTLE_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;

    /**
     * @notice Set mock addresses for testing
     * @param _mockMantleStaking Mock address for Mantle staking
     * @param _mockMethToken Mock address for mETH token
     */
    function setMockAddresses(address _mockMantleStaking, address _mockMethToken) external {
        mockMantleStaking = _mockMantleStaking;
        mockMethToken = _mockMethToken;
    }

    /**
     * @dev Override the internal _harvestAndReport function to use our mock tokens
     */
    function _harvestAndReport() internal override returns (uint256) {
        // Get current exchange rate
        uint256 currentExchangeRate = _getCurrentExchangeRate();

        // Get actual mETH balance - use mockMethToken if set
        uint256 mEthBalance;
        if (mockMethToken != address(0)) {
            mEthBalance = IERC20(mockMethToken).balanceOf(address(this));
        } else {
            mEthBalance = asset.balanceOf(address(this));
        }

        // Get current accounting balance (includes previously reported profits)
        uint256 accountingBalance = IERC4626Payable(address(this)).totalAssets();

        // First harvest or zero accounting balance case
        if (lastExchangeRate == 0 || accountingBalance == 0) {
            // Initialize the exchange rate
            lastExchangeRate = currentExchangeRate;
            // Initialize with actual token balance
            return mEthBalance;
        }

        // Calculate the adjusted balance that accounts for value appreciation
        uint256 adjustedBalance;

        if (currentExchangeRate > lastExchangeRate) {
            // Proper economic calculation of profit due to exchange rate appreciation

            // 1. Calculate the ETH value at current and previous rates
            uint256 currentEthValue = (mEthBalance * currentExchangeRate) / 1e18;
            uint256 previousEthValue = (mEthBalance * lastExchangeRate) / 1e18;

            // 2. The profit in ETH terms is the difference
            uint256 profitInEth = currentEthValue - previousEthValue;

            // 3. Convert this profit to mETH at the current exchange rate
            uint256 profitInMEth = (profitInEth * 1e18) / currentExchangeRate;

            // 4. Add this profit to the ACCOUNTING balance (not just the raw token balance)
            adjustedBalance = accountingBalance + profitInMEth;
        } else {
            adjustedBalance = accountingBalance;
        }

        // Update the exchange rate for next time
        lastExchangeRate = currentExchangeRate;

        // Return the adjusted balance which includes the profit
        return adjustedBalance;
    }

    /**
     * @dev Override the internal _getCurrentExchangeRate function to use our mock
     */
    function _getCurrentExchangeRate() internal view override returns (uint256) {
        if (mockMantleStaking != address(0)) {
            // Call our mock contract instead of the real one
            return IMantleStaking(mockMantleStaking).mETHToETH(1e18);
        }
        return MANTLE_STAKING.mETHToETH(1e18);
    }
}
