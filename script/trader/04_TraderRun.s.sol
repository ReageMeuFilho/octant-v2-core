// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "solady/tokens/ERC20.sol";
import "solady/tokens/WETH.sol";

import {HelperConfig} from "../helpers/HelperConfig.s.sol";
import {Trader} from "src/routers-transformers/Trader.sol";

contract TraderRun is Script, Test {
    Trader trader;

    uint256 scanSince;
    uint256 deployerKey;
    address ETH;

    function max(uint256 a, uint256 b) public pure returns (uint256) {
        if (a > b) return a;
        return b;
    }

    function run() external {
        (,,, uint256 _deployerKey,,,,,,) = new HelperConfig(false).activeNetworkConfig();

        deployerKey = _deployerKey;
        trader = Trader(payable(vm.envAddress("TRADER")));
        ETH = trader.ETH();

        console.log("ChainID:", block.chainid);
        console.log("Trader at", address(trader));
        require(address(trader) != address(0), "Please provide trader address via TRADER env var");

        if (safeBalanceOf(trader.base(), address(trader)) != 0) {
            vm.startBroadcast(deployerKey);
            trade_loop();
            vm.stopBroadcast();
        } else {
            console.log("Trader is out of base token");
        }
    }

    function trade_loop() public {
        scanSince = max(block.number - 255, trader.lastHeight()) + 1;
        emit log_named_uint("Scanning since", scanSince);
        for (uint256 height = scanSince; height < block.number - 1; height++) {
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
    }

    function safeBalanceOf(address token, address owner) private view returns (uint256) {
        if ((token == ETH) || (token == address(0x0))) {
            return owner.balance;
        } else {
            return ERC20(token).balanceOf(owner);
        }
    }
}
