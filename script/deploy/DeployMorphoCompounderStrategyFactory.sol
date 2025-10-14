// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { MorphoCompounderStrategyFactory } from "src/factories/MorphoCompounderStrategyFactory.sol";

contract DeployMorphoCompounderStrategyFactory is Script {
    MorphoCompounderStrategyFactory public morphoCompounderStrategyFactory;

    function deploy() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        morphoCompounderStrategyFactory = new MorphoCompounderStrategyFactory();
        vm.stopBroadcast();
    }
}
