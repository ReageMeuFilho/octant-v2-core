// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import { Trader } from "./Trader.sol";
import { DragonRouter } from "src/zodiac-core/DragonRouter.sol";

contract TraderBotEntry {
    constructor() {}

    function flash(address _router, address user, address strategy, address _trader) public {
        Trader trader = Trader(payable(_trader));
        DragonRouter router = DragonRouter(payable(_router));
        uint256 amount = trader.findSaleValue(max(trader.saleValueHigh(), router.balanceOf(user, strategy)));
        router.claimSplit(user, strategy, amount);
    }

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        if (a > b) return a;
        else return b;
    }
}
