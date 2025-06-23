// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console } from "forge-std/Script.sol";
import { ProxyableRegenStaker } from "src/regen/ProxyableRegenStaker.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";

/// @notice Deployment script for ProxyableRegenStaker factory system
/// @dev This deploys:
/// @dev 1. Master ProxyableRegenStaker implementation contract
/// @dev 2. RegenStakerFactory that creates minimal proxies of the implementation
contract DeployProxyableRegenStakerFactory is Script {
    function run() external returns (address implementation, address factory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the master implementation contract
        implementation = address(new ProxyableRegenStaker());

        // Deploy the factory with the implementation address
        factory = address(new RegenStakerFactory(implementation));

        vm.stopBroadcast();

        // Log deployment addresses
        console.log("ProxyableRegenStaker implementation deployed at:", implementation);
        console.log("RegenStakerFactory deployed at:", factory);
        console.log("Gas savings: Each proxy ~117 bytes vs full contract ~24KB+ = 99.5%+ savings");
    }
}
