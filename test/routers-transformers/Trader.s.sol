// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../Base.t.sol";
import "src/routers-transformers/Trader.sol";
import {HelperConfig} from "script/helpers/HelperConfig.s.sol";

contract TestTraderRandomness is BaseTest {
    uint256 public budget = 10_000 ether;
    HelperConfig helperConfig = new HelperConfig();

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    testTemps temps;
    Trader public moduleImplementation;
    Trader public trader;

    function setUp() public {
        _configure(false);
        moduleImplementation = new Trader();
        temps = _testTemps(address(moduleImplementation), abi.encode(ETH, 0, 0, 0.6 ether, 1.4 ether));
        trader = Trader(payable(temps.module));
        vm.deal(address(trader), budget);
    }

    receive() external payable {}

    // sequential call to this function emulate time progression
    function wrapBuy() public returns (bool) {
        vm.roll(block.number + 1);
        try trader.convert(block.number - 1) {
            return true;
        } catch (bytes memory reason) /*lowLevelData*/ {
            return false;
        }
    }

    function test_receivesEth() external {
        (bool sent,) = payable(address(trader)).call{value: 100000}("");
        require(sent, "Failed to send Ether");
    }

    function test_wrapBuyBounded() external {
        uint256 chance = type(uint256).max / uint256(4000); // corresponds to 0.00025 chance
        uint256 spendADay = 1 ether;

        vm.startPrank(temps.safe);
        trader.setSpendADay(chance, spendADay, 1 ether, 1 ether);
        vm.stopPrank();
        vm.roll(block.number + 10);
        uint256 blocks = 100;
        for (uint256 i = 0; i < blocks; i++) {
            wrapBuy();
        }

        /* check if spending below target plus one buy */
        assertLt(trader.spent(), 1 ether + ((blocks * 1 ether) / trader.blocksADay()));
    }

    function test_wrapBuyBoundedWithRange() external {
        uint256 chance = type(uint256).max / uint256(4000); // corresponds to 0.00025 chance
        uint256 spendADay = 1 ether;
        vm.startPrank(temps.safe);
        trader.setSpendADay(chance, spendADay, 0.6 ether, 1.4 ether);
        vm.stopPrank();
        uint256 blocks = 100_000;
        for (uint256 i = 0; i < blocks; i++) {
            wrapBuy();
        }

        // check if spending above target minus two buys
        assertLt(((blocks * 1 ether) / trader.blocksADay()) - 2 ether, trader.spent());

        // check if spending below target plus one buy
        assertLt(trader.spent(), 1.4 ether + ((blocks * 1 ether) / trader.blocksADay()));
    }

    function test_wrapBuyUnbounded() external {
        uint256 chance = type(uint256).max / uint256(4000); // corresponds to 0.00025 chance
        uint256 spendADay = 100 ether;
        vm.startPrank(temps.safe);
        trader.setSpendADay(chance, spendADay, 1 ether, 1 ether);
        vm.stopPrank();
        uint256 blocks = 100_000;
        for (uint256 i = 0; i < blocks; i++) {
            wrapBuy();
        }

        // comparing to bounded test, average spending will be significantly higher
        // proving that bounding with `spendADay` works
        assertLt(((blocks * 1.4 ether) / trader.blocksADay()) - 2 ether, trader.spent());
        assertLt(trader.spent(), 2 ether + ((blocks * 1.5 ether) / trader.blocksADay()));
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
            val = trader.getUniformInRange(low, high, i);
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
        assertEq(1 ether, trader.getUniformInRange(1 ether, 1 ether, 4));
    }

    function test_blockHashValues() public {
        vm.roll(block.number + 20);
        for (uint256 i = 1; i < 11; i++) {
            assert(blockhash(block.number - i) != blockhash(block.number - i - 1));
            assert(trader.getRandomNumber(block.number - i) != trader.getRandomNumber(block.number - i - 1));
        }
    }

    function test_futureBlockHashValues() public {
        vm.roll(block.number + 20);
        assert(blockhash(block.number - 1) != bytes32(0));
        assert(blockhash(block.number) == bytes32(0));
        assert(blockhash(block.number + 1) == bytes32(0));
    }
}
