// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IWhitelist
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Interface for the whitelist contract
interface IWhitelist {
    /// @notice Checks if an account is whitelisted
    /// @param account The address to check
    /// @return True if the account is whitelisted, false otherwise
    function isWhitelisted(address account) external view returns (bool);

    /// @notice Adds a list of accounts to the whitelist
    /// @param accounts The addresses to add to the whitelist
    function addToWhitelist(address[] memory accounts) external;

    /// @notice Adds an account to the whitelist
    /// @param account The address to add to the whitelist
    function addToWhitelist(address account) external;

    /// @notice Removes a list of accounts from the whitelist
    /// @param accounts The addresses to remove from the whitelist
    function removeFromWhitelist(address[] memory accounts) external;

    /// @notice Removes an account from the whitelist
    /// @param account The address to remove from the whitelist
    function removeFromWhitelist(address account) external;
}
