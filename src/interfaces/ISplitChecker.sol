// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

struct Split {
    address[] recipients; // [r1, r2, ..., opexVault, metapool]
    uint256[] allocations; // should be in SPLIT_PRECISION terms
    uint256 totalAllocations; // should be in SPLIT_PRECISION terms
}

interface ISplitChecker {
    function checkSplit(Split memory split, address opexVault, address metapool) external view;
}
