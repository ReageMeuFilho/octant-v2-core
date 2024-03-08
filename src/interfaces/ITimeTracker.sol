// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

interface ITimeTracker {
    function getCurrentPeriod() external view returns (uint256 amount);
    function getDecisionWindowEnd(uint256 _period) external view returns (uint256 end);
}
