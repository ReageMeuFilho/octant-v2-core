// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {BatchScript} from "forge-safe/src/BatchScript.sol";

contract CreateSafeWithModule is Script, BatchScript {
    address safe;

    function setUp() public {
        // Initialize vars
        safe = vm.envAddress("SAFE_ADDRESS");
    }


    function run() public isBatch(safe) {    
        // Enable DragonRouter module
        bytes memory txn1 = abi.encodeWithSignature("enableModule(address)", vm.envAddress("DRAGON_ROUTER"));

        addToBatch(safe, 0, txn1);

        executeBatch(true);
    }
}
