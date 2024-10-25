// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface ISplitChecker {
    function checkSplit(Split memory split, address opexVault, address metapool) external;
}
