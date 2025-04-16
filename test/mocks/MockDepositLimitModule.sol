// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

// Mock for deposit limit module
contract MockDepositLimitModule {
    uint256 public defaultDepositLimit = type(uint256).max;
    bool public enforceWhitelist = false;
    mapping(address => bool) public whitelist;
    // user -> limit
    mapping(address => uint256) public userAlreadyDeposited;

    function setDefaultDepositLimit(uint256 newLimit) external {
        defaultDepositLimit = newLimit;
    }

    function setEnforceWhitelist(bool enforce) external {
        enforceWhitelist = enforce;
    }

    function setWhitelist(address account) external {
        whitelist[account] = true;
    }

    function availableDepositLimit(address user) external view returns (uint256) {
        if (user == address(0) || user == msg.sender) {
            return 0;
        }

        if (enforceWhitelist && !whitelist[user]) {
            return 0;
        }

        return defaultDepositLimit;
    }
}
