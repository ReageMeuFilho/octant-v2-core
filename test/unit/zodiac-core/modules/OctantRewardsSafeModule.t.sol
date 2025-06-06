// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../Base.t.sol";
import { OctantRewardsSafe, OctantRewardsSafe__InvalidNumberOfValidators, OctantRewardsSafe__InvalidAddress, OctantRewardsSafe__InvalidMaxYield, OctantRewardsSafe__TransferFailed, OctantRewardsSafe__YieldNotInRange } from "src/zodiac-core/modules/OctantRewardsSafe.sol";
import { FailSafe } from "test/mocks/MockFailSafe.sol";

contract OctantRewardsSafeModule is BaseTest {
    address keeper = makeAddr("keeper");
    address treasury = makeAddr("treasury");
    address dragonRouter = makeAddr("dragonRouter");
    uint256 totalValidators = 2;
    uint256 maxYield = 31 ether;

    testTemps temps;
    OctantRewardsSafe moduleImplementation;
    OctantRewardsSafe module;

    function setUp() public {
        _configure(true, "eth");
        moduleImplementation = new OctantRewardsSafe();
        temps = _testTemps(
            address(moduleImplementation),
            abi.encode(keeper, treasury, dragonRouter, totalValidators, maxYield)
        );
        module = OctantRewardsSafe(payable(temps.module));
    }

    function testCheckModuleInitialization() public view {
        assertTrue(module.owner() == temps.safe);
        assertTrue(module.keeper() == keeper);
        assertTrue(module.treasury() == treasury);
        assertTrue(module.dragonRouter() == dragonRouter);
        assertTrue(module.totalValidators() == totalValidators);
    }

    function testOnlyKeeperCanConfirmNewValidators() public {
        uint256 amount = 2;

        vm.startPrank(temps.safe);

        // Fails if 0 is passed
        vm.expectRevert(abi.encodeWithSelector(OctantRewardsSafe__InvalidNumberOfValidators.selector, 0));
        module.requestNewValidators(0);

        module.requestNewValidators(amount);

        vm.stopPrank();

        vm.expectRevert();
        module.confirmNewValidators();

        vm.startPrank(keeper);
        module.confirmNewValidators();
        assertTrue(module.totalValidators() == totalValidators + amount);

        // fails when newValidators == 0
        vm.expectRevert(abi.encodeWithSelector(OctantRewardsSafe__InvalidNumberOfValidators.selector, 0));
        module.confirmNewValidators();

        vm.stopPrank();
    }

    function testOnlyOwnerCanSetTreasury() public {
        address newTreasury = _randomAddress();

        vm.expectRevert();
        module.setTreasury(newTreasury);

        vm.startPrank(temps.safe);

        // fails if zero address is passed.
        vm.expectRevert(abi.encodeWithSelector(OctantRewardsSafe__InvalidAddress.selector, address(0)));
        module.setTreasury(address(0));

        module.setTreasury(newTreasury);
        assertTrue(module.treasury() == newTreasury);

        vm.stopPrank();
    }

    function testOnlyOwnerCanSetDragonRouter() public {
        address newDragonRouter = _randomAddress();

        vm.expectRevert();
        module.setDragonRouter(newDragonRouter);

        vm.startPrank(temps.safe);

        // fails if zero address is passed.
        vm.expectRevert(abi.encodeWithSelector(OctantRewardsSafe__InvalidAddress.selector, address(0)));
        module.setDragonRouter(address(0));

        module.setDragonRouter(newDragonRouter);
        assertTrue(module.dragonRouter() == newDragonRouter);

        vm.stopPrank();
    }

    function testOnlyOwnerCanSetMaxYield() public {
        uint256 _newMaxYield = 3 ether;
        vm.expectRevert();
        module.setMaxYield(_newMaxYield);

        vm.startPrank(temps.safe);

        // fails if max yield not in range
        vm.expectRevert(abi.encodeWithSelector(OctantRewardsSafe__InvalidMaxYield.selector, 0));
        module.setMaxYield(0);

        module.setMaxYield(_newMaxYield);
        assertTrue(module.maxYield() == _newMaxYield);

        vm.stopPrank();
    }

    function testExitValidators() public {
        uint256 exitedValidators = 1;

        vm.startPrank(temps.safe);

        // Fails if 0 is passed
        vm.expectRevert(abi.encodeWithSelector(OctantRewardsSafe__InvalidNumberOfValidators.selector, 0));
        module.requestExitValidators(0);

        module.requestExitValidators(exitedValidators);

        vm.stopPrank();

        // can only be called by keeper
        vm.expectRevert();
        module.confirmExitValidators();

        /// confirmExitValidators Fails if execTransactionFromModule returns false
        FailSafe failSafe = new FailSafe();
        vm.prank(temps.safe);
        module.setTarget(address(failSafe));
        vm.deal(temps.safe, exitedValidators * 32 ether); // send yield to safe
        vm.expectRevert(
            abi.encodeWithSelector(OctantRewardsSafe__TransferFailed.selector, exitedValidators * 32 ether)
        );
        vm.prank(keeper);
        module.confirmExitValidators();
        vm.prank(temps.safe);
        module.setTarget(temps.safe);

        vm.startPrank(keeper);

        assertTrue(treasury.balance == 0);
        vm.deal(temps.safe, exitedValidators * 32 ether); // send yield to safe
        module.confirmExitValidators();
        assertTrue(module.totalValidators() == (totalValidators - exitedValidators));
        assertTrue(treasury.balance == exitedValidators * 32 ether);

        // keeper cannot call confirmExitValidators when exitedValidators = 0
        vm.expectRevert(abi.encodeWithSelector(OctantRewardsSafe__InvalidNumberOfValidators.selector, 0));
        module.confirmExitValidators();

        vm.stopPrank();
    }

    function testHarvest() public {
        uint256 yield = 1 ether;

        /// Harvest fails when Yield > Max Yield
        vm.deal(temps.safe, maxYield + 1 ether); // send yield to safe
        vm.expectRevert(
            abi.encodeWithSelector(OctantRewardsSafe__YieldNotInRange.selector, maxYield + 1 ether, maxYield)
        );
        module.harvest();

        /// Harvest works when Yield < Max Yield
        vm.deal(temps.safe, yield); // send yield to safe
        assertTrue(dragonRouter.balance == 0);
        module.harvest();
        assertTrue(dragonRouter.balance == yield);

        /// Harvest Fails if execTransactionFromModule returns false
        FailSafe failSafe = new FailSafe();
        vm.prank(temps.safe);
        module.setTarget(address(failSafe));
        vm.deal(temps.safe, yield); // send yield to safe
        vm.expectRevert(abi.encodeWithSelector(OctantRewardsSafe__TransferFailed.selector, yield));
        module.harvest();
    }
}
