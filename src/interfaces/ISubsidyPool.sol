// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @author  .
 * @title   Subsidy Pool
 * @dev     Draft
 * @notice  Subsidy Pool is a contract that accumulates GLM automatically exchanged by PfpGlmTransformer
 */

interface ISubsidyPool {
    function deposit(uint256 amount) external; // Only PpfGlmTransformer
    function getUserEntitlement(address user) external view returns (uint256 amount);
    function claimUserEntitlement(address user) external;
}