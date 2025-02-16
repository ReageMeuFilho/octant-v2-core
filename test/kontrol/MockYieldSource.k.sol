// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Module } from "zodiac/core/Module.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { ERC4626Upgradeable } from "openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract MockYieldSource is ERC4626Upgradeable {

    function setUp(address _asset) public initializer {
        __ERC4626_init(IERC20(_asset));
    }

    function availableDepositLimit(
        address /*_owner*/
    ) public view virtual returns (uint256) {
        return type(uint256).max;
    }                                                                       

}
