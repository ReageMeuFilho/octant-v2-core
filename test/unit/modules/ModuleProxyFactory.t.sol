// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { TestPlus } from "lib/solady/test/utils/TestPlus.sol";
import { ModuleProxyFactory } from "src/dragons/ModuleProxyFactory.sol";
import { ISafe } from "src/interfaces/Safe.sol";
import { MockModule } from "../../mocks/MockModule.sol";
import { MockSafe } from "../../mocks/MockSafe.sol";

contract ModuleProxyFactoryTest is Test {
    ModuleProxyFactory public factory;
    address public mockModuleMaster;

    function setUp() public {
        factory = new ModuleProxyFactory();
        // Deploy a mock module implementation
        mockModuleMaster = address(new MockModule());
    }

    function testCalculateProxyAddress() public {
        // Create initializer data and salt nonce
        bytes memory initializer = abi.encodeWithSignature("setUp(address)", address(this));
        uint256 saltNonce = 12345;

        // Calculate the expected address
        address calculatedAddress = factory.getModuleAddress(mockModuleMaster, initializer, saltNonce);

        // Deploy a proxy and verify the address matches
        address deployedAddress = factory.deployModule(mockModuleMaster, initializer, saltNonce);

        assertEq(calculatedAddress, deployedAddress, "Calculated address should match deployed address");
    }

    function testGetModuleAddress() public {
        // Test data
        bytes memory initializer = abi.encodeWithSignature("setUp(address)", address(this));
        uint256 saltNonce = 12345;

        // Get the calculated address
        address addressViaGetModule = factory.getModuleAddress(mockModuleMaster, initializer, saltNonce);

        // Actually deploy and compare
        address deployedAddress = factory.deployModule(mockModuleMaster, initializer, saltNonce);

        assertEq(addressViaGetModule, deployedAddress, "Calculated address should match deployed address");
    }

    // Test with different salts to ensure determinism
    function testFuzz_DeterministicAddresses(uint256 saltNonce) public {
        vm.assume(saltNonce > 0); // Avoid zero salt

        bytes memory initializer = abi.encodeWithSignature("setUp(address)", address(this));

        // Calculate the expected address
        address expectedAddress = factory.getModuleAddress(mockModuleMaster, initializer, saltNonce);

        // Deploy and check
        address deployedAddress = factory.deployModule(mockModuleMaster, initializer, saltNonce);

        assertEq(expectedAddress, deployedAddress, "Address calculation should be deterministic");
    }
}
