// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

library OctantLib {
    function calculate35PercentMatchingFund(uint256 amount) public pure returns (uint256 matchingFund) {
        // implement finding 35% of the amount
    }

    function calculateRelativeQFMatchingFund(uint256 amount, uint256 indvidualDonations, uint256 budgetConstraint) public pure returns (uint256 matchingFund) {

    }

    function calculateUserRewards(uint256 totalAmount, uint256 lockedRatio) public pure returns (uint256) {
        return totalAmount * lockedRatio;
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
}