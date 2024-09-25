// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "safe-contracts/proxies/SafeProxy.sol";
import { ModuleProxyFactory } from "../src/dragons/ModuleProxyFactory.sol";
import { BatchScript } from "forge-safe/src/BatchScript.sol";

contract AddTransactionToSafe is BatchScript {
    address public safe_;
    ModuleProxyFactory public moduleFactory;
    address public dragonVaultModule;

    function setUp() public {
        safe_ = vm.envAddress("SAFE_ADDRESS");
        moduleFactory = ModuleProxyFactory(payable(vm.envAddress("MODULE_FACTORY"));
        safeModuleImplementation = vm.envAddress("MODULE");
        address token = vm.envAddress("TOKEN");        
    }

    function run() public isBatch(safe_) {
        dragonVaultModule = moduleFactory.deployModule(safeModuleImplementation, abi.encodeWithSignature("setUp(bytes)", abi.encode(safe_, token)), block.timestamp)

        console.log("Linked Dragon Vault Module: ", dragonVaultModule);

        bytes memory txn1 = abi.encodeWithSignature("enableModule(address)", dragonVaultModule);

        addToBatch(safe_, 0, txn1);

        executeBatch(true);
    }
}
