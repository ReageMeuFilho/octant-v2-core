// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

/**
 * @notice Interface for accountant that charges fees and can give refunds.
 */
interface IAccountant {
    function report(address strategy, uint256 gain, uint256 loss) external returns (uint256, uint256);
}
