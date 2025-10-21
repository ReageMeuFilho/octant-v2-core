// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

/**
 * @title ITimeTracker (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy time tracking interface
 * @dev No longer actively used - retained for historical reference
 */
interface ITimeTracker {
    function getCurrentAccumulationPeriod() external view returns (uint256 number, uint256 start, uint256 end);
    function getSubsidyAttributionPeriod() external view returns (uint256 number, uint256 start, uint256 end);
    function getSubsidyClaimPeriod() external view returns (uint256 number, uint256 start, uint256 end);
}
