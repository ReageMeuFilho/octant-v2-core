// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @title ISubsidyPool (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy subsidy pool interface
 * @dev No longer actively used - retained for historical reference
 */
interface ISubsidyPool {
    function deposit(uint256 _amount) external; // Only PpfGlmTransformer
    function claimUserEntitlement(address _user, bytes memory _data) external;
    function getUserEntitlement(
        address _user,
        uint256 _period,
        bytes memory _data
    ) external view returns (uint256 amount);
}
