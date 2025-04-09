// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Vault Utilities
 * @notice Utility functions for working with vaults and strategies
 */
library VaultUtils {
    /**
     * @notice Convert from raw amount to token units with decimals
     * @param token The token to get decimals from
     * @param amount The raw amount to convert
     * @return The amount in token units
     */
    function toUnits(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        return amount / (10 ** decimals);
    }

    /**
     * @notice Convert from token units to raw amount
     * @param token The token to get decimals from
     * @param amount The amount in token units to convert
     * @return The raw amount
     */
    function fromUnits(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        return amount * (10 ** decimals);
    }

    /**
     * @notice Convert days to seconds
     * @param daysCount Number of days
     * @return Number of seconds
     */
    function daysToSecs(uint256 daysCount) internal pure returns (uint256) {
        return 60 * 60 * 24 * daysCount;
    }
}
