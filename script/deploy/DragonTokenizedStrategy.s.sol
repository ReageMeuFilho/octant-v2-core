// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DragonTokenizedStrategy} from "src/dragons/vaults/DragonTokenizedStrategy.sol";
import {DeploySafe} from "./Safe.s.sol";

/**
 * @title DeployDragonTokenizedStrategy
 * @notice Script to deploy the base implementation of DragonTokenizedStrategy
 * @dev This deploys the implementation contract that will be used as the base for all dragon strategies
 */
contract DeployDragonTokenizedStrategy is Script {
    DragonTokenizedStrategy public dragonTokenizedStrategySingleton;

    function run() public virtual {
           vm.startBroadcast();
        dragonTokenizedStrategySingleton = new DragonTokenizedStrategy();
        vm.stopBroadcast();
    }
}
