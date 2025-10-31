// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

interface IOctantRouter {
    function deposit() external payable; // when this contract is destination
    function depositWithGivers(address[] calldata givers, uint256[] calldata amounts) external payable;
    function enqueueTo(address target) external payable;
    function enqueueToWithGivers(
        address[] calldata givers,
        uint256[] calldata amounts,
        address target
    ) external payable;
}
