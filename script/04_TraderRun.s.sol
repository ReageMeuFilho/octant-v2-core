// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "solady/src/tokens/ERC20.sol";
import "solady/src/tokens/WETH.sol";

import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Trader} from "../src/routers-transformers/Trader.sol";

contract TraderRun is Script, Test {
    function max(uint a, uint b) public pure returns (uint) {
        if (a > b) return a;
        return b;
    }
    function run() external {
        (,,, uint256 deployerKey,,, address trader) = new HelperConfig().activeNetworkConfig();

        console.log("ChainID:", block.chainid);
        console.log("Trader at", trader);
        assert(trader != address(0));

        vm.startBroadcast(deployerKey);

        Trader conv = Trader(payable(trader));
        uint256 scan_since = max(block.number - 255, conv.lastHeight()) + 1;
        emit log_named_uint("Scanning since", scan_since);
        for (uint height = scan_since; height < block.number - 1; height++) {
            if (conv.canTrade(height)) {
                if (!conv.hasOverspent(height)) {
                    emit log_named_uint("Height YES, has budget YES", height);
                    conv.convert(height);
                } else {
                    emit log_named_uint("Height YES, has budget no ", height);
                }
            } else {
                emit log_named_uint("Height no ", height);
            }
        }

        vm.stopBroadcast();
    }
}
