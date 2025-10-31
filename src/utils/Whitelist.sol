// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IWhitelist } from "./IWhitelist.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Whitelist
/// @author [Golem Foundation](https://golem.foundation)
/// @notice A simple whitelist contract that allows for adding and removing addresses from a whitelist
contract Whitelist is IWhitelist, Ownable {
    error IllegalWhitelistOperation(address account, string reason);

    event WhitelistAltered(address indexed account, WhitelistOperation indexed operation);

    error EmptyArray();

    enum WhitelistOperation {
        Add,
        Remove
    }

    mapping(address => bool) public override isWhitelisted;

    constructor() Ownable(msg.sender) {}

    /// @inheritdoc IWhitelist
    function addToWhitelist(address[] memory accounts) external override onlyOwner {
        require(accounts.length > 0, EmptyArray());

        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) {
                revert IllegalWhitelistOperation(accounts[i], "Address zero not allowed.");
            }
            if (isWhitelisted[accounts[i]]) {
                revert IllegalWhitelistOperation(accounts[i], "Address already whitelisted.");
            }
            isWhitelisted[accounts[i]] = true;
            emit WhitelistAltered(accounts[i], WhitelistOperation.Add);
        }
    }

    /// @inheritdoc IWhitelist
    function addToWhitelist(address account) external override onlyOwner {
        if (account == address(0)) {
            revert IllegalWhitelistOperation(account, "Address zero not allowed.");
        }
        if (isWhitelisted[account]) {
            revert IllegalWhitelistOperation(account, "Address already whitelisted.");
        }

        isWhitelisted[account] = true;
        emit WhitelistAltered(account, WhitelistOperation.Add);
    }

    /// @inheritdoc IWhitelist
    function removeFromWhitelist(address[] memory accounts) external override onlyOwner {
        require(accounts.length > 0, EmptyArray());

        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) {
                revert IllegalWhitelistOperation(accounts[i], "Address zero not allowed.");
            }
            if (!isWhitelisted[accounts[i]]) {
                revert IllegalWhitelistOperation(accounts[i], "Address not whitelisted.");
            }
            isWhitelisted[accounts[i]] = false;
            emit WhitelistAltered(accounts[i], WhitelistOperation.Remove);
        }
    }

    /// @inheritdoc IWhitelist
    function removeFromWhitelist(address account) external override onlyOwner {
        if (account == address(0)) {
            revert IllegalWhitelistOperation(account, "Address zero not allowed.");
        }
        if (!isWhitelisted[account]) {
            revert IllegalWhitelistOperation(account, "Address not whitelisted.");
        }
        isWhitelisted[account] = false;
        emit WhitelistAltered(account, WhitelistOperation.Remove);
    }
}
