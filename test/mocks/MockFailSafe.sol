// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

/// @dev Mock Safe that returns false on execTransactionFromModule
contract FailSafe {
    function execTransactionFromModule(
        address /*to*/,
        uint256 /*value*/,
        bytes memory /*data*/,
        Enum.Operation /*operation*/
    ) external pure returns (bool success) {
        success = false;
    }
}
