// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "safe-contracts/proxies/SafeProxy.sol";
import "forge-std/Script.sol";
import { BatchScript } from "forge-safe/src/BatchScript.sol";

contract AddTransactionToSafe is BatchScript {
    address public safe_;
    address public dragonVaultModule;

    function setUp() public {
        safe_ = vm.envAddress("SAFE_ADDRESS");
        dragonVaultModule = vm.envAddress("SAFE_ADDRESS");
    }

    function run() public isBatch(safe_) {
        bytes memory data = abi.encodeWithSignature("mint(uint256,address)", 1e18, safe_);

        bytes memory txn = abi.encodeWithSignature("exec(bytes)", data);

        addToBatch(dragonVaultModule, 0, txn);

        executeBatch(true);
    }
}
