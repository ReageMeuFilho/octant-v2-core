// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "safe-contracts/proxies/SafeProxy.sol";
import { DragonModuleProxyFactory } from "../src/dragons/ModuleProxyFactory.sol";
import { BatchScript } from "forge-safe/src/BatchScript.sol";

contract DeployModuleAndEnableOnSafe is Script, BatchScript {
    address public safe_;
    address public token;
    DragonModuleProxyFactory public moduleFactory;
    address public safeModuleImplementation;
    address public dragonVaultModule;

    function setUp() public {
        safe_ = vm.envAddress("SAFE_ADDRESS");
        moduleFactory = DragonModuleProxyFactory(vm.envAddress("MODULE_FACTORY"));
        safeModuleImplementation = vm.envAddress("MODULE");
        token = vm.envAddress("TOKEN");
    }

    function run() public isBatch(safe_) {
        vm.startBroadcast();

        dragonVaultModule = moduleFactory.deployModule(
            safeModuleImplementation,
            abi.encodeWithSignature("setUp(bytes)", abi.encode(safe_, bytes32(0), bytes32(0), token)),
            block.timestamp
        );

        console.log("Linked Dragon Vault Module: ", dragonVaultModule);

        vm.stopBroadcast();

        bytes memory txn1 = abi.encodeWithSignature("enableModule(address)", dragonVaultModule);

        addToBatch(safe_, 0, txn1);

        executeBatch(true);
    }
}
