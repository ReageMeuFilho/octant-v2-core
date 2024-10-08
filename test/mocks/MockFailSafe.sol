// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

/// @dev Mock Safe that returns false on execTransactionFromModule
contract FailSafe {
    // solhint-disable-next-line unused-function-parameter
    function execTransactionFromModule(address, uint256, bytes memory, Enum.Operation) external returns (bool success) {
        success = false;
    }
}
