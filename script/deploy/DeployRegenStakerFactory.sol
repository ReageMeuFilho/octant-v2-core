// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";

contract DeployRegenStakerFactory is Script {
    RegenStakerFactory public regenStakerFactory;

    function deploy() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        regenStakerFactory = new RegenStakerFactory();
        vm.stopBroadcast();
    }
}
