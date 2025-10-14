// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IAddressSet } from "./IAddressSet.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title AddressSet
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Managed set of addresses using OpenZeppelin's EnumerableSet
/// @dev Provides enumerable address set functionality with owner-only modifications
///      Can be used for allowlists, denylists, or any address collection
contract AddressSet is IAddressSet, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    error IllegalAddressSetOperation(address account, string reason);
    error EmptyArray();

    event AddressSetAltered(address indexed account, AddressSetOperation indexed operation);

    enum AddressSetOperation {
        Add,
        Remove
    }

    EnumerableSet.AddressSet private _addresses;

    constructor() Ownable(msg.sender) {}

    /// @inheritdoc IAddressSet
    function contains(address account) external view override returns (bool) {
        return _addresses.contains(account);
    }

    /// @notice Get all addresses in the set
    /// @return Array of all addresses
    function values() external view returns (address[] memory) {
        return _addresses.values();
    }

    /// @notice Get number of addresses in the set
    /// @return Number of addresses
    function length() external view returns (uint256) {
        return _addresses.length();
    }

    /// @inheritdoc IAddressSet
    function add(address[] memory accounts) external override onlyOwner {
        require(accounts.length > 0, EmptyArray());

        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) {
                revert IllegalAddressSetOperation(accounts[i], "Address zero not allowed.");
            }
            if (!_addresses.add(accounts[i])) {
                revert IllegalAddressSetOperation(accounts[i], "Address already in set.");
            }
            emit AddressSetAltered(accounts[i], AddressSetOperation.Add);
        }
    }

    /// @inheritdoc IAddressSet
    function add(address account) external override onlyOwner {
        if (account == address(0)) {
            revert IllegalAddressSetOperation(account, "Address zero not allowed.");
        }
        if (!_addresses.add(account)) {
            revert IllegalAddressSetOperation(account, "Address already in set.");
        }

        emit AddressSetAltered(account, AddressSetOperation.Add);
    }

    /// @inheritdoc IAddressSet
    function remove(address[] memory accounts) external override onlyOwner {
        require(accounts.length > 0, EmptyArray());

        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) {
                revert IllegalAddressSetOperation(accounts[i], "Address zero not allowed.");
            }
            if (!_addresses.remove(accounts[i])) {
                revert IllegalAddressSetOperation(accounts[i], "Address not in set.");
            }
            emit AddressSetAltered(accounts[i], AddressSetOperation.Remove);
        }
    }

    /// @inheritdoc IAddressSet
    function remove(address account) external override onlyOwner {
        if (account == address(0)) {
            revert IllegalAddressSetOperation(account, "Address zero not allowed.");
        }
        if (!_addresses.remove(account)) {
            revert IllegalAddressSetOperation(account, "Address not in set.");
        }
        emit AddressSetAltered(account, AddressSetOperation.Remove);
    }
}
