/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.23;

import "../interfaces/vendored/IQuoter.sol";
import "../interfaces/vendored/ISwapRouter.sol";

import "forge-std/console.sol";

import "solady/src/tokens/ERC20.sol";
import "solady/src/utils/SafeCastLib.sol";

// TODO: this doesn't need to be a separate contract anymore
contract GLMPriceFeed {
    address public GLMAddress = 0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429;
    address public WETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public UniswapV3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    IQuoter quoter = IQuoter(UniswapV3Quoter);

    function getGLMQuota(uint256 amountIn_) public returns (uint256) {
        uint24 fee = 10_000; // 1% pool, expensive one
        uint24 sqrtPriceLimitX96 = 0; // TODO: check if 0 can be used here
        return quoter.quoteExactInputSingle(WETHAddress, GLMAddress, fee, amountIn_, sqrtPriceLimitX96);
    }
}

contract Converter {

    /// @notice GLM token contract
    address public GlmEth10000Pool = 0x531b6A4b3F962208EA8Ed5268C642c84BB29be0b;
    address public UniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public GLMAddress = 0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429;
    address public WETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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

    ISwapRouter public uniswap = ISwapRouter(UniswapV3Router);
    ERC20 public glm = ERC20(GLMAddress);
    ERC20 public weth = ERC20(WETHAddress);
    GLMPriceFeed public priceFeed = new GLMPriceFeed();

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

        uint256 deadline = block.timestamp + 20;

        // We can't ask for a spot price - it is too easy to manipulate.
        // Instead rely on TWAP oracle price.
        uint256 GLMQuota = priceFeed.getGLMQuota(saleValue);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams(
                                   WETHAddress,
                                   GLMAddress,
                                   10_000, // 1% pool, expensive one
                                   address(this),
                                   deadline,
                                   saleValue,
                                   GLMQuota,
                                   0 // TODO: figure out if 0 is acceptable
            );
        uint256 amountOut = uniswap.exactInputSingle(params);
        assert(GLMQuota <= amountOut);
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

    // TODO: consider making coverter payable and do wrapping inside
    function wrap() public {
        uint selfbalance = address(this).balance;
        // FIXME: fix gas amount
        // FIXME: check results of the call
        payable(address(weth)).call{value: selfbalance, gas: 100_000_000}("");
        uint myWETHBalance = weth.balanceOf(address(this));
        weth.approve(UniswapV3Router, myWETHBalance);
    }
}
