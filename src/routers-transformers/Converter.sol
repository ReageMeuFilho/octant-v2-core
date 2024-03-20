pragma solidity ^0.8.0;

/* SPDX-License-Identifier: UNLICENSED */
contract Converter {

    uint256 public blocksADay = 7200;

    // @notice Chance is probability normalized to uint256.max instead to 1
    uint256 public chance;

    // @notice How much ETH can be spend per day on average (upper bound)
    uint256 public spendADay;

    // @notice Spent ETH since startingBlock
    uint256 public spent = 0;

    uint256 public startingBlock = block.number;

    constructor(uint256 chance_, uint256 spendADay_) {
        chance = chance_;
        spendADay = spendADay_;
    }

    function buy() public {
        require(getRandomNumber() < chance, "Are you sure you are a searcher?");
        require(spent < (block.number - startingBlock) * (spendADay / blocksADay),
                "Can't spend more at this height");
        payable(address(0x0)).transfer(1 ether);
        spent = spent + 1 ether;
    }

    // @dev Testing helper function. Rethink how such admin should be performed.
    function setSpendADay(uint256 chance_, uint256 spendADay_) public {
        chance = chance_;
        spendADay = spendADay_;
        startingBlock = block.number;
        spent = 0;
    }

    function getRandomNumber() public view returns (uint256) {
        return uint256(keccak256(abi.encode("Octant", block.prevrandao)));
    }
}
