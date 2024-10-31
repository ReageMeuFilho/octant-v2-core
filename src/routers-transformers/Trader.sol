// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {Module} from "zodiac/core/Module.sol";
import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import "solady/src/utils/SafeCastLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OracleParams} from "../vendor/0xSplits/OracleParams.sol";
import "solady/src/utils/FixedPointMathLib.sol";
/* import {ITrader} from "../interfaces/ITrader.sol"; */

/// @author .
/// @title Octant Trader
/// @notice Octant Trader is a contract that performs "DCA" in terms of sold token into another token.
/// @dev This contract performs trades in a random times, attempting to isolate the deployer from risks of insider trading.
contract Trader is Module /* , ITrader */ {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    event Traded(uint256 sold);
    event SwapperChanged(address oldSwapper, address newSwapper);

    uint256 public constant blocksADay = 7200;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // using this address to represent native ETH

    /// @notice Swapper is the address which will handle actual selling.
    address public swapper;

    /// @notice Token to be sold.
    address public token;

    /// @notice Deadline for all of budget to be sold.
    uint256 public deadline = block.number;

    /// @notice Total ETH to be spent before deadline.
    uint256 public budget = 0;

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

    /// @notice Heights at which `convert()` can be called is decided by randomness.
    ///         If you see `Trader__WrongHeight()` error, retry in the next block.
    ///         Note, you don't need to pay for gas to learn if tx will apply!
    error Trader__WrongHeight();

    /// @notice This error indicates that contract has spent more than allowed.
    ///         Retry tx in the next block.
    error Trader__SpendingTooMuch();

    /// @notice Raised if tx was already performed for this source of randomness (this height).
    error Trader__RandomnessAlreadyUsed();

    /// @notice Unsafe randomness seed.
    error Trader__RandomnessUnsafeSeed();

    /// @notice Configuration parameters are impossible.
    error Trader__ImpossibleConfiguration();

    /// @notice This one indicates software error. Should never happen.
    error Trader__SoftwareError();

    function setUp(bytes memory initializeParams) public override initializer {
        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));
        (address _token, address _swapper) = abi.decode(data, (address, address));
        __Ownable_init(msg.sender);
        token = _token;
        swapper = _swapper;
        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);
    }

    /// @notice Transfers funds that are to be converted by to target token by external converter.
    /// @param height that will be used as a source of randomness. One height value can be used only once.
    function convert(uint256 height) external {
        uint256 rand = getRandomNumber(height);
        uint256 _chance = this.chance();
        if (rand > _chance) revert Trader__WrongHeight();
        if (_chance != type(uint256).max && hasOverspent(height)) revert Trader__SpendingTooMuch();
        if (lastHeight >= height) revert Trader__RandomnessAlreadyUsed();
        lastHeight = height;

        uint256 saleValue = getUniformInRange(saleValueLow, saleValueHigh, rand);
        if (saleValue > saleValueHigh) revert Trader__SoftwareError();

        uint256 balance = address(this).balance;
        if (token != ETH) {
            balance = IERC20(token).balanceOf(address(this));
        }

        if (saleValue > balance) {
            saleValue = balance;
        }
        if (saleValue > budget - spent) {
            saleValue = budget - spent;
        }
        if (token == ETH) {
            (bool success,) = payable(swapper).call{value: saleValue}("");
            require(success);
        } else {
            IERC20(token).safeTransfer(swapper, saleValue);
        }

        spent = spent + saleValue;

        emit Traded(saleValue);
    }

    function canTrade(uint256 height) public view returns (bool) {
        uint256 rand = getRandomNumber(height);
        return (rand <= chance());
    }

    function hasOverspent(uint256 height) public view returns (bool) {
        if (height < startingBlock) return true;
        return (spent > (height - startingBlock) * (budget / (deadline - startingBlock)));
    }

    /// @notice Sets spending limits.
    /// @param low_ is a lower bound of sold ETH for a single trade
    /// @param high_ is a higher bound of sold ETH for a single trade
    /// @param budget_ sets amount of ETH (in wei) to be sold before deadline block height
    /// @param deadline_ sets deadline block height
    function setSpendADay(uint256 low_, uint256 high_, uint256 budget_, uint256 deadline_) public onlyOwner {
        startingBlock = block.number;
        lastHeight = block.number;
        spent = 0;
        saleValueLow = low_;
        saleValueHigh = high_;
        deadline = deadline_;
        budget = budget_;
        if (deadline <= block.number) revert Trader__ImpossibleConfiguration();
        if (saleValueLow == 0) revert Trader__ImpossibleConfiguration();
        if (getSafetyBlocks() > (deadline - block.number)) revert Trader__ImpossibleConfiguration();
    }

    function setSwapper(address swapper_) external onlyOwner {
        emit SwapperChanged(swapper, swapper_);
        swapper = payable(swapper_);
    }

    function getSafetyBlocks() public view returns (uint256) {
        return (budget - spent).divUp(saleValueLow);
    }

    /// @return returns probability of a trade normalized to [0, type(uint256).max] range
    function chance() public view returns (uint256) {
        uint256 safetyBlocks = getSafetyBlocks();
        if (deadline - block.number <= safetyBlocks) return type(uint256).max;
        uint256 avgSale = (saleValueLow + saleValueHigh) / 2;
        uint256 numberOfSales = (budget - spent).divUp(avgSale);
        return (type(uint256).max / remainingBlocks()) * numberOfSales;
    }

    /// @return number of blocks before deadline where probability of trade < 1
    function remainingBlocks() public view returns (uint256) {
        uint256 safety_blocks = getSafetyBlocks();
        return deadline - block.number - safety_blocks;
    }

    /// @return average amount of ETH in wei to be sold in 24 hours at average
    function spendADay() external view returns (uint256) {
        return budget / ((deadline - block.number) / blocksADay);
    }

    /// @notice Get random value for particular blockchain height.
    /// @param height Height is block height to be used as a source of randomness. Will raise if called for blocks older than 256.
    /// @return a pseudorandom uint256 value in range [0, type(uint256).max]
    function getRandomNumber(uint256 height) public view returns (uint256) {
        uint256 seed = uint256(blockhash(height));
        if (seed == 0) revert Trader__RandomnessUnsafeSeed();
        return apply_domain(seed);
    }

    function apply_domain(uint256 seed) public pure returns (uint256) {
        return uint256(keccak256(abi.encode("Octant", seed)));
    }

    /// @dev This function returns random value distributed uniformly in range [low, high).
    ///      Note, some values will not be chosen because of precision compromise.
    ///      Also, if high > 2**200, this function may overflow.
    /// @param low Low range of values returned
    function getUniformInRange(uint256 low, uint256 high, uint256 seed) public pure returns (uint256) {
        return low + ((high - low) * (apply_domain(seed) >> 200) / 2 ** (256 - 200));
    }

    receive() external payable {}
}
