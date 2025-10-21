// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @title ICapitalTransformer (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy capital transformer interface
 * @dev No longer actively used - retained for historical reference
 */
interface ICapitalTransformer {
    function transform(uint256 amount) external payable;
}

interface ITransformerObserver {
    function onFundsTransformed(address target, uint256 amount) external payable;
    function onFundsTransformed(address[] calldata targets, uint256[] calldata amounts) external payable;
}
