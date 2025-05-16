// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IWhitelist } from "./IWhitelist.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Whitelist is IWhitelist, Ownable {
    mapping(address => bool) public override isWhitelisted;

    constructor() Ownable(msg.sender) {}

    function addToWhitelist(address[] memory accounts) external override onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = true;
        }
    }

    function removeFromWhitelist(address[] memory accounts) external override onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = false;
        }
    }
}
