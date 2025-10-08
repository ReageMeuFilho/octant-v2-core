// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { AntiLoopholeGuard } from "src/zodiac-core/guards/antiLoopHoleGuard.sol";

contract AntiLoopholeGuardTest is Test {
    function testConstructorInitializesOwnership() external {
        address owner = address(0xBEEF);
        uint256 start = block.timestamp;

        AntiLoopholeGuard guard = new AntiLoopholeGuard(owner);

        assertEq(guard.owner(), owner);
        assertEq(guard.lockEndTime(), start + guard.LOCK_DURATION());
        assertFalse(guard.isDisabled());
    }

    function testSetUpInitializesOwnership() external {
        AntiLoopholeGuard implementation = new AntiLoopholeGuard(address(this));
        address owner = address(0xCAFE);
        uint256 start = block.timestamp;

        address clone = Clones.clone(address(implementation));
        AntiLoopholeGuard(clone).setUp(abi.encode(owner));

        assertEq(AntiLoopholeGuard(clone).owner(), owner);
        assertEq(AntiLoopholeGuard(clone).lockEndTime(), start + AntiLoopholeGuard(clone).LOCK_DURATION());
        assertFalse(AntiLoopholeGuard(clone).isDisabled());
    }
}
