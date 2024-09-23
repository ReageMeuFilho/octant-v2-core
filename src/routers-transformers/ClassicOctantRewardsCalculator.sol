// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { IOctantRewardsCalculator } from "../interfaces/IOctantRewardsCalculator.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/**
 * @author  .
 * @title   Classic Octant Rewards Calculator
 * @dev     Draft
 * @notice  Contains logic of calculating classic octant rewards
 */
contract ClassicOctantRewardsCalculator is IOctantRewardsCalculator {
    using FixedPointMathLib for uint256;

    uint256 public lockedRatio;

    function calculateUserRewards(uint256 totalAmount) public view returns (uint256) {
        return totalAmount * lockedRatio;
    }

    function calculateMatchedFund(uint256 totalAmount) public view returns (uint256) {
        uint256 totalRewards = calculateTotalRewards(totalAmount);
        uint256 userRewards = calculateUserRewards(totalAmount);
        return totalRewards - userRewards;
    }

    function calculatePfpFund(uint256 /* totalAmount */) public pure returns (uint256) {
        return 0;
    }

    function calculateCommunityFund(uint256 /* totalAmount */) public pure returns (uint256) {
        return 0;
    }

    function calculateOperationalCosts(uint256 totalAmount) public pure returns (uint256) {
        return (totalAmount * 25) / 100;
    }

    function calculateIncreasedStaking(uint256 totalAmount) public view returns (uint256) {
        uint256 totalRewards = calculateTotalRewards(totalAmount);
        return
            totalRewards -
            calculateUserRewards(totalAmount) -
            calculateMatchedFund(totalAmount) -
            calculateOperationalCosts(totalAmount);
    }

    function calculateTotalRewards(uint256 totalAmount) public view returns (uint256) {
        return totalAmount * lockedRatio.sqrt();
    }
}
