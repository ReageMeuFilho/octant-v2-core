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

contract TestTraderIntegrationETH is BaseTest {
    HelperConfig helperConfig;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    testTemps temps;
    Trader public moduleImplementation;
    Trader public trader;

    address public swapper;

    UniV3Swap public initializer;

    // oracle and swapper initialization
    IUniV3OracleImpl.SetPairDetailParams[] oraclePairDetails;
    OracleParams oracleParams;
    IOracle oracle;
    ISwapperImpl.SetPairScaledOfferFactorParams[] pairScaledOfferFactors;
    ISwapRouter.ExactInputParams[] exactInputParams;
    QuotePair ethGLM;
    QuoteParams[] quoteParams;
    address glmAddress;
    address wethAddress;
    address beneficiary;
    address tokenToBeneficiary;
    uint32 defaultScaledOfferFactor = 99_00_00; // TODO: check if represents 1% MEV reward to searchers?

    function setUp() public {
        _configure(true);
        helperConfig = new HelperConfig();
        (address glmToken, address wethToken,,, address v3router,,, address swapperFactory,, address uniV3Swap) =
            helperConfig.activeNetworkConfig();
        emit log_named_address("glmToken", glmToken);
        emit log_named_address("wethToken", wethToken);

        glmAddress = glmToken;
        wethAddress = wethToken;

        initializer = UniV3Swap(payable(uniV3Swap));
        /* initializer = new UniV3Swap(ISwapperFactory(swapperFactory), ISwapRouter(v3router), WETH(payable(wethToken))); */

        beneficiary = address(this); // FIXME
        emit log_named_address("beneficiary", beneficiary);
        tokenToBeneficiary = glmToken;
        swapper = deploySwapper();
        moduleImplementation = new Trader();

        temps = _testTemps(address(moduleImplementation), abi.encode(ETH, swapper));
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
            tokenToBeneficiary: tokenToBeneficiary,
            oracleParams: oracleParams,
            defaultScaledOfferFactor: defaultScaledOfferFactor,
            pairScaledOfferFactors: pairScaledOfferFactors
        });
    }

    function deploySwapper() public returns (address) {
        helperConfig = new HelperConfig();
        (address glmToken,,,,, address glmPool,, address swapperFactoryAddress, address oracleFactoryAddress,) =
            helperConfig.activeNetworkConfig();
        IOracleFactory oracleFactory = IOracleFactory(oracleFactoryAddress);
        ISwapperFactory swapperFactory = ISwapperFactory(swapperFactoryAddress);
        ISwapperImpl swapperImpl = swapperFactory.swapperImpl();

        address ethAddress = address(0); // address that represents native ETH in Splits Oracle system
        ethGLM = QuotePair({base: ethAddress, quote: glmToken});

        delete oraclePairDetails;
        oraclePairDetails.push(
            IUniV3OracleImpl.SetPairDetailParams({
                quotePair: ethGLM,
                pairDetail: IUniV3OracleImpl.PairDetail({
                    pool: glmPool,
                    period: 0 // no override
                })
            })
        );

        delete pairScaledOfferFactors;
        pairScaledOfferFactors.push(
            ISwapperImpl.SetPairScaledOfferFactorParams({
                quotePair: ethGLM,
                scaledOfferFactor: 98_00_00 // TODO: What this "no discount" refers to exactly? What value should be here?
            })
        );

        IUniV3OracleImpl.InitParams memory initOracleParams = _initOracleParams();
        oracleParams.createOracleParams =
            CreateOracleParams({factory: IOracleFactory(address(oracleFactory)), data: abi.encode(initOracleParams)});

        oracle = oracleFactory.createUniV3Oracle(initOracleParams);
        oracleParams.oracle = oracle;

        emit log_named_address("tokenToBeneficiary", tokenToBeneficiary);

        // setup LibCloneBase
        address impl = address(swapperImpl);
        address clone = address(swapperFactory.createSwapper(_createSwapperParams()));
        return clone;
    }

    function testCheckModuleInitialization() public view {
        assertTrue(trader.owner() == temps.safe);
        assertTrue(trader.swapper() == swapper);
    }

    function testConfiguration() public {
        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, 1 ether, block.number + 102);
        vm.stopPrank();
        assertEq(trader.getSafetyBlocks(), 1);
        assertEq(trader.deadline(), block.number + 102);
        assertEq(trader.remainingBlocks(), 101);
        assertTrue(trader.chance() > 0);
        assertTrue(trader.saleValueLow() == 1 ether);
        assertTrue(trader.saleValueHigh() == 1 ether);
    }

    receive() external payable {}

    function test_sellEth() external {
        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 1 ether;
        vm.deal(address(trader), 2 ether);

        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, fakeBudget, block.number + 101);
        vm.stopPrank();

        uint256 oldBalance = swapper.balance;
        vm.roll(block.number + 100);
        trader.convert(block.number - 2);
        assertEq(trader.spent(), 1 ether);
        assertGt(swapper.balance, oldBalance);

        // mock value of quote to avoid problems with stale oracle on CI
        uint256[] memory unscaledAmountsToBeneficiary = new uint256[](1);
        unscaledAmountsToBeneficiary[0] = 4228914774285437607589;
        vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.getQuoteAmounts.selector), abi.encode(unscaledAmountsToBeneficiary));
        
        uint256 oldGlmBalance = IERC20(glmAddress).balanceOf(address(this));

        address ethAddress = address(0); // address that represents native ETH in Splits Oracle system
        delete exactInputParams;
        exactInputParams.push(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(wethAddress, uint24(10_000), glmAddress),
                recipient: address(initializer),
                deadline: block.timestamp + 100,
                amountIn: uint256(swapper.balance / 2),
                amountOutMinimum: 0
            })
        );

        delete quoteParams;
        quoteParams.push(
            QuoteParams({
                quotePair: ethGLM,
                baseAmount: uint128(swapper.balance / 2),
                data: abi.encode(exactInputParams)
            })
        );
        UniV3Swap.FlashCallbackData memory data =
            UniV3Swap.FlashCallbackData({exactInputParams: exactInputParams, excessRecipient: address(oracle)});
        UniV3Swap.InitFlashParams memory params =
            UniV3Swap.InitFlashParams({quoteParams: quoteParams, flashCallbackData: data});
        initializer.initFlash(ISwapperImpl(swapper), params);

        // check if beneficiary received some GLM
        uint256 newGlmBalance = IERC20(glmAddress).balanceOf(address(this));
        assertGt(newGlmBalance, oldGlmBalance);
    }

    function test_receivesEth() external {
        vm.deal(address(this), 10_000 ether);
        (bool sent,) = payable(address(trader)).call{value: 100 ether}("");
        require(sent, "Failed to send Ether");
    }
}
