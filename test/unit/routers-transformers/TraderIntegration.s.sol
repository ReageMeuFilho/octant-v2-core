// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import "src/routers-transformers/Trader.sol";
import {HelperConfig} from "script/helpers/HelperConfig.s.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CreateOracleParams, IOracleFactory, IOracle, OracleParams} from "src/vendor/0xSplits/OracleParams.sol";
import {QuotePair, QuoteParams} from "src/vendor/0xSplits/LibQuotes.sol";
import {IUniV3OracleImpl} from "src/vendor/0xSplits/IUniV3OracleImpl.sol";
import {ISwapperImpl} from "src/vendor/0xSplits/SwapperImpl.sol";
import {ISwapperFactory} from "src/vendor/0xSplits/ISwapperFactory.sol";
import {UniV3Swap} from "src/vendor/0xSplits/UniV3Swap.sol";
import {ISwapRouter} from "src/vendor/uniswap/ISwapRouter.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract TestTraderIntegrationETH is Test, TestPlus {
    MockERC20 public token;
    uint256 fork;
    string TEST_RPC_URL;

    HelperConfig helperConfig;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public owner;
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
        owner = makeAddr("owner");
        vm.label(owner, "owner");
        beneficiary = makeAddr("beneficiary");
        vm.label(beneficiary, "beneficiary");
        token = new MockERC20();
        token.mint(owner, 100 ether);

        TEST_RPC_URL = vm.envString("TEST_RPC_URL");
        fork = vm.createFork(TEST_RPC_URL);
        vm.selectFork(fork);

        helperConfig = new HelperConfig(true);
        (address glmToken, address wethToken,,,,,,, address uniV3Swap,) = helperConfig.activeNetworkConfig();

        glmAddress = glmToken;

        wethAddress = wethToken;
        initializer = UniV3Swap(payable(uniV3Swap));
    }

    function configureTrader(string memory poolName) public {
        (baseAddress, quoteAddress,) = helperConfig.poolByName(poolName);
        swapper = deploySwapper(poolName);

        trader = new Trader(
            abi.encode(
                owner, baseAddress, quoteAddress, wethAddress, beneficiary, swapper, address(initializer), oracle
            )
        );
        vm.label(address(trader), "Trader");
    }

    function _initOracleParams() internal view returns (IUniV3OracleImpl.InitParams memory) {
        return IUniV3OracleImpl.InitParams({
            owner: owner,
            paused: false,
            defaultPeriod: 30 minutes,
            pairDetails: oraclePairDetails
        });
    }

    function _createSwapperParams() internal view returns (ISwapperFactory.CreateSwapperParams memory) {
        return ISwapperFactory.CreateSwapperParams({
            owner: owner,
            paused: false,
            beneficiary: beneficiary,
            tokenToBeneficiary: splitsEthWrapper(quoteAddress),
            oracleParams: oracleParams,
            defaultScaledOfferFactor: defaultScaledOfferFactor,
            pairScaledOfferFactors: pairScaledOfferFactors
        });
    }

    function deploySwapper(string memory poolName) public returns (address) {
        helperConfig = new HelperConfig(true);
        (,,,,, , address swapperFactoryAddress, address oracleFactoryAddress,,) =
            helperConfig.activeNetworkConfig();
        (address _base, address _quote, uint24 _fee) = helperConfig.poolByName(poolName);
        address poolAddress = helperConfig.getPoolAddress(_base, _quote, _fee);

        IOracleFactory oracleFactory = IOracleFactory(oracleFactoryAddress);
        ISwapperFactory swapperFactory = ISwapperFactory(swapperFactoryAddress);

        fromTo = QuotePair({base: splitsEthWrapper(_base), quote: splitsEthWrapper(_quote)});

        delete oraclePairDetails;
        oraclePairDetails.push(
            IUniV3OracleImpl.SetPairDetailParams({
                quotePair: fromTo,
                pairDetail: IUniV3OracleImpl.PairDetail({
                    pool: poolAddress,
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
        oracleParams.createOracleParams = CreateOracleParams({
            factory: IOracleFactory(address(oracleFactory)),
            data: abi.encode(initOracleParams)
        });

        oracle = oracleFactory.createUniV3Oracle(initOracleParams);
        oracleParams.oracle = oracle;

        // setup LibCloneBase
        address clone = address(swapperFactory.createSwapper(_createSwapperParams()));
        vm.label(clone, "Swapper");
        return clone;
    }

    function uniEthWrapper(address _token) private view returns (address) {
        if (_token == ETH) return wethAddress;
        else return _token;
    }

    function splitsEthWrapper(address _token) private pure returns (address) {
        if (_token == ETH) return address(0x0);
        else return _token;
    }

    receive() external payable {}

    function test_TraderInit() public {
        configureTrader("ETHGLM");
        assertTrue(trader.owner() == owner);
        assertTrue(trader.swapper() == swapper);
    }

    function test_transform_eth_to_glm() external {
        configureTrader("ETHGLM");
        assert(address(trader).balance == 0);
        assert(IERC20(quoteAddress).balanceOf(trader.beneficiary()) == 0);
        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 1 ether;

        vm.startPrank(owner);
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

        uint256 amountToBeneficiary = trader.transform{ value: saleValue }(trader.base(), trader.quote(), saleValue);

        assert(IERC20(quoteAddress).balanceOf(trader.beneficiary()) > 0);
        assert(IERC20(quoteAddress).balanceOf(trader.beneficiary()) == amountToBeneficiary);
        emit log_named_uint("GLM price on Trader.transform(...)", amountToBeneficiary / saleValue);
    }

    function test_convert_eth_to_glm() external {
        configureTrader("ETHGLM");

        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 1 ether;
        vm.deal(address(trader), 2 ether);

        vm.startPrank(owner);
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

        uint256 oldGlmBalance = IERC20(quoteAddress).balanceOf(beneficiary);

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
            QuoteParams({ quotePair: fromTo, baseAmount: uint128(swapper.balance), data: abi.encode(exactInputParams) })
        );
        UniV3Swap.FlashCallbackData memory data = UniV3Swap.FlashCallbackData({
            exactInputParams: exactInputParams,
            excessRecipient: address(oracle)
        });
        UniV3Swap.InitFlashParams memory params = UniV3Swap.InitFlashParams({
            quoteParams: quoteParams,
            flashCallbackData: data
        });
        initializer.initFlash(ISwapperImpl(swapper), params);

        // check if beneficiary received some quote token
        uint256 newGlmBalance = IERC20(quoteAddress).balanceOf(beneficiary);
        assertGt(newGlmBalance, oldGlmBalance);

        emit log_named_uint("oldGlmBalance", oldGlmBalance);
        emit log_named_uint("newGlmBalance", newGlmBalance);
        emit log_named_int("glm delta", int256(newGlmBalance) - int256(oldGlmBalance));
    }

    function test_receivesEth() external {
        vm.deal(address(this), 10_000 ether);
        (bool sent, ) = payable(address(trader)).call{ value: 100 ether }("");
        require(sent, "Failed to send Ether");
    }

    function test_transform_wrong_base() external {
        configureTrader("GLMETH");

        // check if trader will reject unexpected ETH
        vm.expectRevert(Trader.Trader__ImpossibleConfiguration.selector);
        trader.transform(address(token), glmAddress, 10 ether);
    }

    function test_transform_wrong_quote() external {
        configureTrader("GLMETH");

        // check if trader will reject unexpected ETH
        vm.expectRevert(Trader.Trader__ImpossibleConfiguration.selector);
        trader.transform(glmAddress, address(token), 10 ether);
    }

    function test_transform_wrong_eth_value() external {
        configureTrader("ETHGLM");
        assert(address(trader).balance == 0);
        vm.expectRevert(Trader.Trader__ImpossibleConfiguration.selector);
        trader.transform{ value: 1 ether }(ETH, glmAddress, 2 ether);
    }

    function test_transform_unexpected_value() external {
        configureTrader("GLMETH");

        // check if trader will reject unexpected ETH
        vm.expectRevert(Trader.Trader__UnexpectedETH.selector);
        trader.transform{ value: 1 ether }(glmAddress, ETH, 10 ether);
    }

    function test_transform_glm_to_eth() external {
        configureTrader("GLMETH");
        uint256 initialETHBalance = beneficiary.balance;
        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 50 ether;
        deal(glmAddress, address(this), fakeBudget, false);
        ERC20(glmAddress).approve(address(trader), fakeBudget);

        vm.startPrank(owner);
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

        assert(beneficiary.balance > initialETHBalance);
        assert(beneficiary.balance == initialETHBalance + amountToBeneficiary);
        emit log_named_uint("ETH (in GLM) price on Trader.transform(...)", saleValue / amountToBeneficiary);
    }
}
