// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";
import { OctantRewardsSafe } from "../src/dragons/modules/OctantRewardsSafe.sol";

contract OctantRewardsSafeModule is BaseTest {
    address keeper = makeAddr("keeper");
    address treasury = makeAddr("treasury");
    address dragonRouter = makeAddr("dragonRouter");
    uint256 totalValidators = 2;

    testTemps temps;
    OctantRewardsSafe moduleImplementation;
    OctantRewardsSafe module;

    function setUp() public override {
        super.setUp();
        moduleImplementation = new OctantRewardsSafe();
        temps = _testTemps(address(moduleImplementation), abi.encode(keeper, treasury, dragonRouter, totalValidators));
        module = OctantRewardsSafe(payable(temps.module));
    }

    function testCheckModuleInitialization() public view {
        assertTrue(module.owner() == temps.safe);
        assertTrue(module.keeper() == keeper);
        assertTrue(module.treasury() == treasury);
        assertTrue(module.dragonRouter() == dragonRouter);
        assertTrue(module.totalValidators() == totalValidators);
    }

    function testOnlyKeeperCanAddNewValidators() public {
        uint256 amount = 2;

        vm.expectRevert();
        module.addNewValidators(amount);

        vm.startPrank(keeper);
        module.addNewValidators(amount);
        assertTrue(module.totalValidators() == totalValidators + amount);
        vm.stopPrank();
    }

    function testOnlyOwnerCanSetTreasury() public {
        address newTreasury = _randomAddress();

        vm.expectRevert();
        module.setTreasury(newTreasury);

        vm.startPrank(temps.safe);
        module.setTreasury(newTreasury);
        assertTrue(module.treasury() == newTreasury);
        vm.stopPrank();
    }

    function testOnlyOwnerCanSetDragonRouter() public {
        address newDragonRouter = _randomAddress();

        vm.expectRevert();
        module.setDragonRouter(newDragonRouter);

        vm.startPrank(temps.safe);
        module.setDragonRouter(newDragonRouter);
        assertTrue(module.dragonRouter() == newDragonRouter);
        vm.stopPrank();
    }

    function testExitValidtors() public {
        uint256 yield = 1 ether;
        uint256 exitedValidators = 1;

        // can only be called by keeper
        vm.expectRevert();
        module.exitValidators(exitedValidators);

        vm.startPrank(keeper);

        // Keeper cannot exit more than totalValidators
        vm.expectRevert();
        module.exitValidators(totalValidators + 1);

        assertTrue(dragonRouter.balance == 0);
        vm.deal(temps.safe, yield); // send yield to safe
        module.exitValidators(1);
        assertTrue(module.totalValidators() == (totalValidators - exitedValidators));
        assertTrue(dragonRouter.balance == yield);

        vm.stopPrank();
    }

    function testHarvest() public {
        uint256 yield = 1 ether;
        uint256 exitedValidators = 1;

        /// Harvest works when there's no validator exited
        vm.deal(temps.safe, yield); // send yield to safe
        assertTrue(dragonRouter.balance == 0);
        module.harvest();
        assertTrue(dragonRouter.balance == yield);

        /// Harvest works when a validator is exited and there is some yield in the vault
        // exit validator
        vm.startPrank(keeper);
        module.exitValidators(1);
        vm.stopPrank();

        // yield and principal are in the safe
        vm.deal(temps.safe, yield + exitedValidators * 32 ether); // principal

        uint256 previousDragonRouterBalance = dragonRouter.balance;
        uint256 previousTreasuryBalance = treasury.balance;
        module.harvest();
        assertTrue(dragonRouter.balance == (previousDragonRouterBalance + yield));
        assertTrue(treasury.balance == (previousTreasuryBalance + exitedValidators * 32 ether));
        assertTrue(module.exitedValidators() == 0);
    }
}
