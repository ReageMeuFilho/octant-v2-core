// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import { LinearAllowanceSingletonForGnosisSafe } from "src/dragons/modules/LinearAllowanceSingletonForGnosisSafe.sol";

contract LinearAllowanceSingletonForGnosisSafeWrapper is LinearAllowanceSingletonForGnosisSafe {
    function exposeUpdateAllowance(LinearAllowance memory a) public view returns (LinearAllowance memory) {
        return _updateAllowance(a);
    }
}
