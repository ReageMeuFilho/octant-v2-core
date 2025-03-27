// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "forge-std/console.sol";

contract MockESF is IERC1271 {
    using ECDSA for bytes32;

    address public operator;
    bytes4 private constant MAGIC_VALUE = 0x1626ba7e;

    constructor(address _operator) {
        operator = _operator;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        address signer = hash.recover(signature);

        if (signer == operator) {
            return MAGIC_VALUE;
        }
        return 0x00000000;
    }
}
