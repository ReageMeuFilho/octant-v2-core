// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ModuleProxyFactory} from "../src/dragons/ModuleProxyFactory.sol";
import {VaultModule} from "../src/vaults/VaultModule.sol";
import {TestERC20} from "../src/test/TestERC20.sol";
import "forge-std/Script.sol";

contract DeployModuleFactoryTestToken is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ModuleProxyFactory factory = new ModuleProxyFactory();

        VaultModule dragonVaultModule = new VaultModule();

        TestERC20 testERC20 = new TestERC20();

        vm.stopBroadcast();

        // Log the address of the newly deployed Safe
        console.log("Factory deployed at:", address(factory));
        console.log("Dragon Vault Module deployed at:", address(dragonVaultModule));
        console.log("Test ERC20 Token", address(testERC20));
    }
}
