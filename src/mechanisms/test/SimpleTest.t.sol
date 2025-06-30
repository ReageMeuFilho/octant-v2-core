// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract SimpleTest is Test {
    function testFactoryDeployment() public {
        AllocationMechanismFactory factory = new AllocationMechanismFactory();
        assertNotEq(factory.tokenizedAllocationImplementation(), address(0));
    }

    function testTokenizedAllocationDeployment() public {
        TokenizedAllocationMechanism impl = new TokenizedAllocationMechanism();
        assertNotEq(address(impl), address(0));
    }
}
