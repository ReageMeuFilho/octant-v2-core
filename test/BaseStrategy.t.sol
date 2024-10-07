// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";
import { MockStrategy } from "./mocks/MockStrategy.sol";
import { MockYieldSource } from "./mocks/MockYieldSource.sol";
import { MockTokenizedStrategy } from "./mocks/MockTokenizedStrategy.sol";

contract BaseStrategyTest is BaseTest {
    address keeper = makeAddr("keeper");
    address treasury = makeAddr("treasury");
    address dragonRouter = makeAddr("dragonRouter");
    address management = makeAddr("management");
    uint256 totalValidators = 2;
    uint256 maxYield = 31 ether;

    testTemps temps;
    MockStrategy moduleImplementation;
    MockStrategy module;
    MockYieldSource yieldSource;
    MockTokenizedStrategy tokenizedStrategyImplementation;

    string public name = "Test Mock Strategy";
    uint256 public maxReportDelay = 9;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // using this address to represent native ETH

    function setUp() public override {
        super.setUp();
        moduleImplementation = new MockStrategy();
        yieldSource = new MockYieldSource(ETH);
        tokenizedStrategyImplementation = new MockTokenizedStrategy();
        temps = _testTemps(
            address(moduleImplementation),
            abi.encode(address(tokenizedStrategyImplementation), ETH, address(yieldSource), management, keeper, dragonRouter, maxReportDelay, name)
        );
        module = MockStrategy(payable(temps.module));
    }

    function testInitialize() public {}
}
