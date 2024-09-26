// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

contract GetBytesData is Script {
    function setUp() public {}

    event BytesData(bytes data);

    function run() public {
        vm.startBroadcast();

        bytes memory data = abi.encodeWithSignature(
            "mint(uint256,address)",
            1e18,
            0x4b3247099847F6a30E763dB903A9C6e63189fCde
        );

        // Log the data of the newly deployed Safe
        emit BytesData(data);

        vm.stopBroadcast();
    }
}
