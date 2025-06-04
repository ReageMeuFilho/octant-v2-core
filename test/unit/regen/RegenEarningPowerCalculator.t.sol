// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "src/regen/interfaces/IWhitelistedEarningPowerCalculator.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract RegenEarningPowerCalculatorTest is Test {
    RegenEarningPowerCalculator calculator;
    Whitelist whitelist;
    address owner;
    address staker1;
    address staker2;
    address nonOwner;

    function setUp() public {
        owner = makeAddr("owner");
        staker1 = makeAddr("staker1");
        staker2 = makeAddr("staker2");
        nonOwner = makeAddr("nonOwner");

        vm.startPrank(owner);
        whitelist = new Whitelist();
        calculator = new RegenEarningPowerCalculator(owner, whitelist);
        vm.stopPrank();
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(calculator.owner(), owner, "Owner should be set correctly");
    }

    function test_Constructor_SetsInitialWhitelist() public view {
        assertEq(address(calculator.whitelist()), address(whitelist), "Initial whitelist should be set");
    }

    function test_Constructor_EmitsWhitelistSet() public {
        Whitelist localTestWhitelist = new Whitelist();

        vm.expectEmit();
        emit IWhitelistedEarningPowerCalculator.WhitelistSet(localTestWhitelist);

        vm.prank(owner);
        new RegenEarningPowerCalculator(owner, localTestWhitelist);
    }

    function test_SupportsInterface_IWhitelistedEarningPowerCalculator() public view {
        assertTrue(calculator.supportsInterface(type(IWhitelistedEarningPowerCalculator).interfaceId));
    }

    function test_SupportsInterface_IERC165() public view {
        assertTrue(calculator.supportsInterface(type(IERC165).interfaceId));
    }

    function testFuzz_GetEarningPower_WhitelistDisabled(uint256 stakedAmount) public {
        vm.prank(owner);
        calculator.setWhitelist(IWhitelist(address(0))); // Disable whitelist

        uint256 earningPower = calculator.getEarningPower(stakedAmount, staker1, address(0));
        if (stakedAmount > type(uint96).max) {
            assertEq(earningPower, type(uint96).max, "EP should be capped at uint96 max");
        } else {
            assertEq(earningPower, stakedAmount, "EP should be stakedAmount when whitelist disabled");
        }
    }

    function testFuzz_GetEarningPower_UserWhitelisted(uint256 stakedAmount) public {
        vm.prank(owner);
        whitelist.addToWhitelist(staker1);

        uint256 earningPower = calculator.getEarningPower(stakedAmount, staker1, address(0));
        if (stakedAmount > type(uint96).max) {
            assertEq(earningPower, type(uint96).max, "EP should be capped at uint96 max");
        } else {
            assertEq(earningPower, stakedAmount, "EP should be stakedAmount for whitelisted user");
        }
    }

    function testFuzz_GetEarningPower_UserNotWhitelisted(uint256 stakedAmount) public view {
        uint256 earningPower = calculator.getEarningPower(stakedAmount, staker1, address(0));
        assertEq(earningPower, 0);
    }

    function testFuzz_GetNewEarningPower_ChangesWhitelist(uint256 initialStakedAmount, uint256 oldEP) public {
        vm.assume(initialStakedAmount <= type(uint96).max);
        vm.assume(oldEP <= type(uint96).max);
        vm.assume(oldEP > 0); // Ensure oldEP > 0 so changing whitelist causes a change

        vm.prank(owner);
        whitelist.addToWhitelist(staker1);

        // Change calculator's whitelist to one where staker1 is NOT present
        Whitelist newEmptyWhitelist;
        vm.prank(owner);
        newEmptyWhitelist = new Whitelist();
        vm.prank(owner);
        calculator.setWhitelist(newEmptyWhitelist);

        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(
            initialStakedAmount,
            staker1,
            address(0),
            oldEP
        );
        assertEq(newEP, 0, "New EP should be 0 after changing whitelist");
        assertEq(qualifies, true, "Should qualify for bump after changing whitelist");
    }

    /// @notice Most complex test, covers almost all possible scenarios
    function testFuzz_GetNewEarningPower_StakeChange(
        uint256 newStake,
        uint256 oldEarningPower,
        bool isWhitelistEnabled,
        bool isStakerWhitelisted
    ) public {
        vm.assume(oldEarningPower <= type(uint96).max);

        // Setup whitelist state
        if (!isWhitelistEnabled) {
            vm.prank(owner);
            calculator.setWhitelist(IWhitelist(address(0)));
        } else if (isStakerWhitelisted) {
            vm.prank(owner);
            whitelist.addToWhitelist(staker1);
        }

        // Calculate expected new earning power
        uint256 expectedNewEP;
        if (!isWhitelistEnabled || isStakerWhitelisted) {
            expectedNewEP = newStake > type(uint96).max ? type(uint96).max : newStake;
        } else {
            expectedNewEP = 0; // Not whitelisted
        }
        bool expectedQualifies = expectedNewEP != oldEarningPower;

        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(newStake, staker1, address(0), oldEarningPower);

        assertEq(newEP, expectedNewEP, "New earning power mismatch");
        assertEq(qualifies, expectedQualifies, "Qualifies for bump mismatch");
    }

    function testFuzz_GetNewEarningPower_CappedAtUint96Max_BecomesEligible(uint256 stakedAmount, uint256 oldEP) public {
        vm.assume(stakedAmount > type(uint96).max);
        vm.assume(oldEP < type(uint96).max);

        vm.prank(owner);
        whitelist.addToWhitelist(staker1);

        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(stakedAmount, staker1, address(0), oldEP);
        assertEq(newEP, type(uint96).max, "New EP should be capped at uint96 max");
        assertEq(qualifies, true, "Should qualify for bump when EP increases to cap");
    }

    function test_GetNewEarningPower_CappedAtUint96Max_RemainsEligible_NoBump() public {
        vm.prank(owner);
        whitelist.addToWhitelist(staker1);

        // Old and new EP are type(uint96).max, so no significant change.
        uint256 stakedAmount = uint256(type(uint96).max) + 1000;
        uint256 oldEarningPower = type(uint96).max;

        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(
            stakedAmount,
            staker1,
            address(0),
            oldEarningPower
        );
        assertEq(newEP, type(uint96).max, "New EP should remain capped at uint96 max");
        assertEq(qualifies, false, "Should not qualify for bump when EP remains at cap");
    }

    function test_SetWhitelist_AsOwner() public {
        Whitelist newWhitelist = new Whitelist();

        vm.prank(owner);
        calculator.setWhitelist(newWhitelist);

        assertEq(address(calculator.whitelist()), address(newWhitelist), "Whitelist should be updated");
    }

    function test_SetWhitelist_EmitsWhitelistSet() public {
        Whitelist newWhitelist = new Whitelist();

        vm.expectEmit();
        emit IWhitelistedEarningPowerCalculator.WhitelistSet(newWhitelist);

        vm.prank(owner);
        calculator.setWhitelist(newWhitelist);
    }

    function testFuzz_RevertIf_SetWhitelist_NotOwner(address notOwnerAddr) public {
        vm.assume(notOwnerAddr != owner);

        Whitelist newWhitelist = new Whitelist();
        vm.startPrank(notOwnerAddr);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notOwnerAddr));
        calculator.setWhitelist(newWhitelist);
        vm.stopPrank();
    }

    function testFuzz_SetWhitelist_ToAddressZero_DisablesIt(uint256 stakedAmount) public {
        assertEq(calculator.whitelist().isWhitelisted(staker1), false, "Staker1 should not be whitelisted");

        vm.prank(owner);
        calculator.setWhitelist(IWhitelist(address(0)));
        assertEq(address(calculator.whitelist()), address(0), "Whitelist should be address(0)");

        // Verify getEarningPower reflects this (user not on any whitelist, but whitelist is disabled)
        uint256 earningPower = calculator.getEarningPower(stakedAmount, staker1, address(0));
        if (stakedAmount > type(uint96).max) {
            assertEq(earningPower, type(uint96).max, "EP should be capped at uint96 max");
        } else {
            assertEq(earningPower, stakedAmount, "EP should be stakedAmount when whitelist is address(0)");
        }
    }
}
