// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { LidoStrategyFactory } from "src/factories/LidoStrategyFactory.sol";

contract DeployLidoStrategyFactory is Script {
    LidoStrategyFactory public lidoStrategyFactory;

    function deploy() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        lidoStrategyFactory = new LidoStrategyFactory();
        vm.stopBroadcast();
    }
}
