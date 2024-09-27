// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @author  .
 * @title   Octant Rewards Calculator
 * @dev     Draft
 * @notice  Octant rewards calculator implements the logic of dividing the total amount of ETH between different
 * variables
 */
interface IOctantRewardsCalculator {
    function calculateUserRewards(uint256 totalAmount) external view returns (uint256);
    function calculateMatchedFund(uint256 totalAmount) external view returns (uint256);
    function calculatePfpFund(uint256 totalAmount) external view returns (uint256);
    function calculateCommunityFund(uint256 totalAmount) external view returns (uint256);
    function calculateOperationalCosts(uint256 totalAmount) external view returns (uint256);
    function calculateIncreasedStaking(uint256 totalAmount) external view returns (uint256);
}
