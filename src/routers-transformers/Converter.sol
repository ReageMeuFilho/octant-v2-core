/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.23;

contract Converter {

    uint256 public constant blocksADay = 7200;

    /// @notice Chance is probability normalized to uint256.max instead to 1
    uint256 public chance;

    /// @notice How much ETH can be spend per day on average (upper bound)
    uint256 public spendADay;

    /// @notice Spent ETH since startingBlock
    uint256 public spent = 0;

    uint256 public startingBlock = block.number;

    /// @notice Lowest allowed size of a sale.
    uint256 public saleValueLow;

    /// @notice Highest allowed size of a sale.
    /// @dev Technically, this value minus one wei.
    uint256 public saleValueHigh;

    /// @notice Heights at which `buy()` can be executed is decided by `block.prevrandao` value.
    ///         If you see `Converter__WrongPrevrandao()` error, retry in the next block.
    ///         Note, you don't need to pay for gas to learn if tx will apply!
    error Converter__WrongPrevrandao();

    /// @notice This error indicates that contract has spent more ETH than allowed.
    ///         Retry tx in the next block.
    error Converter__SpendingTooMuch();

    /// @notice This one indicates software error. Should never happen.
    error Converter__SoftwareError();

    constructor(uint256 chance_, uint256 spendADay_, uint256 low_, uint256 high_) {
        chance = chance_;
        spendADay = spendADay_;
        saleValueLow = low_;
        saleValueHigh = high_;
    }

    function buy() public {
        uint256 rand = getRandomNumber();
        if (rand > chance) revert Converter__WrongPrevrandao();
        if (spent > (block.number - startingBlock) * (spendADay / blocksADay)) revert Converter__SpendingTooMuch();

        uint256 saleValue = getUniformInRange(saleValueLow, saleValueHigh, rand);
        if (saleValue > saleValueHigh) revert Converter__SoftwareError();

        // TODO: this is a placeholder. ETH will be sold for GLM here.
        payable(address(0x0)).transfer(saleValue);
        spent = spent + saleValue;
    }

    /// @dev FIXME. Testing helper function. Rethink how such admin should be performed.
    function setSpendADay(uint256 chance_, uint256 spendADay_, uint256 low_, uint256 high_) public {
        chance = chance_;
        spendADay = spendADay_;
        startingBlock = block.number;
        spent = 0;
        saleValueLow = low_;
        saleValueHigh = high_;
    }

    // TODO: to save some gas, consider inlining or making this private.
    function getRandomNumber() public view returns (uint256) {
        return randomize(block.prevrandao);
    }

    function randomize(uint256 seed) private pure returns (uint256) {
        return uint256(keccak256(abi.encode("Octant", seed)));
    }

    /// @dev This function returns random value distributed uniformly in range [low, high).
    ///      Note, some values will not be chosen because of precision compromise.
    ///      Also, if high > 2**200, this function may overflow.
    function getUniformInRange(uint256 low, uint256 high, uint256 seed) public pure returns (uint256) {
        return low + ((high - low) * (randomize(seed) >> 200) / 2**(256-200));
    }
}
