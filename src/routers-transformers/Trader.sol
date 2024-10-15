/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.23;

import {Module} from "zodiac/core/Module.sol";
import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import "solady/src/utils/SafeCastLib.sol";

/// @author .
/// @title Octant Trader
/// @notice Octant Trader is a contract that performs "DCA" in terms of sold token into another token.
/// @dev This contract performs trades in a random times, attempting to isolate the deployer from risks of insider trading.
contract Trader is Module {
    event Conversion(uint256 sold, uint256 bought);
    event Status(uint256 ethBalance, uint256 glmBalance);

    uint256 public constant blocksADay = 7200;

    /// @notice Chance is probability of a trade occuring at a particular height, normalized to uint256.max instead to 1
    uint256 public chance;

    /// @notice How much ETH can be spend per day on average (upper bound)
    uint256 public spendADay;

    /// @notice Spent ETH since startingBlock
    uint256 public spent = 0;

    /// @notice Rules for spending were last updated at this height.
    uint256 public startingBlock = block.number;

    /// @notice Lowest allowed size of a sale.
    uint256 public saleValueLow;

    /// @notice Highest allowed size of a sale.
    /// @dev Technically, this value minus one wei.
    uint256 public saleValueHigh;

    /// @notice Height of block hash used as a last source of randomness.
    uint256 public lastHeight;

    uint256 public lastSold = 0;

    /// @notice Heights at which `convert()` can be called is decided by randomness.
    ///         If you see `Trader__WrongHeight()` error, retry in the next block.
    ///         Note, you don't need to pay for gas to learn if tx will apply!
    error Trader__WrongHeight();

    /// @notice This error indicates that contract has spent more ETH than allowed.
    ///         Retry tx in the next block.
    error Trader__SpendingTooMuch();

    /// @notice Raised if tx was already performed for this source of randomness (this height).
    error Trader__RandomnessAlreadyUsed();

    /// @notice Unsafe randomness seed.
    error Trader__RandomnessUnsafeSeed();

    /// @notice This one indicates software error. Should never happen.
    error Trader__SoftwareError();

    function setUp(bytes memory initializeParams) public override initializer {
        (address _owner,,, uint256 _chance, uint256 _spendADay, uint256 _low, uint256 _high) =
            abi.decode(initializeParams, (address, bytes32, bytes32, uint256, uint256, uint256, uint256));
        __Ownable_init(msg.sender);
        setSpendADay(_chance, _spendADay, _low, _high);
        transferOwnership(_owner);
    }

    /// @notice Transfers funds that are to be converted by to target token by external converter.
    /// @param height that will be used as a source of randomness. One height value can be used only once.
    function convert(uint256 height) public {
        uint256 rand = getRandomNumber(height);
        if (rand > chance) revert Trader__WrongHeight();
        if (hasOverspent(height)) revert Trader__SpendingTooMuch();
        if (lastHeight >= height) revert Trader__RandomnessAlreadyUsed();
        lastHeight = height;

        uint256 saleValue = getUniformInRange(saleValueLow, saleValueHigh, rand);
        if (saleValue > saleValueHigh) revert Trader__SoftwareError();

        // this simulates sending ETH to swapper
        (bool success,) = payable(owner()).call{value: saleValue}("");
        require(success);

        lastSold = saleValue;
        spent = spent + saleValue;
    }

    function canTrade(uint256 height) public view returns (bool) {
        uint256 rand = getRandomNumber(height);
        return (rand <= chance);
    }

    function hasOverspent(uint256 height) public view returns (bool) {
        if (height < startingBlock) return true;
        return (spent > (height - startingBlock) * (spendADay / blocksADay));
    }

    /// @notice Sets ETH spending limits.
    /// @param chance_ Chance determines how often on average trades can be performed
    /// @param spendADay_ determines how much ETH on average can Trader sell
    /// @param low_ is a lower bound of sold ETH for a single trade
    /// @param high_ is a higher bound of sold ETH for a single trade
    function setSpendADay(uint256 chance_, uint256 spendADay_, uint256 low_, uint256 high_) public onlyOwner {
        chance = chance_;
        spendADay = spendADay_;
        startingBlock = block.number;
        lastHeight = block.number;
        spent = 0;
        saleValueLow = low_;
        saleValueHigh = high_;
    }

    /// @notice Get random value for particular blockchain height.
    /// @param height Height is block height to be used as a source of randomness. Will raise if called for blocks older than 256.
    /// @return a pseudorandom uint256 value in range [0, type(uint256).max]
    function getRandomNumber(uint256 height) public view returns (uint256) {
        uint256 seed = uint256(blockhash(height));
        if (seed == 0) revert Trader__RandomnessUnsafeSeed();
        return randomize(seed);
    }

    function randomize(uint256 seed) private pure returns (uint256) {
        return uint256(keccak256(abi.encode("Octant", seed)));
    }

    /// @dev This function returns random value distributed uniformly in range [low, high).
    ///      Note, some values will not be chosen because of precision compromise.
    ///      Also, if high > 2**200, this function may overflow.
    /// @param low Low range of values returned
    function getUniformInRange(uint256 low, uint256 high, uint256 seed) public pure returns (uint256) {
        return low + ((high - low) * (randomize(seed) >> 200) / 2 ** (256 - 200));
    }

    receive() external payable {}
}
