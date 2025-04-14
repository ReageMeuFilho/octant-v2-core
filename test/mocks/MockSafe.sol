// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockSafe {
    mapping(address => bool) public modules;

    function enableModule(address module) external {
        modules[module] = true;
    }
}
