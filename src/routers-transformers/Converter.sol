/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.23;

contract Converter {

    uint256 public constant blocksADay = 7200;

    // @notice Chance is probability normalized to uint256.max instead to 1
    uint256 public chance;

    // @notice How much ETH can be spend per day on average (upper bound)
    uint256 public spendADay;

    // @notice Spent ETH since startingBlock
    uint256 public spent = 0;

    uint256 public startingBlock = block.number;

    // @notice Heights at which `buy()` can be executed is decided by `block.prevrandao` value.
    //         If you see `Converter__WrongRandao()` error, retry in the next block.
    //         Note, you don't need to pay for gas to learn if tx will apply!
    error Converter__WrongRandao();

    // @notice This error indicates that contract has spent more ETH than allowed.
    //         Retry tx in the next block.
    error Converter__SpendingTooMuch();

    constructor(uint256 chance_, uint256 spendADay_) {
        chance = chance_;
        spendADay = spendADay_;
    }

    function buy() public {
        if (getRandomNumber() > chance) revert Converter__WrongPrevrandao();
        if (spent > (block.number - startingBlock) * (spendADay / blocksADay)) revert Converter__SpendingTooMuch();

        // TODO: this is a placeholder. ETH will be sold for GLM here.
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

    // TODO: to save some gas, consider inlining or making this private.
    function getRandomNumber() public view returns (uint256) {
        return uint256(keccak256(abi.encode("Octant", block.prevrandao)));
    }
}
