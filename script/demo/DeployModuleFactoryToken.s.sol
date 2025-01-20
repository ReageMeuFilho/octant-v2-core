// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ModuleProxyFactory} from "src/dragons/ModuleProxyFactory.sol";
import {MockVaultModule} from "test/mocks/MockVaultModule.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import "forge-std/Script.sol";

contract DeployModuleFactoryTestToken is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ModuleProxyFactory factory = new ModuleProxyFactory();

        MockVaultModule dragonVaultModule = new MockVaultModule();

        MockERC20 testERC20 = new MockERC20();

        vm.stopBroadcast();

        // Log the address of the newly deployed Safe
        console.log("Factory deployed at:", address(factory));
        console.log("Dragon Vault Module deployed at:", address(dragonVaultModule));
        console.log("Test ERC20 Token", address(testERC20));
    }
}
