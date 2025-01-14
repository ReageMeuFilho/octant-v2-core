// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {SplitChecker} from "src/dragons/SplitChecker.sol";

/**
 * @title DeploySplitChecker
 * @notice Script to deploy the base implementation of SplitChecker
 * @dev This deploys the implementation contract that will be used as the base for all split checkers
 */
contract DeploySplitChecker is Script {
    /// @notice The deployed SplitChecker implementation
    SplitChecker public splitCheckerSingleton;

    function run() public virtual {
        vm.startBroadcast();
        splitCheckerSingleton = new SplitChecker();
        vm.stopBroadcast();

        // Log deployment
        console2.log("SplitChecker Implementation deployed at:", address(splitCheckerSingleton));
    }
}
