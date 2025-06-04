// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { MultistrategyVaultFactory } from "src/factories/MultistrategyVaultFactory.sol";
import { MultistrategyVault } from "src/core/MultistrategyVault.sol";

contract OwnershipTest is Test {
    MultistrategyVaultFactory vaultFactory;
    address gov;
    address strategist;
    address bunny;
    address constant ZERO_ADDRESS = address(0);
    address vaultOriginal;

    function setUp() public {
        gov = address(0x1);
        strategist = address(0x2);
        bunny = address(0x3);
        vaultOriginal = address(0x4);

        vm.startPrank(gov);
        vaultFactory = new MultistrategyVaultFactory("Test Factory", vaultOriginal, gov);
        vm.stopPrank();
    }

    function testGovTransfersOwnership() public {
        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), ZERO_ADDRESS);

        vm.prank(gov);
        vaultFactory.transferGovernance(strategist);

        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), strategist);

        vm.prank(strategist);
        vaultFactory.acceptGovernance();

        assertEq(vaultFactory.governance(), strategist);
        assertEq(vaultFactory.pendingGovernance(), ZERO_ADDRESS);
    }

    function testGovCantAccept() public {
        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), ZERO_ADDRESS);

        vm.prank(gov);
        vaultFactory.transferGovernance(strategist);

        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), strategist);

        vm.prank(gov);
        vm.expectRevert("not pending governance");
        vaultFactory.acceptGovernance();

        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), strategist);
    }

    function testRandomTransfersOwnershipFails() public {
        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), ZERO_ADDRESS);

        vm.prank(strategist);
        vm.expectRevert("not governance");
        vaultFactory.transferGovernance(strategist);

        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), ZERO_ADDRESS);
    }

    function testGovCanChangePending() public {
        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), ZERO_ADDRESS);

        vm.prank(gov);
        vaultFactory.transferGovernance(strategist);

        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), strategist);

        vm.prank(gov);
        vaultFactory.transferGovernance(bunny);

        assertEq(vaultFactory.governance(), gov);
        assertEq(vaultFactory.pendingGovernance(), bunny);

        vm.prank(strategist);
        vm.expectRevert("not pending governance");
        vaultFactory.acceptGovernance();

        vm.prank(bunny);
        vaultFactory.acceptGovernance();

        assertEq(vaultFactory.governance(), bunny);
        assertEq(vaultFactory.pendingGovernance(), ZERO_ADDRESS);
    }
}
