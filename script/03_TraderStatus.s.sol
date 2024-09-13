// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "solady/src/tokens/ERC20.sol";
import "solady/src/tokens/WETH.sol";

import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Converter} from "../src/routers-transformers/Converter.sol";

contract TraderStatus is Script, Test {
    function run() external {
        (
            address glmToken,
            address wethToken,
            address _nPM,
            uint256 deployerKey,
            address _uniswapV3Router,
            address _uniswapGlmWethPool,
            address demoConverter
        ) = new HelperConfig().activeNetworkConfig();

        console.log("ChainID:", block.chainid);
        console.log("Converter at", demoConverter);
        assert(demoConverter != address(0));

        Converter conv = Converter(payable(demoConverter));
        uint chance = conv.chance();
        if (chance == 0) {
            emit log("Trade every (blocks): never");
        }
        else {
            uint tradeEveryNBlocks = type(uint256).max / chance;
            emit log_named_uint("Trade every (blocks)", tradeEveryNBlocks);
        }
        uint spent = conv.spent();
        emit log_named_decimal_uint("Spent (ETH)", spent, 18);

        uint height = block.number - conv.startingBlock();
        emit log_named_uint("Configured for (blocks)", height);

        WETH weth = WETH(payable(wethToken));
        ERC20 glm = ERC20(glmToken);

        emit log_named_decimal_uint("Contract balance (ETH)", demoConverter.balance, 18);
        emit log_named_decimal_uint("Contract balance (WETH)", weth.balanceOf(demoConverter), 18);
        emit log_named_decimal_uint("Contract balance (GLM)", glm.balanceOf(demoConverter), 18);

        uint price = conv.price();
        emit log_named_decimal_uint("ETH price (GLM)", price, 18);

        int spendable = int((block.number - conv.startingBlock()) * (conv.spendADay() / conv.blocksADay())) - int(spent);
        emit log_named_decimal_int("Spendable (ETH)", spendable, 18);

        emit log_named_decimal_uint("Min trade (ETH)", conv.saleValueLow(), 18);
        emit log_named_decimal_uint("Max trade (ETH)", conv.saleValueHigh(), 18);

        emit log_named_decimal_uint("Last bought (GLM)", conv.lastBought(), 18);
        emit log_named_decimal_uint("Last quota  (GLM)", conv.lastQuota(), 18);
    }
}
