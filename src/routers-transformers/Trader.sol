// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import { Ownable } from "solady/src/auth/Ownable.sol";
import { SafeCastLib } from "solady/src/utils/SafeCastLib.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { CreateOracleParams, IOracleFactory, IOracle, OracleParams } from "../../src/vendor/0xSplits/OracleParams.sol";
import { QuotePair, QuoteParams } from "../../src/vendor/0xSplits/LibQuotes.sol";
import { OracleParams } from "../vendor/0xSplits/OracleParams.sol";
import { UniV3Swap } from "../../src/vendor/0xSplits/UniV3Swap.sol";

import { ITransformer } from "../interfaces/ITransformer.sol";
import { IUniV3OracleImpl } from "../../src/vendor/0xSplits/IUniV3OracleImpl.sol";
import { ISwapperImpl } from "../../src/vendor/0xSplits/SwapperImpl.sol";
import { ISwapRouter } from "../../src/vendor/uniswap/ISwapRouter.sol";

/// @author .
/// @title Octant Trader
/// @notice Octant Trader is a contract that performs "DCA" in terms of sold token into another token.
/// @dev this contract performs trades in a random times, isolating the deployer from risks of insider trading.
contract Trader is ITransformer, Ownable, Pausable {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                          Constants
    //////////////////////////////////////////////////////////////*/

    uint256 public constant blocksADay = 7200;
    /// @notice Address used to represent native ETH.
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @notice Address of WETH wrapper
    address public wethAddress;
    /// @notice Token to be sold.
    address public base;
    /// @notice Token to be bought.
    /// @dev Please note that contract that deals with quote token is the `swapper`. Here value of `quote` is purely informational.
    address public quote;

    /*//////////////////////////////////////////////////////////////
                          PRIVATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    bytes private uniPath;
    QuotePair private splitsPair;
    IUniV3OracleImpl.SetPairDetailParams[] private oraclePairDetails;
    OracleParams private oracleParams;
    IOracle private oracle;
    ISwapperImpl.SetPairScaledOfferFactorParams[] private pairScaledOfferFactors;
    ISwapRouter.ExactInputParams[] private exactInputParams;
    QuoteParams[] private quoteParams;

    /*//////////////////////////////////////////////////////////////
                          STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Swapper is the address which will handle actual selling.
    address public swapper;
    /// @notice Account that initializes the swapping.
    address public uniV3Swap;
    /// @notice Beneficiary will receive quote token after the sale of base token.
    address public beneficiary;
    /// @notice `budget` needs to be spend before the end of the period (in blocks).
    uint256 public periodLength;
    /// @notice Total token to be spent before deadline.
    uint256 public budget;
    /// @notice Spent token since spentResetBlock.
    uint256 public spent;
    /// @notice Current deadline (defined by periodZero and periodLength).
    uint256 public deadline;
    /// @notice Rules for spending were last updated at this height.
    uint256 public spentResetBlock = block.number;
    /// @notice Block which starts the periods.
    uint256 public periodZero = block.number;
    /// @notice Lowest allowed size of a sale.
    uint256 public saleValueLow;
    /// @notice Highest allowed size of a sale.
    /// @dev Technically, this value minus one wei.
    uint256 public saleValueHigh;
    /// @notice Height of block hash used as a last source of randomness.
    uint256 public lastHeight;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event Traded(uint256 sold, uint256 left);
    event SwapperChanged(address oldSwapper, address newSwapper);
    event SpendingChanged(address base, address quote, uint256 budget, uint256 deadline);

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Configuration parameters are impossible: deadline is in the past.
    error Trader__ImpossibleConfigurationDeadlineInThePast();

    /// @notice Configuration parameters are impossible: saleValueLow can't be zero.
    error Trader__ImpossibleConfigurationSaleValueLowIsZero();

    /// @notice Configuration parameters are impossible: saleValueLow is too low to allow to sale budget before deadline.
    error Trader__ImpossibleConfigurationSaleValueLowIsTooLow();

    /// @notice All of budget is already spent.
    error Trader__BudgetSpent();

    /// @notice Configuration parameters are impossible.
    error Trader__ImpossibleConfiguration();

    /// @notice This one indicates software error. Should never happen.
    error Trader__SoftwareError();

    /*//////////////////////////////////////////////////////////////
      INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @dev Initialize function
    /// @dev owner of this module will the safe multisig that calls setUp function
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public {
        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));
        (
            address _base,
            address _quote,
            address _wethAddress,
            address _beneficiary,
            address _swapper,
            address _uniV3Swap,
            address _oracle
        ) = abi.decode(data, (address, address, address, address, address, address, address));
        _initializeOwner(msg.sender);
        base = _base;
        quote = _quote;
        wethAddress = _wethAddress;
        beneficiary = _beneficiary;
        swapper = _swapper;
        uniV3Swap = _uniV3Swap;
        oracle = IOracle(_oracle);
        splitsPair = QuotePair({ base: splitsEthWrapper(base), quote: splitsEthWrapper(quote) });
        uniPath = abi.encodePacked(uniEthWrapper(base), uint24(10_000), uniEthWrapper(quote));
        transferOwnership(_owner);
    }

    function uniEthWrapper(address token) private view returns (address) {
        if (token == ETH) return wethAddress;
        else return token;
    }

    function splitsEthWrapper(address token) private pure returns (address) {
        if (token == ETH) return address(0x0);
        else return token;
    }

    function callInitFlash(uint256 amount) private returns (uint256) {
        uint256 oldQuoteBalance = IERC20(quote).balanceOf(beneficiary);

        delete exactInputParams;
        exactInputParams.push(
            ISwapRouter.ExactInputParams({
                path: uniPath,
                recipient: address(uniV3Swap),
                deadline: block.timestamp + 60,
                amountIn: amount,
                amountOutMinimum: 0
            })
        );

        delete quoteParams;
        quoteParams.push(
            QuoteParams({ quotePair: splitsPair, baseAmount: uint128(amount), data: abi.encode(exactInputParams) })
        );
        UniV3Swap.FlashCallbackData memory data = UniV3Swap.FlashCallbackData({
            exactInputParams: exactInputParams,
            excessRecipient: address(oracle)
        });
        UniV3Swap.InitFlashParams memory params = UniV3Swap.InitFlashParams({
            quoteParams: quoteParams,
            flashCallbackData: data
        });
        UniV3Swap(payable(uniV3Swap)).initFlash(ISwapperImpl(swapper), params);

        return IERC20(quote).balanceOf(beneficiary) - oldQuoteBalance;
    }

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        if (a > b) return a;
        else return b;
    }

    /// @notice Implements Transformer.trader interface. This function can be used to synchroniously convert one token to other token.
    ///         Please note that amount needs to be carefully chosen (see `findSaleValue(...)`).
    ///         This function will throw if fromToken and toToken are different from base and quote respectively.
    /// @param fromToken needs to be set to value of `base()`.
    /// @param toToken needs to be set to value of `quote()`.
    /// @param amount needs to be set to what `findSaleValue(...)` returns.
    /// @return amount of quote token that will be transferred to beneficiery.
    function transform(address fromToken, address toToken, uint256 amount) external payable returns (uint256) {
        if ((fromToken != base) || (toToken != quote)) revert Trader__ImpossibleConfiguration();
        if (fromToken == ETH) {
            if (msg.value != amount) revert Trader__ImpossibleConfiguration();
        } else {
            IERC20(base).safeTransferFrom(msg.sender, address(this), amount);
        }

        uint256 height;
        uint256 saleValue;
        for (height = max(block.number - 255, lastHeight + 1); height < block.number; height++) {
            if (canTrade(height)) {
                saleValue = convert(height);
                break;
            }
        }
        assert(saleValue == amount);

        return callInitFlash(amount);
    }

    /// @notice Transfers funds that are to be converted by to target token by external converter.
    /// @param height that will be used as a source of randomness. One height value can be used only once.
    /// @return amount of base token that is transfered to the swapper.
    function convert(uint256 height) public whenNotPaused returns (uint256) {
        if (deadline < block.number) {
            deadline = nextDeadline();
            spent = 0;
            spentResetBlock = deadline - periodLength;
        }

        if (budget == spent) revert Trader__BudgetSpent();

        // handle randomness
        uint256 rand = getRandomNumber(height);
        uint256 _chance = this.chance();
        if (rand > _chance) revert Trader__WrongHeight();

        // handle overspending
        if (_chance != type(uint256).max && hasOverspent(height)) revert Trader__SpendingTooMuch();

        // don't allow to reuse randomness
        if (lastHeight >= height) revert Trader__RandomnessAlreadyUsed();
        lastHeight = height;

        uint256 balance = address(this).balance;
        if (base != ETH) {
            balance = IERC20(base).balanceOf(address(this));
        }

        uint256 saleValue = getSaleValue(rand, 0);

        spent = spent + saleValue;

        if (base == ETH) {
            (bool success, ) = payable(swapper).call{ value: saleValue }("");
            require(success);
        } else {
            IERC20(base).safeTransfer(swapper, saleValue);
        }

        emit Traded(saleValue, balance - saleValue);
        return saleValue;
    }

    /// @dev Compute next deadline. If cached deadline (`deadline`) differs, `spent` needs to be reset.
    function nextDeadline() public view returns (uint256) {
        uint256 nextPeriodNo = (block.number - periodZero).divUp(periodLength);
        if (nextPeriodNo == (block.number - periodZero) / periodLength) {
            nextPeriodNo = nextPeriodNo + 1;
        }
        return periodZero + (periodLength * nextPeriodNo);
    }

    /// @dev Returns sale value, in a range from [saleValueLow, saleValueHigh).
    ///      Returned value is capped so it doesn't exceed available funds.
    /// @param rand value of randomness for this height
    /// @param transferAmount value will be added to balance before determining sale value
    function getSaleValue(uint256 rand, uint256 transferAmount) private view returns (uint256 saleValue) {
        saleValue = getUniformInRange(saleValueLow, saleValueHigh, rand);
        if (saleValue > saleValueHigh) revert Trader__SoftwareError();

        uint256 balance = address(this).balance;
        if (base != ETH) {
            balance = IERC20(base).balanceOf(address(this));
        }

        if (saleValue > balance + transferAmount) {
            saleValue = balance + transferAmount;
        }
        if (saleValue > budget - spent) {
            saleValue = budget - spent;
        }
    }

    /// @dev Finds a earliest block with unused randomness and returns its sale value. Useful if `transfer(...)` is used instead of `convert(...)`
    /// @param transferAmount value will be added to balance before determining sale value
    function findSaleValue(uint256 transferAmount) public view returns (uint256) {
        for (uint256 height = max(block.number - 255, lastHeight + 1); height < block.number; height++) {
            uint256 rand = getRandomNumber(height);
            if (rand <= chance()) {
                return getSaleValue(rand, transferAmount);
            }
        }
        revert Trader__WrongHeight();
    }

    /// @dev Returns true if trade can be made at passed block height.
    function canTrade(uint256 height) public view returns (bool) {
        uint256 rand = getRandomNumber(height);
        return (rand <= chance());
    }

    /// @dev Returns true if mechanism is overspending. This may happen because randomness. Prevents mechanism from spending too much in a case of attack by a block producer.
    function hasOverspent(uint256 height) public view returns (bool) {
        if (height < spentResetBlock) return true;
        return (spent > (height - spentResetBlock) * (budget / (deadline - spentResetBlock)));
    }

    /// @notice Sets spending limits.
    /// @param low_ is a lower bound of sold token (in wei) for a single trade
    /// @param high_ is a higher bound of sold token (in wei) for a single trade
    /// @param budget_ sets amount of token (in wei) to be sold before deadline block height
    function setSpending(uint256 low_, uint256 high_, uint256 budget_) public onlyOwner {
        lastHeight = block.number;
        saleValueLow = low_;
        saleValueHigh = high_;
        budget = budget_;
        if (spent > budget) spent = budget;
        deadline = nextDeadline();
        _sanityCheck();
    }

    /// @notice Configures spending periods. Budget needs to be fully spend before the end of each period.
    /// @param length_ is length of a period in blocks.
    /// @param height_ is a block height remarking the beginning of a period.
    function configurePeriod(uint256 height_, uint256 length_) public onlyOwner {
        periodZero = height_;
        periodLength = length_;
        deadline = nextDeadline();
        if (budget > 0) {
            _sanityCheck();
        }
    }

    function emergencyStop(bool enable) external onlyOwner {
        if (enable) _pause();
        else _unpause();
    }

    function _sanityCheck() private view {
        if (saleValueLow == 0) revert Trader__ImpossibleConfigurationSaleValueLowIsZero();
        if (getSafetyBlocks() > (deadline - block.number)) revert Trader__ImpossibleConfigurationSaleValueLowIsTooLow();
    }

    /// @notice Set address of the contract that will receive token (base) to be converted to target token (quote).
    /// @param swapper_ address of the contract handling the swapping.
    function setSwapper(address swapper_) external onlyOwner {
        emit SwapperChanged(swapper, swapper_);
        swapper = payable(swapper_);
    }

    /// @notice Returns upper bound of number of blocks enough to sold remaining budget.
    /// @dev Please note that in the worst case each trade amount will be `saleValueLow`.
    function getSafetyBlocks() public view returns (uint256) {
        return (budget - spent).divUp(saleValueLow);
    }

    /// @notice Returns probability of a trade normalized to [0, type(uint256).max] range
    /// @dev Probability of trade changes to make sure that contract will sell all of its budget before the deadline.
    function chance() public view returns (uint256) {
        uint256 safetyBlocks = getSafetyBlocks();
        if (deadline <= block.number + safetyBlocks) return type(uint256).max;
        uint256 avgSale = (saleValueLow + saleValueHigh) / 2;
        uint256 numberOfSales = (budget - spent).divUp(avgSale);
        uint256 blocks_left = remainingBlocks();
        if (blocks_left < numberOfSales) return type(uint256).max;
        else return (type(uint256).max / blocks_left) * numberOfSales;
    }

    /// @notice Number of blocks before deadline where probability of trade < 1
    /// @dev Due to the way this function is used, will return 0 if deadline has passed.
    function remainingBlocks() public view returns (uint256) {
        uint256 safety_blocks = getSafetyBlocks();
        if (block.number + safety_blocks > deadline) return 0;
        return deadline - block.number - safety_blocks;
    }

    /// @return Average amount of token in wei to be sold in 24 hours.
    /// @dev This reads configuration parameters, not current state of swapping process, which may diverge because of randomness.
    function spendADay() external view returns (uint256) {
        return (budget / (deadline - spentResetBlock)) * blocksADay;
    }

    /// @notice Get random value for particular blockchain height.
    /// @param height Height is block height to be used as a source of randomness. Will raise if called for blocks older than 256.
    /// @return a pseudorandom uint256 value in range [0, type(uint256).max]
    /// @dev Sourcing of randomness in this way enables tx inclusion in block which is different from block with randomness source. This prevents waste of gas on failed calls to `convert` even in absence of FlashBots-like infrastructure.
    function getRandomNumber(uint256 height) public view returns (uint256) {
        uint256 seed = uint256(blockhash(height));
        if (seed == 0) revert Trader__RandomnessUnsafeSeed();
        return apply_domain(seed);
    }

    /// @dev Applies a domain separator to the given random seed. This function is intended to namespace the randomness to prevent cross-domain collisions.
    function apply_domain(uint256 seed) public pure returns (uint256) {
        return uint256(keccak256(abi.encode("Octant", seed)));
    }

    /// @dev This function returns random value distributed uniformly in range [low, high).
    ///      Note, some values will not be chosen because of precision compromise.
    ///      Also, if high > 2**200, this function may overflow.
    /// @param low Low range of values returned
    function getUniformInRange(uint256 low, uint256 high, uint256 seed) public pure returns (uint256) {
        return low + (((high - low) * (apply_domain(seed) >> 200)) / 2 ** (256 - 200));
    }

    receive() external payable {}
}
