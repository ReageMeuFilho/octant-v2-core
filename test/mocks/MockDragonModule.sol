// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDragonModule} from "src/interfaces/IDragonModule.sol";
import {IDragonRouter} from "src/interfaces/IDragonRouter.sol";

contract MockDragonModule is IDragonModule {
    IERC20 public dragonToken;
    IDragonRouter public dragonRouter;

    constructor(address token, address router) {
        dragonToken = IERC20(token);
        dragonRouter = IDragonRouter(router);
    }

    function getDragonRouter() external view returns (address) {
        return address(dragonRouter);
    }

    function getDragonToken() external view returns (address) {
        return address(dragonToken);
    }
}
