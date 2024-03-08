pragma solidity ^0.8.0;

/* SPDX-License-Identifier: UNLICENSED */
contract Converter {

    uint256 public deployedAt = block.number;
    uint256 public spent = 0;
    uint256 public targetRate;
    uint256 public chance;

    mapping (uint => uint) gasBurner;

    constructor(uint256 chance_, uint256 targetRate_) {
        chance = chance_;
        targetRate = targetRate_;
    }

    modifier randaoGuarded() {
        require(random() < chance, "Are you sure you are a searcher?");
        _;
    }

    modifier underTarget() {
        require(spent < (block.number - deployedAt) * (targetRate / 7400),
               "Can't spend more at this height");
        _;
    }

    function buyGuarded() public randaoGuarded underTarget {
        payable(address(0x0)).transfer(1 ether);
        spent = spent + 1 ether;
    }

    function random() private view returns (uint256) {
        return uint256(keccak256(abi.encode(block.prevrandao)));
    }
}
