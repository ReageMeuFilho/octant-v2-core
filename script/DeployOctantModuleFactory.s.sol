// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ModuleProxyFactory } from "../src/zodiac-core/ModuleProxyFactory.sol";
import { OctantRewardsSafe } from "../src/zodiac-core/modules/OctantRewardsSafe.sol";
import { SplitChecker } from "../src/zodiac-core/SplitChecker.sol";
import { DragonRouter } from "../src/zodiac-core/DragonRouter.sol";
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
