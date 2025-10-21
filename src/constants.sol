// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// =============================================================================
// Octant Constants
// =============================================================================
// Author: Golem Foundation (https://golem.foundation)
// Security Contact: security@golem.foundation
//
// Global constants used across Octant contracts:
// - NATIVE_TOKEN: Sentinel value representing native ETH (address(0))
// - AccessMode: Enum for access control modes in LinearAllowanceExecutor and RegenStaker

// Sentinel value representing native ETH in token parameters
// Use address(0) to indicate ETH instead of ERC20 token
address constant NATIVE_TOKEN = address(0);

// Access control mode for address set validation
// Used by LinearAllowanceExecutor and RegenStaker for access control
enum AccessMode {
    NONE, // No access control (permissionless)
    ALLOWSET, // Only addresses in allowset are permitted
    BLOCKSET // All addresses except those in blockset are permitted
}
