// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

// Mock for deposit limit module
contract MockDepositLimitModule {
    function availableDepositLimit(address) external pure returns (uint256) {
        return 1e18;
    }
}
