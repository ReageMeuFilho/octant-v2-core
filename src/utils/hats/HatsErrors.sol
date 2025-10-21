// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

/**
 * @title Hats Protocol Error Definitions
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Custom errors for Hats Protocol integration
 * @dev Used by AbstractHatsManager and DragonHatter for role-based access control
 */

/// @notice Thrown when an invalid address is provided
/// @param message Description of the validation failure
/// @param a The invalid address
error Hats__InvalidAddressFor(string message, address a);

/// @notice Thrown when an invalid hat ID is provided
/// @param hatId The invalid hat identifier
error Hats__InvalidHat(uint256 hatId);

/// @notice Thrown when sender doesn't wear the required hat
/// @param sender Address that attempted the operation
/// @param hatId Required hat identifier
error Hats__DoesNotHaveThisHat(address sender, uint256 hatId);

/// @notice Thrown when attempting to create a hat that already exists
/// @param roleId Role identifier that already exists
error Hats__HatAlreadyExists(bytes32 roleId);

/// @notice Thrown when referencing a non-existent hat
/// @param roleId Role identifier that doesn't exist
error Hats__HatDoesNotExist(bytes32 roleId);

/// @notice Thrown when sender is not admin of the required hat
/// @param sender Address that attempted admin operation
/// @param hatId Hat identifier requiring admin privileges
error Hats__NotAdminOfHat(address sender, uint256 hatId);

/// @notice Thrown when attempting to assign more initial holders than hat's max supply
/// @param initialHolders Number of initial holders requested
/// @param maxSupply Maximum supply for the hat
error Hats__TooManyInitialHolders(uint256 initialHolders, uint256 maxSupply);
