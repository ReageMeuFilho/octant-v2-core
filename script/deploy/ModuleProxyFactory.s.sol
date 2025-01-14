// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleProxyFactory} from "src/dragons/ModuleProxyFactory.sol";

/**
 * @title DeployModuleProxyFactory
 * @notice Script to deploy the ModuleProxyFactory contract
 * @dev This factory is used to deploy minimal proxy clones of Safe modules
 *      following the EIP-1167 standard for minimal proxy contracts
 */
contract DeployModuleProxyFactory is Script {
    /// @notice The deployed ModuleProxyFactory instance
    ModuleProxyFactory public moduleProxyFactory;

    function run() public virtual{
        vm.startBroadcast();
        
        // Deploy the factory
        moduleProxyFactory = new ModuleProxyFactory();
        
        vm.stopBroadcast();

        // Log deployment information
        console2.log("ModuleProxyFactory deployed at:", address(moduleProxyFactory));
    }
}
