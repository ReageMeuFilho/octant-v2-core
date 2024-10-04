/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "solady/src/tokens/ERC20.sol";
import "src/routers-transformers/Converter.sol";
import {HelperConfig} from "script/helpers/HelperConfig.s.sol";
import {UniswapLiquidityHelper} from "script/helpers/UniswapLiquidityHelper.s.sol";

contract ConverterWrapper is Test {
    Converter public conv;
    uint256 public blockno = 1;
    uint256 public constr = 0;
    uint256 public budget = 10_000 ether;
    HelperConfig helperConfig = new HelperConfig();

    function setUp() external {
        (address glmToken, address wethToken,,, address router, address pool,) = helperConfig.activeNetworkConfig();
        conv = new Converter(pool, router, glmToken, wethToken);
        mockOracle();
        mockRouter();
        conv.setSpendADay(0, 0, 0.6 ether, 1.4 ether);
        vm.deal(address(conv), budget);
    }

    receive() external payable {}

    function mockRouter() public {
        vm.mockCall(
            address(conv.uniswap()),
            abi.encodeWithSelector(MockOfRouter.exactInputSingle.selector),
            abi.encode(5000 * 10 ** 9)
        );
    }

    function mockOracle() public {
        vm.mockCall(
            address(conv.priceFeed()),
            abi.encodeWithSelector(GLMPriceFeed.getGLMQuota.selector),
            abi.encode(5000 * 10 ** 9)
        );
    }

    // sequential call to this function emulate time
    // progressing and set random values for randao
    function wrapBuy() public returns (bool) {
        vm.roll(blockno);
        blockno = blockno + 1;
        /* emit log_named_uint("blockno", block.number); */
        /* emit log_named_bytes32("blockhash", blockhash(block.number-1)); */
        try conv.buy(block.number - 1) {
            return true;
        } catch (bytes memory) /*lowLevelData*/ {
            return false;
        }
    }

    function test_simpleBuy() external {
        // effectively disable randao check
        uint256 chance = type(uint256).max;
        // effectively disable upper bound check
        uint256 spendADay = 1_000_000_000_000 ether;
        conv.setSpendADay(chance, spendADay, 1 ether, 1 ether);
        vm.roll(block.number + 100);
        conv.buy(block.number - 2);
        assertEq(conv.spent(), 1 ether);
    }

    function test_receivesEth() external {
        (bool sent,) = payable(address(conv)).call{value: 100000}("");
        require(sent, "Failed to send Ether");
    }

    function test_wrapBuyBoundedWithRange() external {
        uint256 chance = type(uint256).max / uint256(4000); // corresponds to 0.00025 chance
        uint256 spendADay = 1 ether;
        conv.setSpendADay(chance, spendADay, 0.6 ether, 1.4 ether);
        uint256 blocks = 100_000;
        for (uint256 i = 0; i < blocks; i++) {
            wrapBuy();
        }

        // check if spending above target minus two buys
        assertLt(((blocks * 1 ether) / conv.blocksADay()) - 2 ether, conv.spent());

        // check if spending below target plus one buy
        assertLt(conv.spent(), 1.4 ether + ((blocks * 1 ether) / conv.blocksADay()));
    }

    function test_wrapBuyBounded() external {
        uint256 chance = type(uint256).max / uint256(4000); // corresponds to 0.00025 chance
        uint256 spendADay = 1 ether;
        conv.setSpendADay(chance, spendADay, 1 ether, 1 ether);
        uint256 blocks = 100_000;
        for (uint256 i = 0; i < blocks; i++) {
            wrapBuy();
        }

        // check if spending above target minus two buys
        assertLt(((blocks * 1 ether) / conv.blocksADay()) - 2 ether, conv.spent());

        // check if spending below target plus one buy
        assertLt(conv.spent(), 1 ether + ((blocks * 1 ether) / conv.blocksADay()));
    }

    function test_wrapBuyUnbounded() external {
        uint256 chance = type(uint256).max / uint256(4000); // corresponds to 0.00025 chance
        uint256 spendADay = 100 ether;
        conv.setSpendADay(chance, spendADay, 1 ether, 1 ether);
        uint256 blocks = 100_000;
        for (uint256 i = 0; i < blocks; i++) {
            wrapBuy();
        }

        // comparing to bounded test, average spending will be significantly higher
        // proving that bounding with `spendADay` works
        assertLt(((blocks * 1.4 ether) / conv.blocksADay()) - 2 ether, conv.spent());
        assertLt(conv.spent(), 2 ether + ((blocks * 1.5 ether) / conv.blocksADay()));
    }

    function test_settingPrevrandao() external {
        uint256 i = 12093812093812;
        bytes32 val = keccak256(abi.encode(bytes32(i)));
        vm.prevrandao(val);
        assert(block.prevrandao == uint256(val));
    }

    function test_division() external pure {
        assertLt(0, type(uint256).max / uint256(4000));
        assertLt(type(uint256).max / uint256(4000), type(uint256).max / uint256(3999));
        uint256 maxdiv4096 = 28269553036454149273332760011886696253239742350009903329945699220681916416;
        assertGt(type(uint256).max / uint256(4095), maxdiv4096);
        assertLt(type(uint256).max / uint256(4097), maxdiv4096);
    }

    function test_getUniformInRange_wei() public view {
        runner_getUniformInRange(0, 256);
    }

    function test_getUniformInRange_ether() public view {
        runner_getUniformInRange(100 ether, 200 ether);
    }

    function test_getUniformInRange_highEthers() public view {
        runner_getUniformInRange(1_000_000 ether, 2_000_000 ether);
    }

    function runner_getUniformInRange(uint256 low, uint256 high) public view {
        uint256 counter = 0;
        uint256 val = 0;
        uint256 min = type(uint256).max;
        uint256 max = type(uint256).min;
        uint256 mid = uint256((high + low) / 2);

        for (uint256 i = 0; i < 100_000; i++) {
            val = conv.getUniformInRange(low, high, i);
            if (val < mid) counter = counter + 1;
            if (val > max) max = val;
            if (val < min) min = val;
        }
        assertLt(49_500, counter); // EV(counter) ~= 50_000
        assertLt(counter, 51_500); // EV(counter) ~= 50_000
        if (high - low < 1000) {
            assertEq(min, low);
            assertEq(max, high - 1);
        }
    }

    function test_getUniformInRange_narrow() public view {
        assertEq(1 ether, conv.getUniformInRange(1 ether, 1 ether, 4));
    }

    function test_blockHashValues() public {
        vm.roll(20);
        for (uint256 i = 1; i < 11; i++) {
            assert(blockhash(block.number - i) != blockhash(block.number - i - 1));
            assert(conv.getRandomNumber(block.number - i) != conv.getRandomNumber(block.number - i - 1));
        }
    }

    function test_futureBlockHashValues() public {
        vm.roll(20);
        assert(blockhash(block.number - 1) != bytes32(0));
        assert(blockhash(block.number) == bytes32(0));
        assert(blockhash(block.number + 1) == bytes32(0));
    }
}

contract MockOfRouter is ISwapRouter {
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut) {}
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {}
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn) {}
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn) {}
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {}
}
