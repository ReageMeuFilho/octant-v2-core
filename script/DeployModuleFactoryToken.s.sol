// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ModuleProxyFactory } from "../src/dragons/ModuleProxyFactory.sol";
import { DragonVaultModule } from "../src/dragons/DragonVaultModule.sol";
import { TestERC20 } from "../src/test/TestERC20.sol";
import "forge-std/Script.sol";

contract DeployModuleFactoryTestToken is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy a new Safe Multisig using the Proxy Factory
        ModuleProxyFactory factory = new ModuleProxyFactory();

        DragonVaultModule dragonVaultModule = new DragonVaultModule();

        TestERC20 testERC20 = new TestERC20();

        vm.stopBroadcast();

        // Log the address of the newly deployed Safe
        console.log("Factory deployed at:", address(factory));
        console.log("Dragon Vault Module deployed at:", address(dragonVaultModule));
        console.log("Test ERC20 Token", address(testERC20));
    }
}
