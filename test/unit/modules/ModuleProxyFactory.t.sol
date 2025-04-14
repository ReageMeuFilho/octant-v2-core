// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { TestPlus } from "lib/solady/test/utils/TestPlus.sol";
import { ModuleProxyFactory } from "src/dragons/ModuleProxyFactory.sol";
import { ISafe } from "src/interfaces/Safe.sol";
import { MockModule } from "../../mocks/MockModule.sol";
import { MockSafe } from "../../mocks/MockSafe.sol";
import { MockLinearAllowance } from "../../mocks/MockLinearAllowance.sol";
import { MockSafeDragonRouter } from "../../mocks/MockSafeDragonRouter.sol";
import { MultiSend } from "src/libraries/Safe/MultiSend.sol";
import { MockSplitChecker } from "../../mocks/MockSplitChecker.sol";

contract ModuleProxyFactoryTest is Test {
    ModuleProxyFactory public moduleProxyFactory;
    address public mockModuleMaster;
    address public splitCheckerImpl;
    address public dragonRouterImpl;
    address public linearAllowanceImpl;
    MultiSend public multiSend;
    MockSafe public safe;

    function setUp() public {
        moduleProxyFactory = new ModuleProxyFactory();
        // Deploy a mock module implementation
        mockModuleMaster = address(new MockModule());

        // Deploy MultiSend contract
        multiSend = new MultiSend();

        // Create mock Safe
        safe = new MockSafe();

        // Deploy implementations
        splitCheckerImpl = address(new MockSplitChecker());
        dragonRouterImpl = address(new MockSafeDragonRouter(address(0)));
        linearAllowanceImpl = address(new MockLinearAllowance());
    }

    function testCalculateProxyAddress() public {
        // Create initializer data and salt nonce
        bytes memory initializer = abi.encodeWithSignature("setUp(address)", address(this));
        uint256 saltNonce = 12345;

        // Calculate the expected address
        address calculatedAddress = moduleProxyFactory.getModuleAddress(mockModuleMaster, initializer, saltNonce);

        // Deploy a proxy and verify the address matches
        address deployedAddress = moduleProxyFactory.deployModule(mockModuleMaster, initializer, saltNonce);

        assertEq(calculatedAddress, deployedAddress, "Calculated address should match deployed address");
    }

    function testGetModuleAddress() public {
        // Test data
        bytes memory initializer = abi.encodeWithSignature("setUp(address)", address(this));
        uint256 saltNonce = 12345;

        // Get the calculated address
        address addressViaGetModule = moduleProxyFactory.getModuleAddress(mockModuleMaster, initializer, saltNonce);

        // Actually deploy and compare
        address deployedAddress = moduleProxyFactory.deployModule(mockModuleMaster, initializer, saltNonce);

        assertEq(addressViaGetModule, deployedAddress, "Calculated address should match deployed address");
    }

    // Test with different salts to ensure determinism
    function testFuzz_DeterministicAddresses(uint256 saltNonce) public {
        vm.assume(saltNonce > 0); // Avoid zero salt

        bytes memory initializer = abi.encodeWithSignature("setUp(address)", address(this));

        // Calculate the expected address
        address expectedAddress = moduleProxyFactory.getModuleAddress(mockModuleMaster, initializer, saltNonce);

        // Deploy and check
        address deployedAddress = moduleProxyFactory.deployModule(mockModuleMaster, initializer, saltNonce);

        assertEq(expectedAddress, deployedAddress, "Address calculation should be deterministic");
    }

    function testMultiSendBatchDeployment() public {
        // Setup deployment data
        bytes memory splitCheckerInit = abi.encodeWithSignature("setUp()");
        uint256 splitCheckerSalt = 100;

        // Calculate predicted addresses
        address predictedSplitChecker = moduleProxyFactory.getModuleAddress(
            splitCheckerImpl,
            splitCheckerInit,
            splitCheckerSalt
        );

        // DragonRouter deployment data
        bytes memory dragonRouterInit = abi.encodeWithSignature("setUp(address)", predictedSplitChecker);
        uint256 dragonRouterSalt = 200;
        address predictedDragonRouter = moduleProxyFactory.getModuleAddress(
            dragonRouterImpl,
            dragonRouterInit,
            dragonRouterSalt
        );

        // LinearAllowance module deployment data
        bytes memory linearAllowanceInit = abi.encodeWithSignature("setUp(address)", address(safe));

        bytes memory tx1 = _buildDeployModuleTx(
            moduleProxyFactory,
            splitCheckerImpl,
            splitCheckerInit,
            splitCheckerSalt
        );

        bytes memory tx2 = _buildDeployModuleTx(
            moduleProxyFactory,
            dragonRouterImpl,
            dragonRouterInit,
            dragonRouterSalt
        );

        uint256 linearAllowanceSalt = 300;
        bytes memory tx3 = _buildEnableModuleTx(
            moduleProxyFactory,
            linearAllowanceImpl,
            linearAllowanceInit,
            linearAllowanceSalt
        );

        // Combine transactions
        bytes memory batchData = bytes.concat(tx1, tx2, tx3);

        bool success = safe.execTransactionViaDelegateCall(
            address(multiSend),
            abi.encodeWithSelector(multiSend.multiSend.selector, batchData)
        );

        // Verify everything was deployed and initialized properly
        assertTrue(success, "MultiSend transaction failed");
        assertTrue(predictedSplitChecker.code.length > 0, "SplitChecker not deployed");
        assertTrue(predictedDragonRouter.code.length > 0, "DragonRouter not deployed");
        assertEq(
            MockSafeDragonRouter(predictedDragonRouter).splitChecker(),
            predictedSplitChecker,
            "DragonRouter not initialized with SplitChecker"
        );
    }

    // Helper function to build a regular module deployment transaction
    function _buildDeployModuleTx(
        ModuleProxyFactory factory,
        address implementation,
        bytes memory initializer,
        uint256 salt
    ) internal pure returns (bytes memory) {
        bytes memory callData = abi.encodeWithSelector(
            factory.deployModule.selector,
            implementation,
            initializer,
            salt
        );

        return
            abi.encodePacked(
                uint8(0), // operation: CALL
                address(factory), // to: module factory
                uint256(0), // value
                uint256(callData.length), // data length
                callData // data
            );
    }

    // Helper function to build an enable module transaction (delegatecall)
    function _buildEnableModuleTx(
        ModuleProxyFactory factory,
        address implementation,
        bytes memory initializer,
        uint256 salt
    ) internal pure returns (bytes memory) {
        bytes memory callData = abi.encodeWithSelector(
            factory.deployAndEnableModuleFromSafe.selector,
            implementation,
            initializer,
            salt
        );

        return
            abi.encodePacked(
                uint8(1), // operation: DELEGATECALL
                address(factory), // to: module factory
                uint256(0), // value
                uint256(callData.length), // data length
                callData // data
            );
    }
}
