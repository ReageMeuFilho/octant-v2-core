// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "solady/src/tokens/ERC20.sol";
import "solady/src/tokens/WETH.sol";

import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Trader} from "../src/routers-transformers/Trader.sol";

contract TraderStatus is Script, Test {
    function run() external {
        (, address wethToken,,,,, address trader) = new HelperConfig().activeNetworkConfig();

        console.log("ChainID:", block.chainid);
        console.log("Trader at", trader);
        console.log("Height:", block.number);
        assert(trader != address(0));

        Trader conv = Trader(payable(trader));
        uint256 chance = conv.chance();
        if (chance == 0) {
            emit log("Trade every (blocks): never");
        } else {
            uint256 tradeEveryNBlocks = type(uint256).max / chance;
            emit log_named_uint("Trade every (blocks)", tradeEveryNBlocks);
        }
        if (conv.canTrade(block.number - 1)) {
            emit log("Can trade: yes");
        } else {
            emit log("Can trade: no");
        }

        uint256 spent = conv.spent();
        emit log_named_decimal_uint("Spent (ETH)", spent, 18);

        uint256 height = block.number - conv.startingBlock();
        emit log_named_uint("Configured for (blocks)", height);

        WETH weth = WETH(payable(wethToken));

        emit log_named_decimal_uint("Contract balance (ETH)", trader.balance, 18);
        emit log_named_decimal_uint("Contract balance (WETH)", weth.balanceOf(trader), 18);

        int256 spendable =
            int256((block.number - conv.startingBlock()) * (conv.spendADay() / conv.blocksADay())) - int256(spent);
        emit log_named_decimal_int("Spendable (ETH)", spendable, 18);

        emit log_named_decimal_uint("Min trade (ETH)", conv.saleValueLow(), 18);
        emit log_named_decimal_uint("Max trade (ETH)", conv.saleValueHigh(), 18);
    }
}
