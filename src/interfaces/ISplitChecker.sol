// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;


interface ISplitChecker {

    struct Split {
        address[] recipients;
        uint256[] allocations;
        uint256 totalAllocations;
    }
    
    function checkSplit(Split memory split, address opexVault, address metapool) external view;
}
