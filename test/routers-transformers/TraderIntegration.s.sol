// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../Base.t.sol";
import "src/routers-transformers/Trader.sol";
import {HelperConfig} from "script/helpers/HelperConfig.s.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CreateOracleParams, IOracleFactory, IOracle, OracleParams} from "../../src/vendor/0xSplits/OracleParams.sol";
import {QuotePair, QuoteParams} from "../../src/vendor/0xSplits/LibQuotes.sol";
import {IUniV3OracleImpl} from "../../src/vendor/0xSplits/IUniV3OracleImpl.sol";
import {ISwapperImpl} from "../../src/vendor/0xSplits/SwapperImpl.sol";
import {ISwapperFactory} from "../../src/vendor/0xSplits/ISwapperFactory.sol";
import {UniV3Swap} from "../../src/vendor/0xSplits/UniV3Swap.sol";
import {ISwapRouter} from "../../src/vendor/uniswap/ISwapRouter.sol";
import {WETH} from "solady/src/tokens/WETH.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract TestTraderIntegrationETH is BaseTest {
    HelperConfig helperConfig;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    testTemps temps;
    Trader public moduleImplementation;
    Trader public trader;
    address public glmAddress;

    address public swapper;

    UniV3Swap public initializer;

    // oracle and swapper initialization
    IUniV3OracleImpl.SetPairDetailParams[] oraclePairDetails;
    OracleParams oracleParams;
    IOracle oracle;
    ISwapperImpl.SetPairScaledOfferFactorParams[] pairScaledOfferFactors;
    ISwapRouter.ExactInputParams[] exactInputParams;
    QuotePair fromTo;
    QuoteParams[] quoteParams;
    address baseAddress;
    address quoteAddress;
    address wethAddress;
    address public beneficiary;
    uint32 defaultScaledOfferFactor = 99_00_00; // TODO: check if represents 1% MEV reward to searchers?

    function setUp() public {
        _configure(true, "eth");
        helperConfig = new HelperConfig(true);
        (address glmToken, address wethToken,,,,,,,, address uniV3Swap) = helperConfig.activeNetworkConfig();

        glmAddress = glmToken;

        wethAddress = wethToken;
        beneficiary = address(this); // FIXME
        initializer = UniV3Swap(payable(uniV3Swap));
    }

    function configureTrader(address _base, address _quote) public {
        baseAddress = _base;
        quoteAddress = _quote;
        swapper = deploySwapper();

        moduleImplementation = new Trader();
        temps = _testTemps(
            address(moduleImplementation),
            abi.encode(baseAddress, quoteAddress, wethAddress, beneficiary, swapper, address(initializer), oracle)
        );
        trader = Trader(payable(temps.module));
    }

    function _initOracleParams() internal view returns (IUniV3OracleImpl.InitParams memory) {
        return IUniV3OracleImpl.InitParams({
            owner: temps.safe,
            paused: false,
            defaultPeriod: 30 minutes,
            pairDetails: oraclePairDetails
        });
    }

    function _createSwapperParams() internal view returns (ISwapperFactory.CreateSwapperParams memory) {
        return ISwapperFactory.CreateSwapperParams({
            owner: temps.safe,
            paused: false,
            beneficiary: beneficiary,
            tokenToBeneficiary: splitsEthWrapper(quoteAddress),
            oracleParams: oracleParams,
            defaultScaledOfferFactor: defaultScaledOfferFactor,
            pairScaledOfferFactors: pairScaledOfferFactors
        });
    }

    function deploySwapper() public returns (address) {
        helperConfig = new HelperConfig(true);
        (,,,,, address glmPool,, address swapperFactoryAddress, address oracleFactoryAddress,) =
            helperConfig.activeNetworkConfig();
        IOracleFactory oracleFactory = IOracleFactory(oracleFactoryAddress);
        ISwapperFactory swapperFactory = ISwapperFactory(swapperFactoryAddress);

        fromTo = QuotePair({base: splitsEthWrapper(baseAddress), quote: splitsEthWrapper(quoteAddress)});

        delete oraclePairDetails;
        oraclePairDetails.push(
            IUniV3OracleImpl.SetPairDetailParams({
                quotePair: fromTo,
                pairDetail: IUniV3OracleImpl.PairDetail({
                    pool: glmPool, //FIXME
                    period: 0 // no override
                })
            })
        );

        delete pairScaledOfferFactors;
        pairScaledOfferFactors.push(
            ISwapperImpl.SetPairScaledOfferFactorParams({
                quotePair: fromTo,
                scaledOfferFactor: 98_00_00 // TODO: What this "no discount" refers to exactly? What value should be here?
            })
        );

        IUniV3OracleImpl.InitParams memory initOracleParams = _initOracleParams();
        oracleParams.createOracleParams =
            CreateOracleParams({factory: IOracleFactory(address(oracleFactory)), data: abi.encode(initOracleParams)});

        oracle = oracleFactory.createUniV3Oracle(initOracleParams);
        oracleParams.oracle = oracle;

        // setup LibCloneBase
        address clone = address(swapperFactory.createSwapper(_createSwapperParams()));
        return clone;
    }

    function uniEthWrapper(address token) private view returns (address) {
        if (token == ETH) return wethAddress;
        else return token;
    }

    function splitsEthWrapper(address token) private pure returns (address) {
        if (token == ETH) return address(0x0);
        else return token;
    }

    receive() external payable {}

    function testCheckModuleInitialization() public {
        configureTrader(ETH, glmAddress);
        assertTrue(trader.owner() == temps.safe);
        assertTrue(trader.swapper() == swapper);
    }

    function test_transform_eth_to_glm() external {
        configureTrader(ETH, glmAddress);
        assert(address(trader).balance == 0);
        assert(IERC20(quoteAddress).balanceOf(trader.beneficiary()) == 0);
        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 1 ether;

        vm.startPrank(temps.safe);
        trader.configurePeriod(block.number, 101);
        trader.setSpending(0.5 ether, 1.5 ether, fakeBudget);
        vm.stopPrank();

        vm.roll(block.number + 100);
        uint256 saleValue = trader.findSaleValue(1.5 ether);
        assert(saleValue > 0);

        // mock value of quote to avoid problems with stale oracle on CI
        uint256[] memory unscaledAmountsToBeneficiary = new uint256[](1);
        unscaledAmountsToBeneficiary[0] = 4228914774285437607589;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IOracle.getQuoteAmounts.selector),
            abi.encode(unscaledAmountsToBeneficiary)
        );

        uint256 amountToBeneficiary = trader.transform{value: saleValue}(trader.base(), trader.quote(), saleValue);

        assert(IERC20(quoteAddress).balanceOf(trader.beneficiary()) > 0);
        assert(IERC20(quoteAddress).balanceOf(trader.beneficiary()) == amountToBeneficiary);
        emit log_named_uint("GLM price on Trader.transform(...)", amountToBeneficiary / saleValue);
    }

    function test_convert_eth_to_glm() external {
        configureTrader(ETH, glmAddress);

        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 1 ether;
        vm.deal(address(trader), 2 ether);

        vm.startPrank(temps.safe);
        trader.configurePeriod(block.number, 101);
        trader.setSpending(1 ether, 1 ether, fakeBudget);
        vm.stopPrank();

        uint256 oldBalance = swapper.balance;
        vm.roll(block.number + 100);
        trader.convert(block.number - 2);
        assertEq(trader.spent(), 1 ether);
        assertGt(swapper.balance, oldBalance);

        // mock value of quote to avoid problems with stale oracle on CI
        uint256[] memory unscaledAmountsToBeneficiary = new uint256[](1);
        unscaledAmountsToBeneficiary[0] = 4228914774285437607589;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IOracle.getQuoteAmounts.selector),
            abi.encode(unscaledAmountsToBeneficiary)
        );

        uint256 oldGlmBalance = IERC20(quoteAddress).balanceOf(address(this));

        // now, do the actual swap

        delete exactInputParams;
        exactInputParams.push(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(uniEthWrapper(baseAddress), uint24(10_000), uniEthWrapper(quoteAddress)),
                recipient: address(initializer),
                deadline: block.timestamp + 100,
                amountIn: uint256(swapper.balance),
                amountOutMinimum: 0
            })
        );

        delete quoteParams;
        quoteParams.push(
            QuoteParams({quotePair: fromTo, baseAmount: uint128(swapper.balance), data: abi.encode(exactInputParams)})
        );
        UniV3Swap.FlashCallbackData memory data =
            UniV3Swap.FlashCallbackData({exactInputParams: exactInputParams, excessRecipient: address(oracle)});
        UniV3Swap.InitFlashParams memory params =
            UniV3Swap.InitFlashParams({quoteParams: quoteParams, flashCallbackData: data});
        initializer.initFlash(ISwapperImpl(swapper), params);

        // check if beneficiary received some quote token
        uint256 newGlmBalance = IERC20(quoteAddress).balanceOf(address(this));
        assertGt(newGlmBalance, oldGlmBalance);

        emit log_named_uint("oldGlmBalance", oldGlmBalance);
        emit log_named_uint("newGlmBalance", newGlmBalance);
        emit log_named_int("glm delta", int256(newGlmBalance) - int256(oldGlmBalance));
    }

    function test_receivesEth() external {
        vm.deal(address(this), 10_000 ether);
        (bool sent,) = payable(address(trader)).call{value: 100 ether}("");
        require(sent, "Failed to send Ether");
    }

    function test_transform_wrong_base() external {
        configureTrader(glmAddress, ETH);

        // check if trader will reject unexpected ETH
        vm.expectRevert(Trader.Trader__ImpossibleConfiguration.selector);
        trader.transform(address(token), glmAddress, 10 ether);
    }

    function test_transform_wrong_quote() external {
        configureTrader(glmAddress, ETH);

        // check if trader will reject unexpected ETH
        vm.expectRevert(Trader.Trader__ImpossibleConfiguration.selector);
        trader.transform(glmAddress, address(token), 10 ether);
    }

    function test_transform_wrong_eth_value() external {
        configureTrader(ETH, glmAddress);
        assert(address(trader).balance == 0);
        vm.expectRevert(Trader.Trader__ImpossibleConfiguration.selector);
        trader.transform{value: 1 ether}(ETH, glmAddress, 2 ether);
    }

    function test_transform_unexpected_value() external {
        configureTrader(glmAddress, ETH);

        // check if trader will reject unexpected ETH
        vm.expectRevert(Trader.Trader__UnexpectedETH.selector);
        trader.transform{value: 1 ether}(glmAddress, ETH, 10 ether);
    }

    function test_transform_glm_to_eth() external {
        configureTrader(glmAddress, ETH);
        uint256 initialETHBalance = address(this).balance;
        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 50 ether;
        deal(glmAddress, address(this), fakeBudget, false);
        ERC20(glmAddress).approve(address(trader), fakeBudget);

        vm.startPrank(temps.safe);
        trader.configurePeriod(block.number, 101);
        trader.setSpending(5 ether, 15 ether, fakeBudget);
        vm.stopPrank();

        vm.roll(block.number + 100);
        uint256 saleValue = trader.findSaleValue(15 ether);
        assert(saleValue > 0);

        // mock value of quote to avoid problems with stale oracle on CI
        uint256[] memory unscaledAmountsToBeneficiary = new uint256[](1);
        unscaledAmountsToBeneficiary[0] = FixedPointMathLib.divWadUp(1, 4228914774285437607589);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IOracle.getQuoteAmounts.selector),
            abi.encode(unscaledAmountsToBeneficiary)
        );

        // do actual attempt to convert ERC20 to ETH
        uint256 amountToBeneficiary = trader.transform(glmAddress, ETH, saleValue);

        assert(address(this).balance > initialETHBalance);
        assert(address(this).balance == initialETHBalance + amountToBeneficiary);
        emit log_named_uint("ETH (in GLM) price on Trader.transform(...)", saleValue / amountToBeneficiary);
    }
}
