// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";
import { ModuleProxyFactory } from "src/dragons/ModuleProxyFactory.sol";
import { DragonRouter } from "src/dragons/DragonRouter.sol";
import { ISplitChecker } from "src/interfaces/ISplitChecker.sol";

contract ModuleProxyFactoryTest is BaseTest {
    ModuleProxyFactory public factory;
    address public owner = makeAddr("owner");
    address public splitChecker = makeAddr("splitChecker");
    address public dragonRouter = address(new DragonRouter());
    address public governance = makeAddr("governance");
    address public regenGovernance = makeAddr("regenGovernance");
    address public metapool = makeAddr("metapool");
    address public opexVault = makeAddr("opexVault");
    address[] public strategies;

    function setUp() public {
        factory = new ModuleProxyFactory(governance, regenGovernance, splitChecker, metapool, dragonRouter);
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
