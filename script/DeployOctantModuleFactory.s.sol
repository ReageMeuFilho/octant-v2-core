// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ModuleProxyFactory } from "../src/dragons/ModuleProxyFactory.sol";
import { OctantRewardsSafe } from "../src/dragons/modules/OctantRewardsSafe.sol";
import "forge-std/Script.sol";

contract DeployOctantModuleFactory is Script {
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

        OctantRewardsSafe octantModule = new OctantRewardsSafe();

        vm.stopBroadcast();

        // Log the address of the newly deployed Safe
        console.log("Factory deployed at:", address(factory));
        console.log("Octant Safe Module deployed at:", address(octantModule));
    }
}
