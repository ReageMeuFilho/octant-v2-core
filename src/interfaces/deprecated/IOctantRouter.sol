// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @title IOctantRouter (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy router interface
 * @dev No longer actively used - retained for historical reference
 */
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
