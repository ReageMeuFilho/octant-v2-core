// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

contract MockLinearAllowance {
    address public safe;

    // This function should be used for direct deployment with deployModule
    function setUp(address _safe) public {
        safe = _safe;
    }

    // This function is called when deployed via deployAndEnableModuleFromSafe
    function setUp(bytes memory data) public {
        (address _safe, ) = abi.decode(data, (address, bytes));
        safe = _safe;
    }
}
