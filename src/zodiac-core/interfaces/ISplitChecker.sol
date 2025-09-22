// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title Split Checker Interface
 * @author Golem Foundation
 * @notice Validates that a configured split over recipients adheres to required constraints
 *         (e.g., allocation precision, totals, inclusion of OPEX/metapool recipients).
 */
interface ISplitChecker {
    struct Split {
        address[] recipients; // [r1, r2, ..., opexVault, metapool]
        uint256[] allocations; // should be in SPLIT_PRECISION terms
        uint256 totalAllocations; // should be in SPLIT_PRECISION terms
    }

    function checkSplit(Split memory split, address opexVault, address metapool) external view;
}
