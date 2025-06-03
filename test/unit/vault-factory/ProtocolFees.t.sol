// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { MultistrategyVaultFactory } from "src/factories/MultistrategyVaultFactory.sol";
import { MultistrategyVault } from "src/core/MultistrategyVault.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract ProtocolFeesTest is Test {
    MultistrategyVaultFactory vaultFactory;
    address gov;
    address bunny;
    address asset;
    address constant ZERO_ADDRESS = address(0);
    address vaultOriginal;

    function setUp() public {
        gov = address(0x1);
        bunny = address(0x3);
        asset = address(new MockERC20(18));
        vaultOriginal = address(new MultistrategyVault());

        vm.startPrank(gov);
        vaultFactory = new MultistrategyVaultFactory("Test Factory", vaultOriginal, gov);
        vm.stopPrank();
    }

    function createVault(address _asset, string memory vaultName) internal returns (address) {
        vm.prank(gov);
        return vaultFactory.deployNewVault(_asset, vaultName, "vTST", gov, 7 days);
    }

    function testSetProtocolFeeRecipient() public {
        vm.prank(gov);
        vm.recordLogs();
        vaultFactory.setProtocolFeeRecipient(gov);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        require(entries.length > 0, "No logs found");

        // Check event
        // Event: UpdateProtocolFeeRecipient(address indexed old_fee_recipient, address indexed new_fee_recipient)
        // Since we're looking at raw event data, we need to check the proper event signature and parameters
        bytes32 expectedTopic = keccak256("UpdateProtocolFeeRecipient(address,address)");
        require(entries[0].topics[0] == expectedTopic, "Wrong event");
        require(address(uint160(uint256(entries[0].topics[1]))) == ZERO_ADDRESS, "Wrong old fee recipient");
        require(address(uint160(uint256(entries[0].topics[2]))) == gov, "Wrong new fee recipient");

        // Check state
        (, address feeRecipient) = vaultFactory.protocolFeeConfig(ZERO_ADDRESS);
        assertEq(feeRecipient, gov, "Fee recipient was not set correctly");
    }

    function testSetProtocolFeeRecipientZeroAddressReverts() public {
        vm.prank(gov);
        vm.expectRevert("zero address");
        vaultFactory.setProtocolFeeRecipient(ZERO_ADDRESS);
    }

    function testSetProtocolFees() public {
        // Check initial state
        (uint16 initialFee, ) = vaultFactory.protocolFeeConfig(ZERO_ADDRESS);
        assertEq(initialFee, 0, "Initial fee should be 0");

        // Need to set the fee recipient first
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(gov);

        // Now set the fee
        vm.prank(gov);
        vm.recordLogs();
        vaultFactory.setProtocolFeeBps(20);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        require(entries.length > 0, "No logs found");

        // Check event
        // Event: UpdateProtocolFeeBps(uint16 indexed old_fee_bps, uint16 indexed new_fee_bps)
        bytes32 expectedTopic = keccak256("UpdateProtocolFeeBps(uint16,uint16)");
        require(entries[0].topics[0] == expectedTopic, "Wrong event");

        // Check state
        (uint16 newFee, ) = vaultFactory.protocolFeeConfig(ZERO_ADDRESS);
        assertEq(newFee, 20, "Fee was not set correctly");
    }

    function testSetCustomProtocolFee() public {
        // Set the default protocol fee recipient
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(gov);

        (uint16 defaultFee, address recipient) = vaultFactory.protocolFeeConfig(ZERO_ADDRESS);
        assertEq(defaultFee, 0, "Default fee should be 0");
        assertEq(recipient, gov, "Fee recipient should be gov");

        // Create a vault
        address vault = createVault(asset, "Test Vault");

        // Verify default settings
        (uint16 vaultFee, address vaultRecipient) = vaultFactory.protocolFeeConfig(vault);
        assertEq(vaultFee, 0, "Vault fee should be default");
        assertEq(vaultRecipient, gov, "Vault recipient should be default");

        // Set custom fee
        uint16 newFee = 20;
        vm.prank(gov);
        vm.recordLogs();
        vaultFactory.setCustomProtocolFeeBps(vault, newFee);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        require(entries.length > 0, "No logs found");

        // Check event
        // Event: UpdateCustomProtocolFee(address indexed vault, uint16 new_custom_protocol_fee)
        bytes32 expectedTopic = keccak256("UpdateCustomProtocolFee(address,uint16)");
        require(entries[0].topics[0] == expectedTopic, "Wrong event");
        require(address(uint160(uint256(entries[0].topics[1]))) == vault, "Wrong vault address");

        // Check state
        bool useCustom = vaultFactory.useCustomProtocolFee(vault);
        assertTrue(useCustom, "Should use custom fee");

        (uint16 customFee, address customRecipient) = vaultFactory.protocolFeeConfig(vault);
        assertEq(customFee, newFee, "Custom fee not set correctly");
        assertEq(customRecipient, gov, "Recipient should remain the same");

        // Default should be unchanged
        (defaultFee, recipient) = vaultFactory.protocolFeeConfig(ZERO_ADDRESS);
        assertEq(defaultFee, 0, "Default fee should be unchanged");
    }

    function testRemoveCustomProtocolFee() public {
        // Set the default protocol fee recipient
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(gov);

        // Set default fee
        uint16 genericFee = 8;
        vm.prank(gov);
        vaultFactory.setProtocolFeeBps(genericFee);

        // Create a vault
        address vault = createVault(asset, "Test Vault");

        // Set custom fee
        uint16 customFee = 20;
        vm.prank(gov);
        vaultFactory.setCustomProtocolFeeBps(vault, customFee);

        // Verify custom fee
        (uint16 vaultFee, ) = vaultFactory.protocolFeeConfig(vault);
        assertEq(vaultFee, customFee, "Custom fee not set");

        // Remove custom fee
        vm.prank(gov);
        vm.recordLogs();
        vaultFactory.removeCustomProtocolFee(vault);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        require(entries.length > 0, "No logs found");

        // Check event
        // Event: RemovedCustomProtocolFee(address indexed vault)
        bytes32 expectedTopic = keccak256("RemovedCustomProtocolFee(address)");
        require(entries[0].topics[0] == expectedTopic, "Wrong event");
        require(address(uint160(uint256(entries[0].topics[1]))) == vault, "Wrong vault address");

        // Check updated state
        (vaultFee, ) = vaultFactory.protocolFeeConfig(vault);
        assertEq(vaultFee, genericFee, "Fee should revert to default");

        bool useCustom = vaultFactory.useCustomProtocolFee(vault);
        assertFalse(useCustom, "Should not use custom fee anymore");
    }

    function testSetProtocolFeeBeforeRecipientReverts() public {
        (, address recipient) = vaultFactory.protocolFeeConfig(ZERO_ADDRESS);
        assertEq(recipient, ZERO_ADDRESS, "Recipient should be zero address");

        vm.prank(gov);
        vm.expectRevert("no recipient");
        vaultFactory.setProtocolFeeBps(20);
    }

    function testSetCustomFeeBeforeRecipientReverts() public {
        address vault = createVault(asset, "Test Vault");

        (, address recipient) = vaultFactory.protocolFeeConfig(ZERO_ADDRESS);
        assertEq(recipient, ZERO_ADDRESS, "Recipient should be zero address");

        vm.prank(gov);
        vm.expectRevert("no recipient");
        vaultFactory.setCustomProtocolFeeBps(vault, 20);
    }

    function testSetCustomProtocolFeeByBunnyReverts() public {
        address vault = createVault(asset, "new vault");

        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.setCustomProtocolFeeBps(vault, 10);
    }

    function testSetCustomProtocolFeesTooHighReverts() public {
        // Set the default protocol fee recipient
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(gov);

        address vault = createVault(asset, "new vault");

        vm.prank(gov);
        vm.expectRevert("fee too high");
        vaultFactory.setCustomProtocolFeeBps(vault, 5_001);
    }

    function testRemoveCustomProtocolFeeByBunnyReverts() public {
        address vault = createVault(asset, "new vault");

        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.removeCustomProtocolFee(vault);
    }

    function testSetProtocolFeeRecipientByBunnyReverts() public {
        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.setProtocolFeeRecipient(bunny);
    }

    function testSetProtocolFeesTooHighReverts() public {
        // Set the default protocol fee recipient first
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(gov);

        vm.prank(gov);
        vm.expectRevert("fee too high");
        vaultFactory.setProtocolFeeBps(10_001);
    }

    function testSetProtocolFeesByBunnyReverts() public {
        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.setProtocolFeeBps(20);
    }
}
