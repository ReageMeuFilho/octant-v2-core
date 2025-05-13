// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { RegenEarningPowerCalculator } from "../../src/regen/RegenEarningPowerCalculator.sol";
import { Whitelist } from "../../src/regen/whitelist/Whitelist.sol";
import { IWhitelist } from "../../src/regen/whitelist/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "../../src/regen/IWhitelistedEarningPowerCalculator.sol";
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

        whitelist = new Whitelist();
        vm.prank(owner);
        calculator = new RegenEarningPowerCalculator(owner, whitelist);
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(calculator.owner(), owner, "Owner should be set correctly");
    }

    function test_Constructor_SetsInitialWhitelist() public view {
        assertEq(address(calculator.whitelist()), address(whitelist), "Initial whitelist should be set");
    }

    function test_Constructor_EmitsWhitelistSet() public {
        Whitelist localTestWhitelist = new Whitelist(); // Create a local whitelist for this test

        vm.expectEmit(true, true, false, false); // Check 1st indexed arg (previousOwner), 2nd indexed arg (newOwner), no 3rd indexed arg, no data args.
        emit Ownable.OwnershipTransferred(address(0), owner); // Provides expected values for previousOwner and newOwner.

        vm.expectEmit(false, false, false, true); // No indexed event arguments to check, check data argument.
        emit IWhitelistedEarningPowerCalculator.WhitelistSet(localTestWhitelist); // Provides expected value for the `whitelist` data argument.

        // Action: Deploy a new calculator using the local whitelist.
        // This call will emit the two events above.
        vm.prank(owner);
        new RegenEarningPowerCalculator(owner, localTestWhitelist);
    }

    function test_SupportsInterface_IWhitelistedEarningPowerCalculator() public view {
        assertTrue(calculator.supportsInterface(type(IWhitelistedEarningPowerCalculator).interfaceId));
    }

    function test_SupportsInterface_IERC165() public view {
        assertTrue(calculator.supportsInterface(type(IERC165).interfaceId));
    }

    function test_GetEarningPower_WhitelistDisabled() public {
        vm.prank(owner);
        calculator.setWhitelist(IWhitelist(address(0))); // Disable whitelist

        uint256 stakedAmount = 100e18;
        uint256 earningPower = calculator.getEarningPower(stakedAmount, staker1, address(0));
        assertEq(earningPower, stakedAmount, "EP should be stakedAmount when whitelist disabled");
    }

    function test_GetEarningPower_UserWhitelisted() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);

        uint256 stakedAmount = 100e18;
        uint256 earningPower = calculator.getEarningPower(stakedAmount, staker1, address(0));
        assertEq(earningPower, stakedAmount, "EP should be stakedAmount for whitelisted user");
    }

    function test_GetEarningPower_UserNotWhitelisted() public view {
        // staker1 is NOT on default whitelist
        uint256 stakedAmount = 100e18;
        uint256 earningPower = calculator.getEarningPower(stakedAmount, staker1, address(0));
        assertEq(earningPower, 0, "EP should be 0 for non-whitelisted user");
    }

    function test_GetEarningPower_CappedAtUint96Max() public {
        vm.prank(owner);
        calculator.setWhitelist(IWhitelist(address(0))); // Disable whitelist to focus on capping

        uint256 stakedAmount = uint256(type(uint96).max) + 1000;
        uint256 earningPower = calculator.getEarningPower(stakedAmount, staker1, address(0));
        assertEq(earningPower, type(uint96).max, "EP should be capped at uint96.max");

        uint256 stakedAmountExactlyMax = type(uint96).max;
        earningPower = calculator.getEarningPower(stakedAmountExactlyMax, staker1, address(0));
        assertEq(earningPower, type(uint96).max, "EP should be uint96.max if staked is uint96.max");
    }

    function test_GetNewEarningPower_BecomesWhitelisted() public {
        // staker1 initially not whitelisted (calculator.whitelist is empty for staker1), oldEP=0
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users); // Now staker1 is whitelisted on calculator.whitelist

        _checkNewEarningPower(100e18, staker1, 0, 100e18, true, "BecomesWhitelisted");
    }

    function test_GetNewEarningPower_LosesWhitelist() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users); // staker1 is on the 'whitelist' instance used by calculator

        uint256 initialStakedAmount = 100e18;
        uint256 oldEP = 100e18; // Assumed EP when staker1 was whitelisted

        // Change calculator's whitelist to one where staker1 is NOT present
        Whitelist newEmptyWhitelist = new Whitelist();
        vm.prank(owner);
        calculator.setWhitelist(newEmptyWhitelist);

        _checkNewEarningPower(initialStakedAmount, staker1, oldEP, 0, true, "LosesWhitelist");
    }

    function test_GetNewEarningPower_StakeDoubled_Whitelisted() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);
        _checkNewEarningPower(200e18, staker1, 100e18, 200e18, true, "StakeDoubled_Whitelisted");
    }

    function test_GetNewEarningPower_StakeHalved_Whitelisted() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);
        _checkNewEarningPower(50e18, staker1, 100e18, 50e18, true, "StakeHalved_Whitelisted");
    }

    function test_GetNewEarningPower_StakeSignificantlyDecreased_Whitelisted() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);
        // newEP * 2 (80e18) <= oldEP (100e18) is true
        _checkNewEarningPower(40e18, staker1, 100e18, 40e18, true, "StakeSignificantlyDecreased_Whitelisted");
    }

    function test_GetNewEarningPower_SmallChange_NoBump_Whitelisted() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);
        _checkNewEarningPower(110e18, staker1, 100e18, 110e18, false, "SmallIncrease_NoBump_Whitelisted");
        _checkNewEarningPower(90e18, staker1, 100e18, 90e18, false, "SmallDecrease_NoBump_Whitelisted");
    }

    function test_GetNewEarningPower_NoChange_NoBump_Whitelisted() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);
        _checkNewEarningPower(100e18, staker1, 100e18, 100e18, false, "NoChange_NoBump_Whitelisted");
    }

    function test_GetNewEarningPower_StakeBecomesZero_Whitelisted() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);
        // oldEP > 0, newEP == 0 -> qualifies
        _checkNewEarningPower(0, staker1, 100e18, 0, true, "StakeBecomesZero_Whitelisted");
    }

    function test_GetNewEarningPower_StakeFromZero_Whitelisted() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);
        // oldEP == 0, newEP > 0 -> qualifies
        _checkNewEarningPower(100e18, staker1, 0, 100e18, true, "StakeFromZero_Whitelisted");
    }

    function test_GetNewEarningPower_WhitelistDisabled_StakeDoubled() public {
        vm.prank(owner);
        calculator.setWhitelist(IWhitelist(address(0)));
        _checkNewEarningPower(200e18, staker1, 100e18, 200e18, true, "WhitelistDisabled_StakeDoubled");
    }

    function test_GetNewEarningPower_WhitelistDisabled_SmallChangeNoBump() public {
        vm.prank(owner);
        calculator.setWhitelist(IWhitelist(address(0)));
        _checkNewEarningPower(110e18, staker1, 100e18, 110e18, false, "WhitelistDisabled_SmallChangeNoBump");
    }

    function test_GetNewEarningPower_CappedAtUint96Max_BecomesEligible() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);
        _checkNewEarningPower(
            uint256(type(uint96).max) + 1000,
            staker1,
            10e18,
            type(uint96).max,
            true,
            "CappedAtUint96Max_BecomesEligible"
        );
    }

    function test_GetNewEarningPower_CappedAtUint96Max_RemainsEligible_NoBump() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        whitelist.addToWhitelist(users);
        // oldEP was type(uint96).max, newEP is type(uint96).max. No significant change.
        _checkNewEarningPower(
            uint256(type(uint96).max) + 1000,
            staker1,
            type(uint96).max,
            type(uint96).max,
            false,
            "CappedAtUint96Max_RemainsEligible_NoBump"
        );
    }

    function test_GetNewEarningPower_BothZero_NoBump() public {
        address[] memory users = new address[](1);
        users[0] = staker1;
        // staker1 is NOT added to whitelist, so newEP will be 0 if whitelist is active
        // oldEP is 0
        _checkNewEarningPower(0, staker1, 0, 0, false, "BothZero_NoBump_NotWhitelisted");

        whitelist.addToWhitelist(users); // Now staker1 is whitelisted
        _checkNewEarningPower(0, staker1, 0, 0, false, "BothZero_NoBump_Whitelisted_StakeZero");
    }

    function test_SetWhitelist_AsOwner() public {
        Whitelist newWhitelist = new Whitelist();
        vm.prank(owner);

        vm.expectEmit(false, false, false, true, address(calculator));
        emit IWhitelistedEarningPowerCalculator.WhitelistSet(newWhitelist); // Event from IWhitelistedEarningPowerCalculator
        calculator.setWhitelist(newWhitelist);

        assertEq(address(calculator.whitelist()), address(newWhitelist), "Whitelist should be updated");
    }

    function test_RevertIf_SetWhitelist_NotOwner() public {
        Whitelist newWhitelist = new Whitelist();
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        calculator.setWhitelist(newWhitelist);
        vm.stopPrank();
    }

    function test_SetWhitelist_ToAddressZero_DisablesIt() public {
        vm.prank(owner);

        vm.expectEmit(false, false, false, true, address(calculator));
        emit IWhitelistedEarningPowerCalculator.WhitelistSet(IWhitelist(address(0)));
        calculator.setWhitelist(IWhitelist(address(0)));

        assertEq(address(calculator.whitelist()), address(0), "Whitelist should be address(0)");

        // Verify getEarningPower reflects this (user not on any whitelist, but whitelist is disabled)
        uint256 stakedAmount = 100e18;
        uint256 earningPower = calculator.getEarningPower(stakedAmount, staker1, address(0));
        assertEq(earningPower, stakedAmount, "EP should be stakedAmount when whitelist is address(0)");
    }

    // Helper for getNewEarningPower tests
    function _checkNewEarningPower(
        uint256 stakedAmount,
        address stakerAddr,
        uint256 oldEP,
        uint256 expectedNewEP,
        bool expectedQualifiesForBump,
        string memory reason // Added reason for better error messages
    ) internal view {
        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(stakedAmount, stakerAddr, address(0), oldEP);
        assertEq(newEP, expectedNewEP, string(abi.encodePacked("New EP mismatch: ", reason)));
        assertEq(qualifies, expectedQualifiesForBump, string(abi.encodePacked("QualifiesForBump mismatch: ", reason)));
    }
}
