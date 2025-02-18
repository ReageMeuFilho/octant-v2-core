// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SetupIntegrationTest} from "../Setup.t.sol";
import {NonfungibleDepositManager} from "src/dragons/eth2StakeVault/NonfungibleDepositManager.sol";
import {Vm} from "forge-std/Vm.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
contract ETH2StakeVaultTest is SetupIntegrationTest {
    
    // Test validator credentials - updated to exact lengths
    bytes constant TEST_PUBKEY = hex"888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888";
    // 48 bytes = 96 hex characters

    bytes constant TEST_SIGNATURE = hex"999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999";
    // 96 bytes = 192 hex characters

    bytes32 constant TEST_DEPOSIT_DATA_ROOT = 0x05c366b194111d28ec5e31077441b7478ceb7281cbce615d74084bcfead9f845;

    address public constant DEPOSIT_CONTRACT_ADDRESS = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    // Test events
    event DepositRequested(uint256 indexed tokenId, address indexed depositManager, address indexed withdrawalAddress);
    event ValidatorAssigned(uint256 indexed tokenId, address indexed operator, bytes pubkey);
    event ValidatorConfirmed(uint256 indexed tokenId, address indexed withdrawalAddress, bytes32 depositDataRoot);
    event ValidatorIssued(uint256 indexed tokenId, address indexed operator);
    
    address depositor;

    function setUp() public override {
        super.setUp();

        // Add depositor to setup for use across all tests
        depositor = makeAddr("depositor");
        vm.deal(depositor, 100 ether); // Fund with enough ETH for multiple tests

        // Label addresses for better trace output
        vm.label(DEPOSIT_CONTRACT_ADDRESS, "ETH2DepositContract");
    }

    function test_FullDepositLifecycle() public {
        address withdrawalAddress = makeAddr("withdrawalAddress");
        address operator = makeAddr("operator");
        
        // Request deposit

        vm.startPrank(depositor);
        uint256 tokenId = nonfungibleDepositManager.requestDeposit{value: 32 ether}(withdrawalAddress);
        vm.stopPrank();
        
        // Verify deposit request state
        assertEq(nonfungibleDepositManager.totalDeposits(), 32 ether, "Total deposits not updated");
        assertEq(address(nonfungibleDepositManager).balance, 32 ether, "Contract balance incorrect");
        assertEq(nonfungibleDepositManager.ownerOf(tokenId), depositor, "NFT not minted to depositor");
        
        // Check deposit info
        (
            NonfungibleDepositManager.DepositState state,
            address storedWithdrawalAddress,
            ,,,,,
        ) = nonfungibleDepositManager.deposits(tokenId);
        
        assertEq(uint256(state), uint256(NonfungibleDepositManager.DepositState.Requested), "Wrong state");
        assertEq(storedWithdrawalAddress, withdrawalAddress, "Wrong withdrawal address");

        // 2. Assign Validator
        vm.startPrank(deployer);
        nonfungibleDepositManager.setOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectEmit(true, true, true, true);
        emit ValidatorAssigned(tokenId, operator, TEST_PUBKEY);
        
        nonfungibleDepositManager.assignValidator(tokenId, TEST_PUBKEY, TEST_SIGNATURE);
        vm.stopPrank();

        address assignedOperator;
        (state,/*withdrawalAddress*/,/*withdrawalCredentials*/,/*pubkey*/,/*signature*/,/*depositDataRoot*/, assignedOperator,/*confirmedTimestamp*/) = nonfungibleDepositManager.deposits(tokenId);
        assertEq(uint256(state), uint256(NonfungibleDepositManager.DepositState.Assigned), "Wrong state after assign");
        assertEq(assignedOperator, operator, "Wrong operator assigned");

        // 3. Claim Validator
        vm.startPrank(withdrawalAddress);
        vm.expectEmit(true, true, true, true);
        emit ValidatorConfirmed(tokenId, withdrawalAddress, TEST_DEPOSIT_DATA_ROOT);
        
        nonfungibleDepositManager.claimValidator(tokenId, TEST_DEPOSIT_DATA_ROOT);
        vm.stopPrank();

        // Verify confirmed state
        bytes32 depositDataRoot;
        (state,/*withdrawalAddress*/,/*withdrawalCredentials*/,/*pubkey*/,/*signature*/, depositDataRoot,/*assignedOperator*/,/*confirmedTimestamp*/) = nonfungibleDepositManager.deposits(tokenId);
        assertEq(uint256(state), uint256(NonfungibleDepositManager.DepositState.Confirmed), "Wrong state after confirm");
        assertEq(depositDataRoot, TEST_DEPOSIT_DATA_ROOT, "Wrong deposit data root");

        // 4. Issue Validator
        uint256 depositContractBalanceBefore = address(DEPOSIT_CONTRACT_ADDRESS).balance;
        vm.startPrank(operator);
        vm.expectEmit(true, true, true, true);
        emit ValidatorIssued(tokenId, operator);
        
        nonfungibleDepositManager.issueValidator(tokenId);
        vm.stopPrank();

        // Verify finalized state
        (state,/*withdrawalAddress*/,/*withdrawalCredentials*/,/*pubkey*/,/*signature*/,/*depositDataRoot*/,/*assignedOperator*/,/*confirmedTimestamp*/) = nonfungibleDepositManager.deposits(tokenId);
        assertEq(uint256(state), uint256(NonfungibleDepositManager.DepositState.Finalized), "Wrong state after finalize");
        
        // Verify deposit contract received the deposit
        uint256 depositContractBalanceAfter = address(DEPOSIT_CONTRACT_ADDRESS).balance;
        uint256 depositContractBalanceChange = depositContractBalanceAfter - depositContractBalanceBefore;
        assertEq(nonfungibleDepositManager.totalDeposits(), 0, "Deposit count processed");
        assertEq(depositContractBalanceChange, 32 ether, "Deposit contract didn't receive ETH");
    }


    function test_CancellationInRequestedState() public {
        address withdrawalAddress = makeAddr("withdrawalAddress");
   
        vm.startPrank(depositor);
        uint256 tokenId = nonfungibleDepositManager.requestDeposit{value: 32 ether}(withdrawalAddress);
        uint256 withdrawalAddressBalanceBefore = withdrawalAddress.balance;    
        nonfungibleDepositManager.cancelDeposit(tokenId);
        vm.stopPrank();
        
        // Verify cancellation
        assertEq(withdrawalAddress.balance, withdrawalAddressBalanceBefore + 32 ether, "Refund not received");
        assertEq(nonfungibleDepositManager.totalDeposits(), 0, "Total deposits not decremented");
        // Note reverts with custom error ERC721NonexistentToken(1)
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nonfungibleDepositManager.ownerOf(tokenId); // NFT should be burned
    }

    function test_CancellationInAssignedState() public {
        address withdrawalAddress = makeAddr("withdrawalAddress");
        address operator = makeAddr("operator");
        
        vm.startPrank(depositor);
        uint256 tokenId = nonfungibleDepositManager.requestDeposit{value: 32 ether}(withdrawalAddress);
             uint256 withdrawalAddressBalanceBefore = withdrawalAddress.balance;
        vm.stopPrank();

        vm.startPrank(deployer);
        nonfungibleDepositManager.setOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        nonfungibleDepositManager.assignValidator(tokenId, TEST_PUBKEY, TEST_SIGNATURE);
        vm.stopPrank();
        
        // Cancel from Assigned state
        vm.prank(depositor);
        nonfungibleDepositManager.cancelDeposit(tokenId);
        
        // Verify cancellation
        assertEq(withdrawalAddress.balance, withdrawalAddressBalanceBefore + 32 ether, "Refund not received");
        assertEq(nonfungibleDepositManager.totalDeposits(), 0, "Total deposits not decremented");
        
        
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nonfungibleDepositManager.ownerOf(tokenId); // NFT should be burned
    }

    function test_CancellationInConfirmedStateAfter7days() public {
        address withdrawalAddress = makeAddr("withdrawalAddress");
        address operator = makeAddr("operator");
        vm.startPrank(depositor);
        uint256 tokenId = nonfungibleDepositManager.requestDeposit{value: 32 ether}(withdrawalAddress);
             uint256 withdrawalAddressBalanceBefore = withdrawalAddress.balance;
        vm.stopPrank();

        vm.startPrank(deployer);
        nonfungibleDepositManager.setOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        nonfungibleDepositManager.assignValidator(tokenId, TEST_PUBKEY, TEST_SIGNATURE);
        vm.stopPrank();

        vm.startPrank(withdrawalAddress);
        nonfungibleDepositManager.claimValidator(tokenId, TEST_DEPOSIT_DATA_ROOT);
        vm.stopPrank();

        // fast foward 7 days
        vm.warp(block.timestamp + 7 days);
        // Cancel from Confirmed state
        vm.prank(depositor);
        nonfungibleDepositManager.cancelDeposit(tokenId);
        
        // Verify cancellation
        assertEq(withdrawalAddress.balance, withdrawalAddressBalanceBefore + 32 ether, "Refund not received");
        assertEq(nonfungibleDepositManager.totalDeposits(), 0, "Total deposits not decremented");
        
        
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nonfungibleDepositManager.ownerOf(tokenId); // NFT should be burned
    }

    function test_RevertWhen_UnauthorizedCancellation() public {
        address withdrawalAddress = makeAddr("withdrawalAddress");
        address unauthorizedUser = makeAddr("unauthorizedUser");
        
        vm.startPrank(depositor);
        uint256 tokenId = nonfungibleDepositManager.requestDeposit{value: 32 ether}(withdrawalAddress);
        vm.stopPrank();
        
        // Cancel from Requested state
        vm.prank(unauthorizedUser);
        vm.expectRevert("Not authorized to cancel");
        nonfungibleDepositManager.cancelDeposit(tokenId);
    }
}
