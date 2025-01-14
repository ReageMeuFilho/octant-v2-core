// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DragonRouter} from "src/dragons/DragonRouter.sol";
import {DeploySplitChecker} from "./SplitChecker.s.sol";
import {Upgrades} from "lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

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

    function run() public virtual override {
        // First deploy SplitChecker
        DeploySplitChecker.run();

        vm.startBroadcast();

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
                address(splitCheckerProxy), // split checker address
                msg.sender, // opex vault address
                msg.sender // metapool address
            )
        );
        address _owner = msg.sender;
        
        address proxy = Upgrades.deployTransparentProxy(
            "DragonRouter.sol",
            _getConfiguredAddress("PROXY_ADMIN"),
            
            abi.encodeCall( 
                DragonRouter.setUp,
                abi.encode(_owner, initData)
            )
        );
        
        dragonRouterProxy = DragonRouter(payable(address(proxy)));
    
        vm.stopBroadcast();

        // Log deployment info
        console2.log("DragonRouter Singleton deployed at:", address(dragonRouterSingleton));
        console2.log("DragonRouter Proxy deployed at:", address(dragonRouterProxy));
        console2.log("\nConfiguration:");
        console2.log("- Governance:", _getConfiguredAddress("GOVERNANCE"));
        console2.log("- Split Checker:", address(splitCheckerProxy));
        console2.log("- Opex Vault:", _getConfiguredAddress("OPEX_VAULT"));
        console2.log("- Metapool:", _getConfiguredAddress("METAPOOL"));
    }

   
}
