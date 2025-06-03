// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { PaymentSplitterFactory } from "src/factories/PaymentSplitterFactory.sol";
import { PaymentSplitter } from "src/core/PaymentSplitter.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract PaymentSplitterFactoryTest is Test {
    PaymentSplitterFactory public factory;
    MockERC20 public token;

    // Test accounts
    address payable public alice = payable(address(0x1));
    address payable public bob = payable(address(0x2));
    address payable public charlie = payable(address(0x3));

    uint256 public constant INITIAL_ETH_AMOUNT = 100 ether;
    uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;

    function setUp() public {
        // Setup test accounts with ETH
        vm.deal(alice, INITIAL_ETH_AMOUNT);
        vm.deal(bob, INITIAL_ETH_AMOUNT);
        vm.deal(charlie, INITIAL_ETH_AMOUNT);
        vm.deal(address(this), INITIAL_ETH_AMOUNT);

        // Create mock ERC20 token for testing
        token = new MockERC20(18);
        token.mint(address(this), INITIAL_TOKEN_AMOUNT);

        // Deploy factory
        factory = new PaymentSplitterFactory();
    }

    // Test creating a PaymentSplitter without ETH
    function testCreatePaymentSplitter() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";
        payeeNames[2] = "OpEx";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Create PaymentSplitter and capture events
        vm.recordLogs();
        address splitterAddress = factory.createPaymentSplitter(payees, payeeNames, shares);

        // Verify splitter was created
        assertTrue(splitterAddress != address(0));

        // Check the PaymentSplitter state
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.payee(0), alice);
        assertEq(splitter.payee(1), bob);
        assertEq(splitter.payee(2), charlie);
        assertEq(splitter.shares(alice), 50);
        assertEq(splitter.shares(bob), 30);
        assertEq(splitter.shares(charlie), 20);

        // Verify splitter has no ETH
        assertEq(address(splitter).balance, 0);
    }

    // Test creating a PaymentSplitter with ETH
    function testCreatePaymentSplitterWithETH() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";
        payeeNames[2] = "OpEx";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        uint256 ethAmount = 10 ether;

        // Create PaymentSplitter and capture events
        vm.recordLogs();
        address splitterAddress = factory.createPaymentSplitterWithETH{ value: ethAmount }(payees, payeeNames, shares);

        // Verify splitter was created
        assertTrue(splitterAddress != address(0));

        // Check the PaymentSplitter state
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.payee(0), alice);
        assertEq(splitter.payee(1), bob);
        assertEq(splitter.payee(2), charlie);
        assertEq(splitter.shares(alice), 50);
        assertEq(splitter.shares(bob), 30);
        assertEq(splitter.shares(charlie), 20);

        // Verify splitter received ETH
        assertEq(address(splitter).balance, ethAmount);

        // Calculate expected amounts
        uint256 aliceExpected = (ethAmount * 50) / 100;
        uint256 bobExpected = (ethAmount * 30) / 100;
        uint256 charlieExpected = (ethAmount * 20) / 100;

        // Check releasable amounts
        assertEq(splitter.releasable(alice), aliceExpected);
        assertEq(splitter.releasable(bob), bobExpected);
        assertEq(splitter.releasable(charlie), charlieExpected);
    }

    // Test releasing ETH from a created PaymentSplitter
    function testReleaseFromCreatedSplitter() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";
        payeeNames[2] = "OpEx";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        uint256 ethAmount = 10 ether;

        // Create PaymentSplitter with ETH
        address splitterAddress = factory.createPaymentSplitterWithETH{ value: ethAmount }(payees, payeeNames, shares);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Release to Alice
        uint256 aliceExpected = (ethAmount * 50) / 100;
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice); // Alice calls release
        splitter.release(alice);

        assertEq(alice.balance, aliceBalanceBefore + aliceExpected);
        assertEq(splitter.releasable(alice), 0);
        assertEq(splitter.released(alice), aliceExpected);
    }

    // Test PaymentSplitterFactory with ERC20 tokens
    function testWithERC20Tokens() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";
        payeeNames[2] = "OpEx";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Create PaymentSplitter
        address splitterAddress = factory.createPaymentSplitter(payees, payeeNames, shares);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Send tokens to the splitter
        uint256 tokenAmount = 100e18;
        token.transfer(address(splitter), tokenAmount);

        // Check token balances in the splitter
        assertEq(token.balanceOf(address(splitter)), tokenAmount);

        // Calculate expected amounts
        uint256 aliceExpected = (tokenAmount * 50) / 100;
        uint256 bobExpected = (tokenAmount * 30) / 100;
        uint256 charlieExpected = (tokenAmount * 20) / 100;

        // Check releasable amounts
        assertEq(splitter.releasable(IERC20(address(token)), alice), aliceExpected);
        assertEq(splitter.releasable(IERC20(address(token)), bob), bobExpected);
        assertEq(splitter.releasable(IERC20(address(token)), charlie), charlieExpected);

        // Release tokens to Alice
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        splitter.release(IERC20(address(token)), alice);
        assertEq(token.balanceOf(alice), aliceBalanceBefore + aliceExpected);
    }

    // Test invalid input to PaymentSplitter through factory
    function testInvalidInputToFactory() public {
        // Prepare invalid payees (empty array)
        address[] memory emptyPayees = new address[](0);
        string[] memory emptyNames = new string[](0);
        uint256[] memory emptyShares = new uint256[](0);

        // Expect revert
        vm.expectRevert("PaymentSplitterFactory: initialization failed");
        factory.createPaymentSplitter(emptyPayees, emptyNames, emptyShares);

        // Prepare invalid payees (mismatched arrays)
        address[] memory payees = new address[](2);
        payees[0] = alice;
        payees[1] = bob;

        string[] memory payeeNames = new string[](2);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Expect revert
        vm.expectRevert("PaymentSplitterFactory: length mismatch");
        factory.createPaymentSplitter(payees, payeeNames, shares);
    }

    // Test edge cases
    function testEdgeCases() public {
        // Single payee case
        address[] memory singlePayee = new address[](1);
        singlePayee[0] = alice;

        string[] memory singleName = new string[](1);
        singleName[0] = "GrantRoundOperator";

        uint256[] memory singleShare = new uint256[](1);
        singleShare[0] = 100;

        // Create PaymentSplitter with a single payee
        address splitterAddress = factory.createPaymentSplitter(singlePayee, singleName, singleShare);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Verify splitter state
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.payee(0), alice);
        assertEq(splitter.shares(alice), 100);

        // Many payees case (testing with 10)
        address[] memory manyPayees = new address[](10);
        string[] memory manyNames = new string[](10);
        uint256[] memory manyShares = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            // Create unique addresses
            manyPayees[i] = address(uint160(0x100 + i));
            manyNames[i] = string(abi.encodePacked("Payee", i));
            manyShares[i] = 10; // Equal shares
        }

        // Create PaymentSplitter with many payees
        address manySplitterAddress = factory.createPaymentSplitter(manyPayees, manyNames, manyShares);
        PaymentSplitter manySplitter = PaymentSplitter(payable(manySplitterAddress));

        // Verify splitter state
        assertEq(manySplitter.totalShares(), 100);

        for (uint256 i = 0; i < 10; i++) {
            assertEq(manySplitter.payee(i), manyPayees[i]);
            assertEq(manySplitter.shares(manyPayees[i]), 10);
        }
    }

    // Helper function for receiving ETH
    receive() external payable {}
}
