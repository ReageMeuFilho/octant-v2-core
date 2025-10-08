// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { MultistrategyLockedVault } from "src/core/MultistrategyLockedVault.sol";
import { MultistrategyVaultFactory } from "src/factories/MultistrategyVaultFactory.sol";
import { IMultistrategyLockedVault } from "src/core/interfaces/IMultistrategyLockedVault.sol";
import { MockFactory } from "test/mocks/MockFactory.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract Finding592Fix is Test {
    address private constant GOVERNANCE = address(0xA11CE);
    address private constant FEE_RECIPIENT = address(0xFEE);

    MockERC20 private asset;
    MultistrategyLockedVault private vault;

    function setUp() public {
        asset = new MockERC20(18);
        asset.mint(GOVERNANCE, 1 ether);

        vm.prank(GOVERNANCE);
        MockFactory factory = new MockFactory(0, FEE_RECIPIENT);

        vm.startPrank(address(factory));
        MultistrategyLockedVault implementation = new MultistrategyLockedVault();
        MultistrategyVaultFactory vaultFactory = new MultistrategyVaultFactory(
            "Locked Test Vault",
            address(implementation),
            GOVERNANCE
        );
        vault = MultistrategyLockedVault(
            vaultFactory.deployNewVault(address(asset), "Locked Test Vault", "vLTST", GOVERNANCE, 7 days)
        );
        vm.stopPrank();
    }

    function test_RegenGovernanceTransferRequiresAcceptance() public {
        address newGovernance = address(0xBEEF);

        vm.expectEmit(true, true, false, true);
        emit IMultistrategyLockedVault.RegenGovernanceTransferUpdate(GOVERNANCE, newGovernance, 0);
        vm.prank(GOVERNANCE);
        vault.setRegenGovernance(newGovernance);

        assertEq(vault.regenGovernance(), GOVERNANCE, "governance should not change immediately");
        assertEq(vault.pendingRegenGovernance(), newGovernance, "pending governance mismatch");

        // Pending governance must accept the transfer.
        vm.expectEmit(true, true, false, true);
        emit IMultistrategyLockedVault.RegenGovernanceTransferUpdate(GOVERNANCE, newGovernance, 1);
        vm.prank(newGovernance);
        vault.acceptRegenGovernance();

        assertEq(vault.regenGovernance(), newGovernance, "governance should transfer after acceptance");
        assertEq(vault.pendingRegenGovernance(), address(0), "pending governance should be cleared");
    }
}
