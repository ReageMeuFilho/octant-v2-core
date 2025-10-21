// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @title IOctantForwarder (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy forwarder interface
 * @dev No longer actively used - retained for historical reference
 */
interface IOctantForwarder {
    function forward() external payable;
    function forwardTo(address target) external payable;
    function forwardToWithGivers(
        address[] calldata givers,
        uint256[] calldata amounts,
        address target
    ) external payable;
}
