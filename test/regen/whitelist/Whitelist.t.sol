// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { Whitelist } from "../../../src/regen/whitelist/Whitelist.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol"; // For OwnableUnauthorizedAccount error

contract WhitelistTest is Test {
    Whitelist whitelist;
    address owner;
    address user1;
    address user2;
    address user3;
    address nonOwner;

    function setUp() public {
        address intendedOwner = makeAddr("intendedOwner"); // Create a dedicated address for ownership
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        nonOwner = makeAddr("nonOwner");

        vm.prank(intendedOwner); // Prank as the intended owner for the deployment
        whitelist = new Whitelist();

        owner = intendedOwner; // Assign the 'owner' variable to the actual owner of the whitelist
    }

    // --- Constructor & Ownership Tests ---
    function test_Constructor_SetsOwnerCorrectly() public view {
        assertEq(whitelist.owner(), owner, "Owner should be the intendedOwner");
    }

    // --- isWhitelisted Tests ---
    function test_IsWhitelisted_InitiallyFalse() public view {
        assertFalse(whitelist.isWhitelisted(user1), "User1 should not be whitelisted initially");
        assertFalse(whitelist.isWhitelisted(address(0)), "Address(0) should not be whitelisted initially");
    }

    // --- addToWhitelist Tests ---
    function test_AddToWhitelist_SingleAccount() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.prank(owner);
        whitelist.addToWhitelist(accounts);

        assertTrue(whitelist.isWhitelisted(user1), "User1 should be whitelisted after adding");
        assertFalse(whitelist.isWhitelisted(user2), "User2 should still not be whitelisted");
    }

    function test_AddToWhitelist_MultipleAccounts() public {
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        vm.prank(owner);
        whitelist.addToWhitelist(accounts);

        assertTrue(whitelist.isWhitelisted(user1), "User1 should be whitelisted");
        assertTrue(whitelist.isWhitelisted(user2), "User2 should be whitelisted");
        assertFalse(whitelist.isWhitelisted(user3), "User3 should not be whitelisted");
    }

    function test_AddToWhitelist_EmptyList() public {
        address[] memory accounts = new address[](0);

        vm.prank(owner);
        whitelist.addToWhitelist(accounts); // Should not revert

        assertFalse(whitelist.isWhitelisted(user1), "No user should be whitelisted after adding empty list");
    }

    function test_AddToWhitelist_AddAddressZero() public {
        address[] memory accounts = new address[](1);
        accounts[0] = address(0);

        vm.prank(owner);
        whitelist.addToWhitelist(accounts);
        assertTrue(whitelist.isWhitelisted(address(0)), "Address(0) should be whitelisteable");
    }

    function test_AddToWhitelist_AlreadyWhitelisted() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.startPrank(owner);
        whitelist.addToWhitelist(accounts); // Add once
        assertTrue(whitelist.isWhitelisted(user1));

        whitelist.addToWhitelist(accounts); // Add again
        assertTrue(whitelist.isWhitelisted(user1), "User1 should remain whitelisted after adding again");
        vm.stopPrank();
    }

    function test_RevertIf_AddToWhitelist_NotOwner() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        whitelist.addToWhitelist(accounts);
        vm.stopPrank();
    }

    // --- removeFromWhitelist Tests ---
    function test_RemoveFromWhitelist_SingleAccount() public {
        address[] memory addAccounts = new address[](1);
        addAccounts[0] = user1;
        vm.startPrank(owner);
        whitelist.addToWhitelist(addAccounts);
        assertTrue(whitelist.isWhitelisted(user1));

        address[] memory removeAccounts = new address[](1);
        removeAccounts[0] = user1;
        whitelist.removeFromWhitelist(removeAccounts);

        assertFalse(whitelist.isWhitelisted(user1), "User1 should not be whitelisted after removal");
        vm.stopPrank();
    }

    function test_RemoveFromWhitelist_MultipleAccounts() public {
        address[] memory addAccounts = new address[](3);
        addAccounts[0] = user1;
        addAccounts[1] = user2;
        addAccounts[2] = user3;
        vm.startPrank(owner);
        whitelist.addToWhitelist(addAccounts);
        assertTrue(whitelist.isWhitelisted(user1));
        assertTrue(whitelist.isWhitelisted(user2));
        assertTrue(whitelist.isWhitelisted(user3));

        address[] memory removeAccounts = new address[](2);
        removeAccounts[0] = user1;
        removeAccounts[1] = user3;
        whitelist.removeFromWhitelist(removeAccounts);

        assertFalse(whitelist.isWhitelisted(user1), "User1 should be removed");
        assertTrue(whitelist.isWhitelisted(user2), "User2 should remain whitelisted");
        assertFalse(whitelist.isWhitelisted(user3), "User3 should be removed");
        vm.stopPrank();
    }

    function test_RemoveFromWhitelist_EmptyList() public {
        address[] memory addAccounts = new address[](1);
        addAccounts[0] = user1;
        vm.startPrank(owner);
        whitelist.addToWhitelist(addAccounts);
        assertTrue(whitelist.isWhitelisted(user1));

        address[] memory removeAccounts = new address[](0);
        whitelist.removeFromWhitelist(removeAccounts); // Should not revert

        assertTrue(whitelist.isWhitelisted(user1), "User1 should still be whitelisted after removing empty list");
        vm.stopPrank();
    }

    function test_RemoveFromWhitelist_AddressZero() public {
        address[] memory addAccounts = new address[](1);
        addAccounts[0] = address(0);
        vm.startPrank(owner);
        whitelist.addToWhitelist(addAccounts);
        assertTrue(whitelist.isWhitelisted(address(0)), "Address(0) should be whitelisted");

        address[] memory removeAccounts = new address[](1);
        removeAccounts[0] = address(0);
        whitelist.removeFromWhitelist(removeAccounts);
        assertFalse(whitelist.isWhitelisted(address(0)), "Address(0) should be removable");
        vm.stopPrank();
    }

    function test_RemoveFromWhitelist_AccountNotWhitelisted() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1; // user1 is not whitelisted yet

        vm.prank(owner);
        whitelist.removeFromWhitelist(accounts); // Should not revert

        assertFalse(whitelist.isWhitelisted(user1), "User1 should remain not whitelisted");
    }

    function test_RevertIf_RemoveFromWhitelist_NotOwner() public {
        address[] memory addAccounts = new address[](1);
        addAccounts[0] = user1;
        vm.startPrank(owner); // owner adds user1
        whitelist.addToWhitelist(addAccounts);
        vm.stopPrank(); // Stop owner prank before starting nonOwner prank

        address[] memory removeAccounts = new address[](1);
        removeAccounts[0] = user1;

        vm.startPrank(nonOwner); // nonOwner tries to remove
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        whitelist.removeFromWhitelist(removeAccounts);
        vm.stopPrank();

        vm.prank(owner); // Verify user1 still whitelisted as owner didn't remove
        assertTrue(whitelist.isWhitelisted(user1), "User1 should still be whitelisted as non-owner failed to remove");
    }
}
