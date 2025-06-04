// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { LinearAllowanceSingletonForGnosisSafe } from "src/zodiac-core/modules/LinearAllowanceSingletonForGnosisSafe.sol";

/**
 * @title DeployLinearAllowanceSingletonForGnosisSafe
 * @notice Script to deploy the LinearAllowanceSingletonForGnosisSafe contract
 */
contract DeployLinearAllowanceSingletonForGnosisSafe is Test {
    /// @notice The deployed LinearAllowanceSingletonForGnosisSafe instance
    LinearAllowanceSingletonForGnosisSafe public linearAllowanceSingletonForGnosisSafe;

    function deploy() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        linearAllowanceSingletonForGnosisSafe = new LinearAllowanceSingletonForGnosisSafe();

        vm.stopBroadcast();
    }
}
