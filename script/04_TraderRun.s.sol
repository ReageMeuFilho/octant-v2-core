// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "solady/src/tokens/ERC20.sol";
import "solady/src/tokens/WETH.sol";

import {HelperConfig} from "./helpers/HelperConfig.s.sol";
import {Trader} from "../src/routers-transformers/Trader.sol";

contract TraderRun is Script, Test {
    function max(uint256 a, uint256 b) public pure returns (uint256) {
        if (a > b) return a;
        return b;
    }

    function run() external {
        (,,, uint256 deployerKey,,, address traderAddress,,,) = new HelperConfig(false).activeNetworkConfig();

        console.log("ChainID:", block.chainid);
        console.log("Trader at", traderAddress);
        assert(traderAddress != address(0));

        vm.startBroadcast(deployerKey);

        Trader trader = Trader(payable(traderAddress));
        uint256 scan_since = max(block.number - 255, trader.lastHeight()) + 1;
        emit log_named_uint("Scanning since", scan_since);
        for (uint256 height = scan_since; height < block.number - 1; height++) {
            if (trader.canTrade(height)) {
                if (!trader.hasOverspent(height)) {
                    emit log_named_uint("Height YES, has budget YES", height);
                    trader.convert(height);
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
