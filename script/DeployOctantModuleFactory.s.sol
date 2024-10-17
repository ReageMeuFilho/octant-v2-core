// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ModuleProxyFactory} from "../src/dragons/ModuleProxyFactory.sol";
import {OctantRewardsSafe} from "../src/dragons/modules/OctantRewardsSafe.sol";
import "forge-std/Script.sol";

contract DeployOctantModuleFactory is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ModuleProxyFactory factory = new ModuleProxyFactory();

        OctantRewardsSafe octantModule = new OctantRewardsSafe();

        vm.stopBroadcast();

        // Log the address of the newly deployed Safe
        console.log("Factory deployed at:", address(factory));
        console.log("Octant Safe Module deployed at:", address(octantModule));
    }
}
