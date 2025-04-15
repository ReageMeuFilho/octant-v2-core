// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWhitelist {
    function isWhitelisted(address account) external view returns (bool);

    function addToWhitelist(address[] memory accounts) external;

    function removeFromWhitelist(address[] memory accounts) external;
}
