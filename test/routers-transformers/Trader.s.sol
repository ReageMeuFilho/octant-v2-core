// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../Base.t.sol";
import "src/routers-transformers/Trader.sol";
import {HelperConfig} from "script/helpers/HelperConfig.s.sol";

contract TestTraderRandomness is BaseTest {
    HelperConfig helperConfig = new HelperConfig();

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    testTemps temps;
    Trader public moduleImplementation;
    Trader public trader;

    address swapper = makeAddr("swapper");
    bool log_spending = false;
    string constant deadlineFn = "./cache/test-artifacts/deadline.csv";

    function setUp() public {
        _configure(false);
        moduleImplementation = new Trader();
        temps = _testTemps(address(moduleImplementation), abi.encode(ETH, token, swapper));
        trader = Trader(payable(temps.module));
    }

    receive() external payable {}

    function testConfigurationBasic() public {
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

    function testConfigurationLowSaleIsTooLow() public {
        vm.startPrank(temps.safe);
        vm.expectRevert(Trader.Trader__ImpossibleConfigurationSaleValueLowIsTooLow.selector);
        trader.setSpendADay(1, 1 ether, 1 ether, block.number + 102);
        vm.stopPrank();
    }

    function testConfigurationLowIsZero() public {
        vm.startPrank(temps.safe);
        vm.expectRevert(Trader.Trader__ImpossibleConfigurationSaleValueLowIsZero.selector);
        trader.setSpendADay(0, 1 ether, 1 ether, block.number + 102);
        vm.stopPrank();
    }

    function testConfigurationDeadlineInPast() public {
        vm.roll(1000);
        vm.startPrank(temps.safe);
        vm.expectRevert(Trader.Trader__ImpossibleConfigurationDeadlineInThePast.selector);
        trader.setSpendADay(1, 1 ether, 1 ether, 100);
        vm.stopPrank();
    }

    // sequential call to this function emulate time progression
    function wrapBuy() public returns (bool) {
        vm.roll(block.number + 1);
        try trader.convert(block.number - 1) {
            if (log_spending) {
                string memory currentBudget = vm.toString((trader.budget() - trader.spent()) / 1e15);
                vm.writeLine(deadlineFn, string(abi.encodePacked(vm.toString(block.number), ",", currentBudget)));
            }
            return true;
        } catch (bytes memory) /*lowLevelData*/ {
            return false;
        }
    }

    function test_receivesEth() external {
        (bool sent,) = payable(address(trader)).call{value: 100000}("");
        require(sent, "Failed to send Ether");
    }

    function concat(string memory _a, string memory _b) public pure returns (string memory) {
        return string(abi.encodePacked(_a, _b));
    }

    function test_deadline() external {
        uint256 budget = 1000 ether;
        vm.deal(address(trader), budget);
        if (vm.exists(deadlineFn)) {
            vm.removeFile(deadlineFn);
        }
        uint256 blocks = 10_000;
        vm.startPrank(temps.safe);
        trader.setSpendADay(0.6 ether, 1.4 ether, budget, block.number + blocks);
        vm.stopPrank();
        assertEq(address(trader).balance, budget);
        assertEq(trader.budget(), budget);
        assertEq(trader.spent(), 0);
        for (uint256 i = 0; i < blocks; i++) {
            wrapBuy();
        }
        assertEq(trader.budget(), trader.spent());
    }

    function test_safety_blocks_value() external {
        uint256 blocks = 1_000_000;
        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, 100_000 ether, block.number + blocks);
        vm.stopPrank();
        assertEq(trader.getSafetyBlocks(), 100_000);
    }

    function test_safety_blocks_chance() external {
        uint256 blocks = 1000;
        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, 1000 ether, block.number + blocks);
        vm.stopPrank();
        vm.roll(block.number + blocks - trader.getSafetyBlocks());
        assertEq(type(uint256).max, trader.chance());
        vm.roll(block.number + blocks - 1);
        assertEq(type(uint256).max, trader.chance());
    }

    function test_overspend_protection() external {
        // This test will attempt to overspend, simulating validator griding hash values.
        // Since forge doesn't allow to manipulate blockhash directly, overspending
        // is done by manipulating return value of `chance()` function.
        uint256 blocks = 1000;
        vm.startPrank(temps.safe);
        uint256 budget_value = 100 ether;
        trader.setSpendADay(1 ether, 1 ether, budget_value, block.number + blocks);
        vm.stopPrank();

        // mock chance
        vm.mockCall(address(trader), abi.encodeWithSelector(Trader.chance.selector), abi.encode(type(uint256).max - 1));

        // sanity check
        assertEq(type(uint256).max - 1, trader.chance());

        /* run trader */
        for (uint256 i = 0; i < blocks / 2; i++) {
            wrapBuy();
        }

        assertLe(trader.spent(), trader.budget() / 2);
    }

    function test_chance_high() external {
        uint256 blocks = 1_000_000;
        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, 100_000 ether, block.number + blocks);
        vm.stopPrank();
        assertLt(trader.chance(), type(uint256).max / 9);
    }

    function test_chance_low() external {
        uint256 blocks = 1_000_000;
        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 1 ether, 100_000 ether, block.number + blocks);
        vm.stopPrank();
        assertGt(trader.chance(), type(uint256).max / 11);
    }

    function test_avg_sale_chance_high() external {
        uint256 blocks = 1_000_000;
        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 3 ether, 100_000 ether, block.number + blocks);
        vm.stopPrank();
        assertLt(trader.chance(), type(uint256).max / 18);
    }

    function test_avg_sale_chance_low() external {
        uint256 blocks = 1_000_000;
        vm.startPrank(temps.safe);
        trader.setSpendADay(1 ether, 3 ether, 100_000 ether, block.number + blocks);
        vm.stopPrank();
        assertGt(trader.chance(), type(uint256).max / 20);
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
