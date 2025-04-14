// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import { ModuleProxyFactory } from "src/dragons/ModuleProxyFactory.sol";

/**
 * @title DeployModuleProxyFactory
 * @notice Script to deploy the ModuleProxyFactory contract
 * @dev This factory is used to deploy minimal proxy clones of Safe modules
 *      following the EIP-1167 standard for minimal proxy contracts
 */
contract DeployModuleProxyFactory is Script {
    address public governance = 0x0000000000000000000000000000000000000001;
    address public regenGovernance = 0x0000000000000000000000000000000000000001;
    address public splitChecker = 0x0000000000000000000000000000000000000001;
    address public metapool = 0x0000000000000000000000000000000000000001;
    address public dragonRouterImplementation = 0x0000000000000000000000000000000000000001;
    /// @notice The deployed ModuleProxyFactory instance
    ModuleProxyFactory public moduleProxyFactory;

    function deploy() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the factory
        moduleProxyFactory = new ModuleProxyFactory(
            governance,
            regenGovernance,
            splitChecker,
            metapool,
            dragonRouterImplementation
        );

        vm.stopBroadcast();
    }
}
