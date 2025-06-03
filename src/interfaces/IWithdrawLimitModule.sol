// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

/**
 * @notice Interface to control the withdraw limit.
 */
interface IWithdrawLimitModule {
    function availableWithdrawLimit(
        address owner,
        uint256 maxLoss,
        address[] calldata strategies
    ) external view returns (uint256);
}
