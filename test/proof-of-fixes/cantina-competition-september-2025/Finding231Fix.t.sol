// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { MultistrategyLockedVault } from "src/core/MultistrategyLockedVault.sol";
import { MultistrategyVaultFactory } from "src/factories/MultistrategyVaultFactory.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";
import { IMultistrategyLockedVault } from "src/core/interfaces/IMultistrategyLockedVault.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockFactory } from "test/mocks/MockFactory.sol";

contract Finding231Fix is Test {
    MultistrategyLockedVault internal vaultImplementation;
    MultistrategyLockedVault internal vault;
    MockERC20 internal asset;
    MockFactory internal factory;
    MultistrategyVaultFactory internal vaultFactory;

    address internal governance = address(0x1);
    address internal feeRecipient = address(0x2);
    uint256 internal constant DEFAULT_PROFIT_MAX_UNLOCK = 7 days;
    uint256 internal constant MAX_INT = type(uint256).max;

    function setUp() public {
        asset = new MockERC20(18);
        asset.mint(governance, 1_000_000e18);

        vm.prank(governance);
        factory = new MockFactory(0, feeRecipient);

        vm.startPrank(address(factory));
        vaultImplementation = new MultistrategyLockedVault();
        vaultFactory = new MultistrategyVaultFactory("Locked Vault", address(vaultImplementation), governance);
        vault = MultistrategyLockedVault(
            vaultFactory.deployNewVault(address(asset), "Locked Vault", "vLOCK", governance, DEFAULT_PROFIT_MAX_UNLOCK)
        );
        vm.stopPrank();

        vm.startPrank(governance);
        vault.addRole(governance, IMultistrategyVault.Roles.ADD_STRATEGY_MANAGER);
        vault.addRole(governance, IMultistrategyVault.Roles.DEBT_MANAGER);
        vault.addRole(governance, IMultistrategyVault.Roles.MAX_DEBT_MANAGER);
        vault.addRole(governance, IMultistrategyVault.Roles.DEPOSIT_LIMIT_MANAGER);
        vault.setDepositLimit(MAX_INT, false);
        vm.stopPrank();
    }

    function testCancelWithinGraceSucceeds() public {
        vm.startPrank(governance);
        uint256 newPeriod = 8 days;
        vault.proposeRageQuitCooldownPeriodChange(newPeriod);

        uint256 proposedAt = vault.getRageQuitCooldownPeriodChangeTimestamp();
        uint256 cancelTime = proposedAt + vault.RAGE_QUIT_COOLDOWN_CHANGE_DELAY() - 1;
        vm.warp(cancelTime);

        vm.expectEmit(false, false, false, true);
        emit IMultistrategyLockedVault.RageQuitCooldownPeriodChangeCancelled(newPeriod, proposedAt, cancelTime);
        vm.expectEmit(false, false, false, true);
        emit IMultistrategyLockedVault.PendingRageQuitCooldownPeriodChange(0, 0);

        vault.cancelRageQuitCooldownPeriodChange();

        assertEq(vault.getPendingRageQuitCooldownPeriod(), 0, "pending should clear");
        assertEq(vault.getRageQuitCooldownPeriodChangeTimestamp(), 0, "timestamp should clear");
        vm.stopPrank();
    }

    function testCancelAfterGraceReverts() public {
        vm.startPrank(governance);
        uint256 newPeriod = 9 days;
        vault.proposeRageQuitCooldownPeriodChange(newPeriod);

        uint256 proposedAt = vault.getRageQuitCooldownPeriodChangeTimestamp();
        vm.warp(proposedAt + vault.RAGE_QUIT_COOLDOWN_CHANGE_DELAY());

        vm.expectRevert(IMultistrategyLockedVault.RageQuitCooldownPeriodChangeDelayElapsed.selector);
        vault.cancelRageQuitCooldownPeriodChange();
        vm.stopPrank();
    }
}
