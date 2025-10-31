// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxy.sol";
import "forge-std/Script.sol";
import { BatchScript } from "../helpers/BatchScript.sol";

contract AddTransactionToSafe is BatchScript {
    address public safe_;
    address public dragonVaultModule;
    address public token;

    function setUp() public {
        safe_ = vm.envAddress("SAFE_ADDRESS");
        dragonVaultModule = vm.envAddress("SAFE_DRAGON_VAULT_MODULE_ADDRESS");
        token = vm.envAddress("TOKEN");
    }

    function run() public isBatch(safe_) {
        bytes memory txn1 = abi.encodeWithSignature("approve(address,uint256)", dragonVaultModule, 100e18);

        addToBatch(token, 0, txn1);

        bytes memory data = abi.encodeWithSignature("mint(uint256,address)", 1e18, safe_);

        bytes memory txn2 = abi.encodeWithSignature("exec(bytes)", data);

        addToBatch(dragonVaultModule, 0, txn2);

        executeBatch(true);
    }
}
