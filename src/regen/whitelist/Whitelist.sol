// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IWhitelist } from "./IWhitelist.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Whitelist
/// @author [Golem Foundation](https://golem.foundation)
/// @notice A simple whitelist contract that allows for adding and removing addresses from a whitelist
contract Whitelist is IWhitelist, Ownable {
    mapping(address => bool) public override isWhitelisted;

    constructor() Ownable(msg.sender) {}

    /// @inheritdoc IWhitelist
    function addToWhitelist(address[] memory accounts) external override onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = true;
        }
    }

    /// @inheritdoc IWhitelist
    function removeFromWhitelist(address[] memory accounts) external override onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = false;
        }
    }
}
