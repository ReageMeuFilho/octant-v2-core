// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DragonRouter } from "src/zodiac-core/DragonRouter.sol";
import { DeploySplitChecker } from "./DeploySplitChecker.sol";
/**
 * @title DeployDragonRouter
 * @notice Script to deploy the DragonRouter with transparent proxy pattern
 * @dev Uses OpenZeppelin Upgrades plugin to handle proxy deployment
 */

contract DeployDragonRouter is DeploySplitChecker {
    /// @notice The deployed DragonRouter implementation
    DragonRouter public dragonRouterSingleton;
    /// @notice The deployed DragonRouter proxy
    DragonRouter public dragonRouterProxy;

    function deploy() public virtual override {
        // First deploy SplitChecker

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        DeploySplitChecker.deploy();

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        dragonRouterSingleton = new DragonRouter();

        // setup empty strategies and assets
        address[] memory strategies = new address[](0);
        address[] memory assets = new address[](0);

        bytes memory initData = abi.encode(
            msg.sender, // owner
            abi.encode(
                strategies, // initial strategies array
                assets, // initial assets array
                msg.sender, // governance address
                msg.sender, // regen governance address
                address(splitCheckerProxy), // split checker address
                msg.sender, // opex vault address
                msg.sender // metapool address
            )
        );

        // Deploy ProxyAdmin for DragonRouter proxy
        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);

        // Deploy TransparentProxy for DragonRouter
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(dragonRouterSingleton),
            address(proxyAdmin),
            abi.encodeCall(DragonRouter.setUp, initData)
        );

        dragonRouterProxy = DragonRouter(payable(address(proxy)));

        vm.stopBroadcast();

        // Log deployment info
        // console2.log("DragonRouter Singleton deployed at:", address(dragonRouterSingleton));
        // console2.log("DragonRouter Proxy deployed at:", address(dragonRouterProxy));
        // console2.log("\nConfiguration:");
        // console2.log("- Governance:", _getConfiguredAddress("GOVERNANCE"));
        // console2.log("- Split Checker:", address(splitCheckerProxy));
        // console2.log("- Opex Vault:", _getConfiguredAddress("OPEX_VAULT"));
        // console2.log("- Metapool:", _getConfiguredAddress("METAPOOL"));
    }
}
