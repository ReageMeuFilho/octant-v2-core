// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @title IOctantRewardsCalculator (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy rewards calculator interface
 * @dev No longer actively used - retained for historical reference
 */
interface IOctantRewardsCalculator {
    function calculateUserRewards(uint256 totalAmount) external view returns (uint256);
    function calculateMatchedFund(uint256 totalAmount) external view returns (uint256);
    function calculatePfpFund(uint256 totalAmount) external view returns (uint256);
    function calculateCommunityFund(uint256 totalAmount) external view returns (uint256);
    function calculateOperationalCosts(uint256 totalAmount) external view returns (uint256);
    function calculateIncreasedStaking(uint256 totalAmount) external view returns (uint256);
}
