// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "solady/tokens/ERC20.sol";
import "solady/tokens/WETH.sol";

import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Trader} from "../src/routers-transformers/Trader.sol";

contract TraderStatus is Script, Test {
    function run() external {
        (, address wethToken,,,,, address traderAddress,,,) = new HelperConfig(false).activeNetworkConfig();

        console.log("ChainID:", block.chainid);
        console.log("Trader at", traderAddress);
        console.log("Height:", block.number);
        assert(traderAddress != address(0));

        Trader trader = Trader(payable(traderAddress));
        uint256 chance = trader.chance();
        if (chance == 0) {
            emit log("Trade every (blocks): never");
        } else {
            uint256 tradeEveryNBlocks = type(uint256).max / chance;
            emit log_named_uint("Trade every (blocks)", tradeEveryNBlocks);
        }
        if (trader.canTrade(block.number - 1)) {
            emit log("Can trade: yes");
        } else {
            emit log("Can trade: no");
        }

        uint256 spent = trader.spent();
        emit log_named_decimal_uint("Spent (ETH)", spent, 18);

        uint256 height = block.number - trader.spentResetBlock();
        emit log_named_uint("Configured for (blocks)", height);

        WETH weth = WETH(payable(wethToken));

        emit log_named_decimal_uint("Contract balance (ETH)", traderAddress.balance, 18);
        emit log_named_decimal_uint("Contract balance (WETH)", weth.balanceOf(traderAddress), 18);

        int256 spendable = int256(
            (block.number - trader.spentResetBlock()) * (trader.spendADay() / trader.BLOCKS_PER_DAY())
        ) - int256(spent);
        emit log_named_decimal_int("Spendable (ETH)", spendable, 18);

        emit log_named_decimal_uint("Min trade (ETH)", trader.saleValueLow(), 18);
        emit log_named_decimal_uint("Max trade (ETH)", trader.saleValueHigh(), 18);
    }
}
