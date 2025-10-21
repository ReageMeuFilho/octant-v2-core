// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";

contract DeployAllocationMechanismFactory is Script {
    AllocationMechanismFactory public allocationMechanismFactory;

    function deploy() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        allocationMechanismFactory = new AllocationMechanismFactory();
        vm.stopBroadcast();
    }
}
