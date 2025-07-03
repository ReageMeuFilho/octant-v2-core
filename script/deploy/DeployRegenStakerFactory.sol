// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";

contract DeployRegenStakerFactory is Script {
    RegenStakerFactory public regenStakerFactory;

    function deploy() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get bytecode for both variants
        bytes memory regenStakerBytecode = type(RegenStaker).creationCode;
        bytes memory noDelegationBytecode = type(RegenStakerWithoutDelegateSurrogateVotes).creationCode;

        regenStakerFactory = new RegenStakerFactory(regenStakerBytecode, noDelegationBytecode);
        vm.stopBroadcast();
    }
}
