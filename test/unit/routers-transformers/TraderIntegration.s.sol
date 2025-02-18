// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { TestPlus } from "lib/solady/test/utils/TestPlus.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import "../../../script/deploy/DeployTrader.sol";
import { HelperConfig } from "../../../script/helpers/HelperConfig.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestTraderIntegrationETH2GLM is Test, TestPlus, DeployTrader {
    HelperConfig config;
    uint256 fork;
    string TEST_RPC_URL;

    function setUp() public {
        owner = makeAddr("owner");
        vm.label(owner, "owner");
        beneficiary = makeAddr("beneficiary");
        vm.label(beneficiary, "beneficiary");

        TEST_RPC_URL = vm.envString("TEST_RPC_URL");
        fork = vm.createFork(TEST_RPC_URL);
        vm.selectFork(fork);

        config = new HelperConfig(true);

        (address glmToken, address wethToken, , , , , , , address uniV3Swap, ) = config.activeNetworkConfig();

        glmAddress = glmToken;

        wethAddress = wethToken;
        initializer = UniV3Swap(payable(uniV3Swap));
        configureTrader(config, "ETHGLM");
    }

    receive() external payable {}

    function test_convert_eth_to_glm() external {
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

    function test_TraderInit() public view {
        assertTrue(trader.owner() == owner);
        assertTrue(trader.swapper() == swapper);
    }

    function test_transform_eth_to_glm() external {
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

    function test_receivesEth() external {
        vm.deal(address(this), 10_000 ether);
        (bool sent, ) = payable(address(trader)).call{ value: 100 ether }("");
        require(sent, "Failed to send Ether");
    }

    function test_transform_wrong_eth_value() external {
        vm.expectRevert(Trader.Trader__ImpossibleConfiguration.selector);
        trader.transform{ value: 1 ether }(ETH, glmAddress, 2 ether);
    }

    function test_findSaleValue_throws() external {
        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 1 ether;

        vm.startPrank(owner);
        trader.configurePeriod(block.number, 5000);
        trader.setSpending(0.5 ether, 1.5 ether, fakeBudget);
        vm.stopPrank();

        vm.roll(block.number + 300);
        vm.expectRevert(Trader.Trader__WrongHeight.selector);
        trader.findSaleValue(1 ether);
    }
}

contract TestTraderIntegrationGLM2ETH is Test, TestPlus, DeployTrader {
    HelperConfig config;
    uint256 fork;
    string TEST_RPC_URL;

    function setUp() public {
        owner = makeAddr("owner");
        vm.label(owner, "owner");
        beneficiary = makeAddr("beneficiary");
        vm.label(beneficiary, "beneficiary");

        TEST_RPC_URL = vm.envString("TEST_RPC_URL");
        fork = vm.createFork(TEST_RPC_URL);
        vm.selectFork(fork);

        config = new HelperConfig(true);

        (address glmToken, address wethToken, , , , , , , address uniV3Swap, ) = config.activeNetworkConfig();

        glmAddress = glmToken;

        wethAddress = wethToken;
        initializer = UniV3Swap(payable(uniV3Swap));
        configureTrader(config, "GLMETH");
    }

    receive() external payable {}

    function test_transform_unexpected_value() external {
        // check if trader will reject unexpected ETH
        vm.expectRevert(Trader.Trader__UnexpectedETH.selector);
        trader.transform{ value: 1 ether }(glmAddress, ETH, 10 ether);
    }

    function test_transform_wrong_base() external {
        MockERC20 otherToken = new MockERC20();
        otherToken.mint(address(trader), 100 ether);

        // check if trader will reject base token different than configured
        vm.expectRevert(Trader.Trader__ImpossibleConfiguration.selector);
        trader.transform(address(otherToken), glmAddress, 10 ether);
    }

    function test_transform_wrong_quote() external {
        MockERC20 otherToken = new MockERC20();

        // check if trader will reject unexpected ETH
        vm.expectRevert(Trader.Trader__ImpossibleConfiguration.selector);
        trader.transform(glmAddress, address(otherToken), 10 ether);
    }

    function test_transform_glm_to_eth() external {
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

contract MisconfiguredSwapperTest is Test, TestPlus, DeployTrader {
    HelperConfig config;
    uint256 fork;
    string TEST_RPC_URL;

    function setUp() public {
        owner = makeAddr("owner");
        vm.label(owner, "owner");
        beneficiary = makeAddr("beneficiary");
        vm.label(beneficiary, "beneficiary");

        TEST_RPC_URL = vm.envString("TEST_RPC_URL");
        fork = vm.createFork(TEST_RPC_URL);
        vm.selectFork(fork);

        config = new HelperConfig(true);

        (address glmToken, address wethToken, , , , , , , address uniV3Swap, ) = config.activeNetworkConfig();

        glmAddress = glmToken;

        wethAddress = wethToken;
        initializer = UniV3Swap(payable(uniV3Swap));
    }

    receive() external payable {}

    function test_reverts_if_swapper_is_misconfigured() external {
        swapper = address(new ContractThatRejectsETH());
        vm.label(swapper, "bad_swapper");
        configureTrader(config, "ETHGLM");

        // effectively disable upper bound check and randomness check
        uint256 fakeBudget = 1 ether;
        vm.deal(address(trader), 2 ether);

        vm.startPrank(owner);
        trader.configurePeriod(block.number, 101);
        trader.setSpending(1 ether, 1 ether, fakeBudget);
        vm.stopPrank();

        vm.roll(block.number + 100);
        // revert without data
        vm.expectRevert();
        trader.convert(block.number - 2);
    }
}

contract ContractThatRejectsETH {
    receive() external payable {
        require(false);
    }
}
