// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { BatchScript } from "../helpers/BatchScript.sol";

contract AttachModuleToSafe is Script, BatchScript {
    address safe;
    address module;

    function setUp() public {
        try vm.prompt("Enter Safe Address") returns (string memory res) {
            safe = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Invalid Safe Address Response");
        }

        try vm.prompt("Enter Module Address") returns (string memory res) {
            module = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Invalid Module Address Response");
        }
    }

    function run() public isBatch(safe) {
        bytes memory txn1 = abi.encodeWithSignature("enableModule(address)", module);
        addToBatch(safe, 0, txn1);
        executeBatch(true);
    }
}
