// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ModuleProxyFactory } from "../src/dragons/ModuleProxyFactory.sol";
import { OctantRewardsSafe } from "../src/dragons/modules/OctantRewardsSafe.sol";
import { SplitChecker } from "../src/dragons/SplitChecker.sol";
import { DragonRouter } from "../src/dragons/DragonRouter.sol";
import "forge-std/Script.sol";

contract DeployOctantModuleFactory is Script {
    address public splitCheckerImplementation = address(new SplitChecker());
    address public dragonRouterImplementation = address(new DragonRouter());

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ModuleProxyFactory factory = new ModuleProxyFactory(
            msg.sender,
            msg.sender,
            msg.sender,
            splitCheckerImplementation,
            dragonRouterImplementation
        );

        OctantRewardsSafe octantModule = new OctantRewardsSafe();

        vm.stopBroadcast();

        // Log the address of the newly deployed Safe
        console.log("Factory deployed at:", address(factory));
        console.log("Octant Safe Module deployed at:", address(octantModule));
    }
}
