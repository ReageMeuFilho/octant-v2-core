/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.23;

import "forge-std/console.sol";

import {Ownable} from "@solady/auth/Ownable.sol";
import "solady/src/tokens/ERC20.sol";
import "solady/src/tokens/WETH.sol";
import "solady/src/utils/SafeCastLib.sol";

import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract GLMPriceFeed {
    address public GLMAddress;
    address public WETHAddress;
    address public GlmEth10000Pool;

    constructor(address _poolAddress, address _glm, address _weth) {
        GLMAddress = _glm;
        WETHAddress = _weth;
        GlmEth10000Pool = _poolAddress;
    }

    function getGLMQuota(uint256 amountIn_) public view returns (uint256) {
        (int24 twapTick,) = OracleLibrary.consult(GlmEth10000Pool, 30);
        return OracleLibrary.getQuoteAtTick(twapTick, SafeCastLib.toUint128(amountIn_), WETHAddress, GLMAddress);
    }
}

contract Converter is Ownable {
    event Conversion(uint256 sold, uint256 bought);
    event Status(uint256 ethBalance, uint256 glmBalance);

    /// @notice GLM token contract
    address public GlmEth10000PoolAddress;
    address public UniswapV3RouterAddress;
    address public GLMAddress;
    address public WETHAddress;

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

    /// @notice Height of block hash used as a last source of randomness.
    uint256 public lastHeight;

    ISwapRouter public uniswap;
    ERC20 public glm;
    WETH public weth;
    GLMPriceFeed public priceFeed;

    uint256 public lastBought = 0;
    uint256 public lastQuota = 0;
    uint256 public lastSold = 0;

    /// @notice Heights at which `buy()` can be executed is decided by `block.prevrandao` value.
    ///         If you see `Converter__WrongPrevrandao()` error, retry in the next block.
    ///         Note, you don't need to pay for gas to learn if tx will apply!
    error Converter__WrongPrevrandao();

    /// @notice This error indicates that contract has spent more ETH than allowed.
    ///         Retry tx in the next block.
    error Converter__SpendingTooMuch();

    /// @notice Raised if tx was already performed for this source of randomness.
    error Converter__RandomnessAlreadyUsed();

    /// @notice Unsafe randomness seed.
    error Converter__RandomnessUnsafeSeed();

    /// @notice This one indicates software error. Should never happen.
    error Converter__SoftwareError();

    constructor(address _poolAddress, address _v3Router, address _glm, address _weth) payable {
        GlmEth10000PoolAddress = _poolAddress;
        UniswapV3RouterAddress = _v3Router;
        GLMAddress = _glm;
        WETHAddress = _weth;

        uniswap = ISwapRouter(UniswapV3RouterAddress);
        glm = ERC20(GLMAddress);
        weth = WETH(payable(WETHAddress));
        priceFeed = new GLMPriceFeed(GlmEth10000PoolAddress, GLMAddress, WETHAddress);

        _initializeOwner(msg.sender);
    }

    function test_rand() public view returns (bool) {
        uint256 rand = getRandomNumber(block.number - 1);
        return (rand > chance);
    }

    function test_limit() public view returns (bool) {
        return (spent > (block.number - startingBlock) * (spendADay / blocksADay));
    }

    function buy(uint256 height) public {
        uint256 rand = getRandomNumber(height);
        if (rand > chance) revert Converter__WrongPrevrandao();
        if (spent > (block.number - startingBlock) * (spendADay / blocksADay)) revert Converter__SpendingTooMuch();
        if (lastHeight >= height) revert Converter__RandomnessAlreadyUsed();
        lastHeight = height;

        uint256 saleValue = getUniformInRange(saleValueLow, saleValueHigh, rand);
        if (saleValue > saleValueHigh) revert Converter__SoftwareError();

        // this simulates sending ETH to swapper
        (bool success,) = payable(owner()).call{value: saleValue}("");
        require(success);

        lastSold = saleValue;
        spent = spent + saleValue;
    }

    function price() public view returns (uint256) {
        return priceFeed.getGLMQuota(1 ether);
    }

    function setSpendADay(uint256 chance_, uint256 spendADay_, uint256 low_, uint256 high_) public onlyOwner {
        chance = chance_;
        spendADay = spendADay_;
        startingBlock = block.number;
        spent = 0;
        saleValueLow = low_;
        saleValueHigh = high_;
    }

    function getRandomNumber(uint256 height) public view returns (uint256) {
        uint256 seed = uint256(blockhash(height));
        if (seed == 0) revert Converter__RandomnessUnsafeSeed();
        return randomize(seed);
    }

    function randomize(uint256 seed) private pure returns (uint256) {
        return uint256(keccak256(abi.encode("Octant", seed)));
    }

    /// @dev This function returns random value distributed uniformly in range [low, high).
    ///      Note, some values will not be chosen because of precision compromise.
    ///      Also, if high > 2**200, this function may overflow.
    function getUniformInRange(uint256 low, uint256 high, uint256 seed) public pure returns (uint256) {
        return low + ((high - low) * (randomize(seed) >> 200) / 2 ** (256 - 200));
    }

    receive() external payable {}
}
