// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.8.0;

import { ISafe } from "../interfaces/Safe.sol";
import { ModuleProxyFactory } from "zodiac/factory/ModuleProxyFactory.sol";

contract DragonModuleProxyFactory is ModuleProxyFactory {
    function deployAndEnableModuleFromSafe(
        address masterCopy,
        bytes memory data,
        uint256 saltNonce
    ) public returns (address proxy) {
        proxy = deployModule(
            masterCopy,
            abi.encodeWithSignature("setUp(bytes)", abi.encode(address(this), data)),
            saltNonce
        );

        ISafe(address(this)).enableModule(proxy);
    }
}
