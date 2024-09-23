// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @author  .
 * @title   Capital Transformer Interface
 * @dev     .
 * @notice  Capital Transformer implementation is responsible for the logic of transforming a provided
 * amount of capital into another value type, dividing it into a number of sub-flows etc.
 */
interface ICapitalTransformer {
    function transform(uint256 amount) external payable;
}

interface ITransformerObserver {
    function onFundsTransformed(address target, uint256 amount) external payable;
    function onFundsTransformed(address[] calldata targets, uint256[] calldata amounts) external payable;
}
