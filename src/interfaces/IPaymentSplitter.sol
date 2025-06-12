// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

interface IPaymentSplitter {
    function recordProfit(uint256 amount) external;

    /**
     * @dev Record loss for the current epoch.
     * @param amount The amount of loss to record.
     * @return The amount of shares that were burned.
     */
    function recordLoss(uint256 amount) external returns (uint256);
}
