// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @author  .
 * @title   Subsidy Pool
 * @dev     Draft
 * @notice  Subsidy Pool is a contract that accumulates GLM automatically exchanged by PfpGlmTransformer
 */
interface ISubsidyPool {
    function deposit(uint256 _amount) external; // Only PpfGlmTransformer
    function getUserEntitlement(
        address _user,
        uint256 _period,
        bytes memory _data
    ) external view returns (uint256 amount);
    function claimUserEntitlement(address _user, bytes memory _data) external;
}
