// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

/**
 * @notice Interface to control the deposit limit.
 */
interface IDepositLimitModule {
    function availableDepositLimit(address receiver) external view returns (uint256);
}
