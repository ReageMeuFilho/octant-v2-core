// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { Vault } from "../../../src/dragons/vaults/Vault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "../../../src/interfaces/IVault.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { Constants } from "./utils/constants.sol";

contract VaultRolesTest is Test {
    Vault public vault;
    MockERC20 public asset;
    address public gov;
    address public fish;
    address public strategist;
    address public bunny;

    function setUp() public {
        gov = address(this);
        fish = makeAddr("fish");
        strategist = makeAddr("strategist");
        bunny = makeAddr("bunny");
        asset = new MockERC20();

        // Create and initialize the vault
        vault = new Vault();
        vault.initialize(
            address(asset),
            "Test Vault",
            "tvTEST",
            gov,
            7 days // profitMaxUnlockTime
        );
    }

    function testSetRole() public {
        // Gov can set role
        vault.setRole(fish, IVault.Roles.DEBT_MANAGER);

        // Fish tries to set role (should fail)
        vm.prank(fish);
        vm.expectRevert("not allowed");
        vault.setRole(fish, IVault.Roles.DEBT_MANAGER);
    }

    function testTransfersRoleManager() public {
        // Check initial state
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), Constants.ZERO_ADDRESS);

        // Gov transfers role to strategist
        vault.transferRoleManager(strategist);
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), strategist);

        // Strategist accepts role
        vm.prank(strategist);
        vault.acceptRoleManager();
        assertEq(vault.roleManager(), strategist);
        assertEq(vault.futureRoleManager(), Constants.ZERO_ADDRESS);
    }

    function testGovTransfersRoleManager_GovCantAccept() public {
        // Check initial state
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), Constants.ZERO_ADDRESS);

        // Gov transfers role to strategist
        vault.transferRoleManager(strategist);
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), strategist);

        // Gov tries to accept (should fail)
        vm.expectRevert("not future role manager");
        vault.acceptRoleManager();

        // State should remain unchanged
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), strategist);
    }

    function testRandomTransfersRoleManager_Reverts() public {
        // Check initial state
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), Constants.ZERO_ADDRESS);

        // Strategist tries to transfer role (should fail)
        vm.prank(strategist);
        vm.expectRevert("not allowed");
        vault.transferRoleManager(strategist);

        // State should remain unchanged
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), Constants.ZERO_ADDRESS);
    }

    function testGovTransfersRoleManager_CanChangeFutureManager() public {
        // Check initial state
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), Constants.ZERO_ADDRESS);

        // Gov transfers role to strategist
        vault.transferRoleManager(strategist);
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), strategist);

        // Gov changes future manager to bunny
        vault.transferRoleManager(bunny);
        assertEq(vault.roleManager(), gov);
        assertEq(vault.futureRoleManager(), bunny);

        // Strategist tries to accept (should fail)
        vm.prank(strategist);
        vm.expectRevert("not future role manager");
        vault.acceptRoleManager();

        // Bunny accepts the role
        vm.prank(bunny);
        vault.acceptRoleManager();
        assertEq(vault.roleManager(), bunny);
        assertEq(vault.futureRoleManager(), Constants.ZERO_ADDRESS);
    }
}
