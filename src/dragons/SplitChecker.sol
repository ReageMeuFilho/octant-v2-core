// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

struct Split {
    address[] recipients; // [r1, r2, ..., opexVault, metapool]
    uint256[] allocations; // should be in SPLIT_PRECISION terms
    uint256 totalAllocations; // should be in SPLIT_PRECISION terms
}

contract SplitChecker {
    address public goverance;

    uint256 private constant SPLIT_PRECISION = 1e18;
    uint256 public maxOpexSplit;
    uint256 public minMetapoolSplit;

    modifier onlyGovernance() {
        require(msg.sender == goverance, "!Authorized");
        _;
    }

    constructor(address _goverance, uint256 _maxOpexSplit, uint256 _minMetapoolSplit) {
        goverance = _goverance;
        _setMaxOpexSplit(_maxOpexSplit);
        _setMinMetapoolSplit(_minMetapoolSplit);
    }

    function setMinMetapoolSplit(uint256 _minMetapoolSplit) external onlyGovernance {
        _setMinMetapoolSplit(_minMetapoolSplit);
    }

    function _setMinMetapoolSplit(uint256 _minMetapoolSplit) internal {
        require(_minMetapoolSplit <= 1e18);
        // emit MetapoolUpdated(metapool, _metapool);

        minMetapoolSplit = _minMetapoolSplit;
    }

    function setMaxOpexSplit(uint256 _maxOpexSplit) external onlyGovernance {
        _setMaxOpexSplit(_maxOpexSplit);
    }

    function _setMaxOpexSplit(uint256 _maxOpexSplit) internal {
        require(_maxOpexSplit <= 1e18);
        // emit MetapoolUpdated(metapool, _metapool);

        maxOpexSplit = _maxOpexSplit;
    }

    function checkSplit(Split memory split, address opexVault, address metapool) external {
        require(split.recipients.length == split.allocations.length);
        bool flag;
        uint256 calculatedTotalAllocation;
        for(uint256 i = 0; i < split.recipients.length; i++) {
            if(split.recipients[i] == opexVault) {
                require(split.allocations[i] * SPLIT_PRECISION / split.totalAllocations <= maxOpexSplit);
            }
            if(split.recipients[i] == metapool) {
                require(split.allocations[i] * SPLIT_PRECISION / split.totalAllocations > minMetapoolSplit);
                flag = true;
            }
            calculatedTotalAllocation += split.allocations[i];
        }
        if(!flag) revert("Metapool Split undefined");
        require(calculatedTotalAllocation == split.totalAllocations);
    }
}
