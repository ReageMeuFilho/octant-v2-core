// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { SkyCompounderStrategyFactory } from "src/factories/SkyCompounderStrategyFactory.sol";

contract DeploySkyCompounderStrategyFactory is Script {
    SkyCompounderStrategyFactory public skyCompounderStrategyFactory;

    function deploy() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        skyCompounderStrategyFactory = new SkyCompounderStrategyFactory();
        vm.stopBroadcast();
    }
}
