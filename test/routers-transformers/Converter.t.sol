pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/routers-transformers/Converter.sol";

contract Wrapper is Test {
    Converter public conv;
    uint256 public blockno = 1;
    uint256 public constr = 0;
    uint256 public budget = 10_000 ether;

    function setUp() external {
        conv = new Converter(0, 0);
        vm.deal(address(conv), budget);
    }

    // sequential call to this function emulate time
    // progressing and set random values for randao
    function wrapBuy() public returns (bool) {
        constr = 1;
        vm.roll(blockno);
        vm.prevrandao(bytes32(blockno));
        blockno = blockno + 1;
        try conv.buy() {
            return true;
        } catch (bytes memory /*lowLevelData*/) {
            return false;
        }
    }

    function test_wrapBuyBounded() external {
        uint256 chance = type(uint256).max / uint256(4000); // corresponds to 0.00025 chance
        uint256 spendADay = 1 ether;
        conv.setSpendADay(chance, spendADay);
        uint256 blocks = 500_000;
        for (uint256 i = 0; i < blocks; i++) {
            wrapBuy();
        }

        // check if spending above target minus two buys
        assertLt((blocks * 1 ether / 7200) - 2 ether, conv.spent());

        // check if spending below target plus one buy
        assertLt(conv.spent(), 1 ether + (blocks * 1 ether / 7200));
    }

    function test_wrapBuyUnbounded() external {
        uint256 chance = type(uint256).max / uint256(4000); // corresponds to 0.00025 chance
        uint256 spendADay = 100 ether;
        conv.setSpendADay(chance, spendADay);
        uint256 blocks = 500_000;
        for (uint256 i = 0; i < blocks; i++) {
            wrapBuy();
        }

        // comparing to bounded test, average spending will be significantly higher
        // proving that bounding with `spendADay` works
        assertLt((blocks * 1.4 ether / 7200) - 2 ether, conv.spent());
        assertLt(conv.spent(), 2 ether + (blocks * 1.5 ether / 7200));
    }

    function test_keccak_distribution() external {
        uint256 maxdiv4096 = 28269553036454149273332760011886696253239742350009903329945699220681916416;
        uint256 counter = 0;

        for (uint256 i = 0; i < 1_000_000; i++) {
            if (uint256(keccak256(abi.encode(bytes32(i)))) < maxdiv4096) {
                counter = counter + 1;
            }
        }
        assertGt(counter, 240); // EV(counter) ~= 244
    }

    function test_setting_prevrandao() external {
        uint256 i = 12093812093812;
        bytes32 val = keccak256(abi.encode(bytes32(i)));
        vm.prevrandao(val);
        assert(block.prevrandao == uint256(val));
    }

    function test_division() external {
        assertLt(0, type(uint256).max / uint256(4000));
        assertLt(type(uint256).max / uint256(4000), type(uint256).max / uint256(3999));
        uint256 maxdiv4096 = 28269553036454149273332760011886696253239742350009903329945699220681916416;
        assertGt(type(uint256).max / uint256(4095), maxdiv4096);
        assertLt(type(uint256).max / uint256(4097), maxdiv4096);
    }

}
