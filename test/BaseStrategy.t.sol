// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";
import { OctantRewardsSafe } from "../src/dragons/modules/OctantRewardsSafe.sol";
import { MockStrategy } from "./mocks/MockStrategy.sol";

contract BaseStrategyTest is BaseTest {
    address keeper = makeAddr("keeper");
    address treasury = makeAddr("treasury");
    address dragonRouter = makeAddr("dragonRouter");
    uint256 totalValidators = 2;
    uint256 maxYield = 31 ether;

    testTemps temps;
    MockStrategy moduleImplementation;
    MockStrategy module;

    function setUp() public override {
        super.setUp();
        moduleImplementation = new MockStrategy();
        temps = _testTemps(
            address(moduleImplementation),
            abi.encode(keeper, treasury, dragonRouter, totalValidators, maxYield)
        );
        module = MockStrategy(payable(temps.module));
    }
}
