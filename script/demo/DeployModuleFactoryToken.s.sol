// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ModuleProxyFactory } from "src/dragons/ModuleProxyFactory.sol";
import { MockVaultModule } from "test/mocks/MockVaultModule.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import "forge-std/Script.sol";

contract DeployModuleFactoryTestToken is Script {
    address public governance = 0x0000000000000000000000000000000000000001;
    address public regenGovernance = 0x0000000000000000000000000000000000000001;
    address public splitChecker = 0x0000000000000000000000000000000000000001;
    address public metapool = 0x0000000000000000000000000000000000000001;
    address public dragonRouterImplementation = 0x0000000000000000000000000000000000000001;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ModuleProxyFactory factory = new ModuleProxyFactory(
            governance,
            regenGovernance,
            splitChecker,
            metapool,
            dragonRouterImplementation
        );

        MockVaultModule dragonVaultModule = new MockVaultModule();

        MockERC20 testERC20 = new MockERC20();

        vm.stopBroadcast();

        // Log the address of the newly deployed Safe
        console.log("Factory deployed at:", address(factory));
        console.log("Dragon Vault Module deployed at:", address(dragonVaultModule));
        console.log("Test ERC20 Token", address(testERC20));
    }
}
