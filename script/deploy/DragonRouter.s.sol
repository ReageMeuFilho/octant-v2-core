// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DragonRouter} from "src/dragons/DragonRouter.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * @title DeployDragonRouter
 * @notice Script to deploy the DragonRouter with transparent proxy pattern
 * @dev Uses OpenZeppelin Upgrades plugin to handle proxy deployment
 */
contract DeployDragonRouter is Script {
    /// @notice The deployed DragonRouter implementation
    DragonRouter public dragonRouterImplementation;
    /// @notice The deployed DragonRouter proxy
    DragonRouter public dragonRouterProxy;

    function run() public virtual {
        vm.startBroadcast();

        // Deploy implementation
        address implementation = Upgrades.deployImplementation(
            DragonRouter,
            "DragonRouter_v1"
        );
        dragonRouterImplementation = DragonRouter(implementation);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            DragonRouter.initialize.selector,
            _getConfiguredAddress("DRAGON_ROUTER_OWNER"),
            _getConfiguredAddress("DRAGON_ROUTER_ADMIN")
        );

        address proxy = Upgrades.deployTransparentProxy(
            "DragonRouter_v1",
            _getConfiguredAddress("DRAGON_ROUTER_ADMIN"),
            initData
        );
        dragonRouterProxy = DragonRouter(proxy);

        vm.stopBroadcast();

        // Log deployment info
        console2.log("DragonRouter Implementation deployed at:", address(dragonRouterImplementation));
        console2.log("DragonRouter Proxy deployed at:", address(dragonRouterProxy));
        console2.log("\nConfiguration:");
        console2.log("- Owner:", _getConfiguredAddress("DRAGON_ROUTER_OWNER"));
        console2.log("- Admin:", _getConfiguredAddress("DRAGON_ROUTER_ADMIN"));
    }

    /**
     * @dev Helper to get address from environment with fallback to msg.sender
     */
    function _getConfiguredAddress(string memory key) internal view returns (address) {
        try vm.envAddress(key) returns (address value) {
            return value;
        } catch {
            return msg.sender;
        }
    }
}
