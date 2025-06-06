// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

interface IOctantForwarder {
    function forward() external payable;
    function forwardTo(address target) external payable;
    function forwardToWithGivers(
        address[] calldata givers,
        uint256[] calldata amounts,
        address target
    ) external payable;
}
