// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { RocketPoolStrategyFactory } from "src/factories/yieldSkimming/RocketPoolStrategyFactory.sol";

contract DeployRocketPoolStrategyFactory is Script {
    RocketPoolStrategyFactory public rocketPoolStrategyFactory;

    function deploy() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        rocketPoolStrategyFactory = new RocketPoolStrategyFactory();
        vm.stopBroadcast();
    }
}
