// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";

/**
 * @title Vault System Constants
 * @notice Constants used throughout the vault system
 */
library Constants {
    // Time-related constants
    uint256 constant DAY = 86400;
    uint256 constant WEEK = 7 * DAY;
    uint256 constant YEAR = 31_556_952; // same value used in vault

    // System limits
    uint256 constant MAX_INT = type(uint256).max;
    address constant ZERO_ADDRESS = address(0);
    uint256 constant MAX_BPS = 1_000_000_000_000;
    uint256 constant MAX_BPS_ACCOUNTANT = 10_000;

    // Role definitions - implemented as bit flags to mimic Python's IntFlag
    uint256 constant ROLE_ADD_STRATEGY_MANAGER = 1;
    uint256 constant ROLE_REVOKE_STRATEGY_MANAGER = 2;
    uint256 constant ROLE_FORCE_REVOKE_MANAGER = 4;
    uint256 constant ROLE_ACCOUNTANT_MANAGER = 8;
    uint256 constant ROLE_QUEUE_MANAGER = 16;
    uint256 constant ROLE_REPORTING_MANAGER = 32;
    uint256 constant ROLE_DEBT_MANAGER = 64;
    uint256 constant ROLE_MAX_DEBT_MANAGER = 128;
    uint256 constant ROLE_DEPOSIT_LIMIT_MANAGER = 256;
    uint256 constant ROLE_WITHDRAW_LIMIT_MANAGER = 512;
    uint256 constant ROLE_MINIMUM_IDLE_MANAGER = 1024;
    uint256 constant ROLE_PROFIT_UNLOCK_MANAGER = 2048;
    uint256 constant ROLE_DEBT_PURCHASER = 4096;
    uint256 constant ROLE_EMERGENCY_MANAGER = 8192;
    uint256 constant ROLE_ALL = 16383;

    // Strategy change types
    IMultistrategyVault.StrategyChangeType constant STRATEGY_CHANGE_ADDED =
        IMultistrategyVault.StrategyChangeType.ADDED;
    IMultistrategyVault.StrategyChangeType constant STRATEGY_CHANGE_REVOKED =
        IMultistrategyVault.StrategyChangeType.REVOKED;

    // Role status changes
    uint256 constant ROLE_STATUS_OPENED = 1;
    uint256 constant ROLE_STATUS_CLOSED = 2;

    /**
     * @notice Check if a role value contains a specific role
     * @param roleValue The combined role value to check
     * @param role The specific role to check for
     * @return True if the role is included
     */
    function hasRole(uint256 roleValue, uint256 role) internal pure returns (bool) {
        return (roleValue & role) != 0;
    }

    /**
     * @notice Add a role to an existing role value
     * @param currentRoles The current roles value
     * @param roleToAdd The role to add
     * @return The updated roles value
     */
    function addRole(uint256 currentRoles, uint256 roleToAdd) internal pure returns (uint256) {
        return currentRoles | roleToAdd;
    }

    /**
     * @notice Remove a role from an existing role value
     * @param currentRoles The current roles value
     * @param roleToRemove The role to remove
     * @return The updated roles value
     */
    function removeRole(uint256 currentRoles, uint256 roleToRemove) internal pure returns (uint256) {
        return currentRoles & ~roleToRemove;
    }
}
