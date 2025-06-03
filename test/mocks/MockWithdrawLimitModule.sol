// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

contract MockWithdrawLimitModule {
    uint256 public defaultWithdrawLimit = type(uint256).max;

    function setDefaultWithdrawLimit(uint256 newLimit) external {
        defaultWithdrawLimit = newLimit;
    }

    function availableWithdrawLimit(address, uint256, address[] calldata) external view returns (uint256) {
        return defaultWithdrawLimit;
    }
}
