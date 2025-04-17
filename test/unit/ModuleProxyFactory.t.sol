// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";
import { ModuleProxyFactory } from "src/dragons/ModuleProxyFactory.sol";
import { DragonRouter } from "src/dragons/DragonRouter.sol";
import { ISplitChecker } from "src/interfaces/ISplitChecker.sol";

contract ModuleProxyFactoryTest is BaseTest {
    ModuleProxyFactory public factory;
    address public owner = makeAddr("owner");
    address public splitChecker = address(new SplitChecker());
    address public dragonRouter = address(new DragonRouter());
    address public governance = makeAddr("governance");
    address public regenGovernance = makeAddr("regenGovernance");
    address public metapool = makeAddr("metapool");
    address public opexVault = makeAddr("opexVault");
    address[] public strategies;

    function setUp() public {
        factory = new ModuleProxyFactory(governance, regenGovernance, metapool, splitChecker, dragonRouter);
    }

    function setupFailsWithZeroGovernance() public {
        vm.expectRevert("ZeroAddress");
        new ModuleProxyFactory(address(0), regenGovernance, metapool, splitChecker, dragonRouter);
    }

    function setupFailsWithZeroRegenGovernance() public {
        vm.expectRevert("ZeroAddress");
        new ModuleProxyFactory(governance, address(0), metapool, splitChecker, dragonRouter);
    }

    function setupFailsWithZeroMetapool() public {
        vm.expectRevert("ZeroAddress");
        new ModuleProxyFactory(governance, regenGovernance, address(0), splitChecker, dragonRouter);
    }

    function setupFailsWithZeroSplitChecker() public {
        vm.expectRevert("ZeroAddress");
        new ModuleProxyFactory(governance, regenGovernance, metapool, address(0), dragonRouter);
    }

    function setupFailsWithZeroDragonRouter() public {
        vm.expectRevert("ZeroAddress");
        new ModuleProxyFactory(governance, regenGovernance, metapool, splitChecker, address(0));
    }

    function testDeployDragonRouterWithFactory() public {
        DragonRouter router = DragonRouter(factory.deployDragonRouter(owner, strategies, opexVault, 100));
        assertTrue(router.hasRole(router.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(router.hasRole(router.GOVERNANCE_ROLE(), governance));
        assertTrue(router.hasRole(router.REGEN_GOVERNANCE_ROLE(), regenGovernance));
        assertEq(address(router.splitChecker()), 0x856353418c3022f2E4767bba2d0cfEEaB6689104);
        assertEq(router.metapool(), metapool);
    }
}
