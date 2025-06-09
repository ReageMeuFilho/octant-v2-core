// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { TokenizedAllocationMechanism } from "../../TokenizedAllocationMechanism.sol";
import { QuadraticVotingMechanism } from "../../mechanism/QuadraticVotingMechanism.sol";
import { AllocationMechanismFactory } from "../../AllocationMechanismFactory.sol";
import { AllocationConfig } from "../../BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/// @title Recipient Journey Integration Tests
/// @notice Comprehensive tests for recipient user journey covering advocacy, allocation, and redemption
contract QuadraticVotingRecipientJourneyTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    QuadraticVotingMechanism mechanism;
    
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address dave = address(0x4);
    address eve = address(0x5);
    address frank = address(0x6);
    
    uint256 constant LARGE_DEPOSIT = 1000 ether;
    uint256 constant MEDIUM_DEPOSIT = 500 ether;
    uint256 constant QUORUM_REQUIREMENT = 500;
    uint256 constant VOTING_DELAY = 100;
    uint256 constant VOTING_PERIOD = 1000;
    uint256 constant TIMELOCK_DELAY = 1 days;
    
    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
    }
    
    /// @notice Helper function to sign up a user with specified deposit
    /// @param user Address of user to sign up
    /// @param depositAmount Amount of tokens to deposit
    function _signupUser(address user, uint256 depositAmount) internal {
        vm.startPrank(user);
        token.approve(address(mechanism), depositAmount);
        _tokenized(address(mechanism)).signup(depositAmount);
        vm.stopPrank();
    }
    
    /// @notice Helper function to create a proposal
    /// @param proposer Address creating the proposal
    /// @param recipient Address that will receive funds if proposal passes
    /// @param description Description of the proposal
    /// @return pid The proposal ID
    function _createProposal(address proposer, address recipient, string memory description) internal returns (uint256 pid) {
        vm.prank(proposer);
        pid = _tokenized(address(mechanism)).propose(recipient, description);
    }
    
    /// @notice Helper function to cast a vote on a proposal
    /// @param voter Address casting the vote
    /// @param pid Proposal ID to vote on
    /// @param weight Vote weight (quadratic cost = weight^2)
    function _castVote(address voter, uint256 pid, uint256 weight) internal {
        vm.prank(voter);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, weight);
    }
    
    function setUp() public {
        factory = new AllocationMechanismFactory();
        token = new ERC20Mock();
        
        token.mint(alice, 2000 ether);
        token.mint(bob, 1500 ether);
        token.mint(frank, 200 ether);
        
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Recipient Journey Test",
            symbol: "RJTEST",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_REQUIREMENT,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: 7 days,
            startBlock: block.number + 50,
            owner: address(0)
        });
        
        address mechanismAddr = factory.deployQuadraticVotingMechanism(config, 50, 100); // 50% alpha
        mechanism = QuadraticVotingMechanism(payable(mechanismAddr));
        
        // Pre-fund matching pool - this will be included in total assets during finalize
        uint256 matchingPoolAmount = 2000 ether;
        token.mint(address(this), matchingPoolAmount);
        token.transfer(address(mechanism), matchingPoolAmount);
    }
    
    /// @notice Test recipient proposal advocacy and creation
    function testRecipientAdvocacy_ProposalCreation() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
        // Recipients need proposers with voting power
        _signupUser(alice, LARGE_DEPOSIT);
        _signupUser(bob, MEDIUM_DEPOSIT);
        
        // Successful proposal creation for recipient
        uint256 pid1 = _createProposal(alice, charlie, "Charlie's Clean Energy Initiative");
        
        TokenizedAllocationMechanism.Proposal memory proposal1 = _tokenized(address(mechanism)).proposals(pid1);
        assertEq(proposal1.proposer, alice);
        assertEq(proposal1.recipient, charlie);
        assertEq(proposal1.description, "Charlie's Clean Energy Initiative");
        assertFalse(proposal1.claimed);
        assertFalse(proposal1.canceled);
        assertEq(proposal1.earliestRedeemableTime, 0);
        
        // Multiple recipients can have proposals
        uint256 pid2 = _createProposal(bob, dave, "Dave's Education Platform");
        console.log("Created proposal", pid2);
        
        uint256 pid3 = _createProposal(alice, eve, "Eve's Healthcare Program");
        console.log("Created proposal", pid3);
        
        assertEq(_tokenized(address(mechanism)).getProposalCount(), 3);
        
        // Recipient uniqueness constraint
        vm.expectRevert(abi.encodeWithSelector(
            TokenizedAllocationMechanism.RecipientUsed.selector, charlie
        ));
        vm.prank(bob);
        _tokenized(address(mechanism)).propose(charlie, "Another proposal for Charlie");
        
        // Recipient cannot self-propose (no voting power)
        vm.expectRevert(abi.encodeWithSelector(
            TokenizedAllocationMechanism.ProposeNotAllowed.selector, charlie
        ));
        vm.prank(charlie);
        _tokenized(address(mechanism)).propose(frank, "Self-initiated proposal");
        
        // Zero address cannot be recipient
        vm.expectRevert(abi.encodeWithSelector(
            TokenizedAllocationMechanism.InvalidRecipient.selector, address(0)
        ));
        vm.prank(alice);
        _tokenized(address(mechanism)).propose(address(0), "Invalid recipient");
    }
    
    /// @notice Test recipient monitoring and outcome tracking
    function testRecipientMonitoring_OutcomeTracking() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
        // Setup voting scenario with multiple outcomes
        _signupUser(alice, LARGE_DEPOSIT);
        _signupUser(bob, MEDIUM_DEPOSIT);
        _signupUser(frank, 100 ether);
        
        // Create proposals for different recipients
        uint256 pidCharlie = _createProposal(alice, charlie, "Charlie's Project");
        uint256 pidDave = _createProposal(bob, dave, "Dave's Project");
        uint256 pidEve = _createProposal(frank, eve, "Eve's Project");
        
        vm.roll(startBlock + VOTING_DELAY + 1);
        
        // Create different voting outcomes
        // Charlie: Successful (meets quorum)
        _castVote(alice, pidCharlie, 30);
        _castVote(bob, pidCharlie, 15);
        
        // Dave: Failed (below quorum)
        _castVote(bob, pidDave, 10);
        
        // Eve: Negative outcome
        _castVote(alice, pidEve, 12);
        _castVote(frank, pidEve, 8);
        
        // Recipients can monitor progress in real-time using getTally() from ProperQF
        (, , uint256 charlieQuadraticFunding, uint256 charlieLinearFunding) = mechanism.getTally(pidCharlie);
        uint256 charlieFor = charlieQuadraticFunding + charlieLinearFunding;
        // Charlie: Alice(25) + Bob(12) = (37)² × 0.5 = 684.5, rounded funding calculation
        assertTrue(charlieFor > 0, "Charlie should have funding from QuadraticFunding calculation");
        
        (, , uint256 daveQuadraticFunding, uint256 daveLinearFunding) = mechanism.getTally(pidDave);
        uint256 daveFor = daveQuadraticFunding + daveLinearFunding;
        // Dave: Bob(10) = (10)² × 0.5 = 50 
        assertTrue(daveFor > 0, "Dave should have some funding");
        
        (, , uint256 eveQuadraticFunding, uint256 eveLinearFunding) = mechanism.getTally(pidEve);
        uint256 eveFor = eveQuadraticFunding + eveLinearFunding;
        // Eve: Alice(12) + Frank(8) = (20)² × 0.5 = 200
        assertTrue(eveFor > 0, "Eve should have funding from For votes");
        
        // End voting and finalize
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success,) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");
        
        // Test outcome tracking
        assertEq(uint(_tokenized(address(mechanism)).state(pidCharlie)), uint(TokenizedAllocationMechanism.ProposalState.Succeeded));
        assertEq(uint(_tokenized(address(mechanism)).state(pidDave)), uint(TokenizedAllocationMechanism.ProposalState.Defeated));
        assertEq(uint(_tokenized(address(mechanism)).state(pidEve)), uint(TokenizedAllocationMechanism.ProposalState.Defeated));
    }
    
    /// @notice Test recipient share allocation and redemption
    function testRecipientShares_AllocationRedemption() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
        // Setup successful proposal scenario
        _signupUser(alice, LARGE_DEPOSIT);
        _signupUser(bob, MEDIUM_DEPOSIT);
        
        uint256 pid = _createProposal(alice, charlie, "Charlie's Successful Project");
        
        vm.roll(startBlock + VOTING_DELAY + 1);
        
        // Generate successful vote outcome
        _castVote(alice, pid, 30);
        _castVote(bob, pid, 20);
        
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success,) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");
        
        // Share allocation on queuing
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 0);
        
        uint256 timestampBefore = block.timestamp;
        (bool success2,) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue proposal failed");
        
        // Verify share allocation based on QuadraticFunding calculation
        uint256 actualShares = _tokenized(address(mechanism)).balanceOf(charlie);
        assertTrue(actualShares > 0, "Charlie should receive shares based on QuadraticFunding");
        assertEq(_tokenized(address(mechanism)).totalSupply(), actualShares);
        
        // With matching pool: totalAssets = user deposits + matching pool
        uint256 expectedTotalAssets = LARGE_DEPOSIT + MEDIUM_DEPOSIT + 2000 ether; // 1000 + 500 + 2000 = 3500
        assertEq(_tokenized(address(mechanism)).totalAssets(), expectedTotalAssets);
        assertEq(_tokenized(address(mechanism)).proposalShares(pid), actualShares);
        
        // Timelock enforcement
        uint256 redeemableTime = _tokenized(address(mechanism)).redeemableAfter(charlie);
        assertEq(redeemableTime, timestampBefore + TIMELOCK_DELAY);
        assertGt(redeemableTime, block.timestamp);
        
        // Cannot redeem before timelock
        vm.expectRevert("ERC4626: redeem more than max");
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(actualShares, charlie, charlie);
        
        // Successful redemption after timelock
        vm.warp(redeemableTime + 1);
        
        uint256 charlieTokensBefore = token.balanceOf(charlie);
        uint256 mechanismTokensBefore = token.balanceOf(address(mechanism));
        
        vm.prank(charlie);
        uint256 assetsReceived = _tokenized(address(mechanism)).redeem(actualShares, charlie, charlie);
        
        // Verify redemption effects
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 0);
        assertEq(token.balanceOf(charlie), charlieTokensBefore + assetsReceived);
        assertEq(token.balanceOf(address(mechanism)), mechanismTokensBefore - assetsReceived);
        // With matching pool: charlie gets 100% of shares, so 100% of total assets
        // Total assets = user deposits + matching pool = (alice + bob) + 2000
        // Since charlie is the only recipient, assetsReceived should equal total assets
        assertEq(assetsReceived, expectedTotalAssets);
    }
    
    /// @notice Test recipient partial redemption and share management
    function testRecipientShares_PartialRedemption() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
        // Setup multiple successful recipients
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();
        
        uint256 pid1 = _createProposal(alice, charlie, "Charlie's Project");
        uint256 pid2 = _createProposal(bob, dave, "Dave's Project");
        
        vm.roll(startBlock + VOTING_DELAY + 1);
        
        // Vote for both proposals
        _castVote(alice, pid1, 30);
        _castVote(bob, pid2, 25);
        
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success,) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");
        
        // Queue both proposals at the same time to ensure same timelock schedule
        uint256 queueTime = block.timestamp;
        
        // Warp to a specific time BEFORE queuing to ensure both get the same timestamp
        vm.warp(queueTime);
        (bool success1,) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid1));
        require(success1, "Queue proposal 1 failed");
        
        // Reset to same timestamp for second proposal  
        vm.warp(queueTime);
        (bool success2,) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid2));
        require(success2, "Queue proposal 2 failed");
        
        // Verify both recipients received shares based on QuadraticFunding calculations
        uint256 charlieShares = _tokenized(address(mechanism)).balanceOf(charlie);
        uint256 daveShares = _tokenized(address(mechanism)).balanceOf(dave);
        uint256 totalSupply = _tokenized(address(mechanism)).totalSupply();
        
        assertTrue(charlieShares > 0, "Charlie should receive shares");
        assertTrue(daveShares > 0, "Dave should receive shares");
        assertEq(totalSupply, charlieShares + daveShares);
        
        // Fast forward past timelock with buffer for safety
        vm.warp(block.timestamp + TIMELOCK_DELAY + 100);
        
        // Charlie partial redemption (50%) - use maxRedeem to avoid boundary issues
        uint256 charlieMaxRedeem = _tokenized(address(mechanism)).maxRedeem(charlie);
        uint256 charliePartialRedeem = charlieMaxRedeem / 2; // Redeem half of what's allowed
        vm.prank(charlie);
        uint256 charlieAssets1 = _tokenized(address(mechanism)).redeem(charliePartialRedeem, charlie, charlie);
        
        uint256 charlieRemainingShares = charlieShares - charliePartialRedeem;
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), charlieRemainingShares);
        assertEq(_tokenized(address(mechanism)).totalSupply(), totalSupply - charliePartialRedeem);
        
        // With matching pool: calculate expected assets based on share-to-asset ratio
        uint256 totalAssets = LARGE_DEPOSIT + MEDIUM_DEPOSIT + 2000 ether; // 3500 ether
        uint256 expectedCharlieAssets1 = (charliePartialRedeem * totalAssets) / totalSupply;
        assertApproxEqAbs(charlieAssets1, expectedCharlieAssets1, 1, "Charlie assets1 within 1 wei");
        
        // Dave full redemption - use maxRedeem to handle any rounding issues
        uint256 daveMaxRedeemShares = _tokenized(address(mechanism)).maxRedeem(dave);
        vm.prank(dave);
        uint256 daveAssets = _tokenized(address(mechanism)).redeem(daveMaxRedeemShares, dave, dave);
        
        uint256 daveRemainingShares = daveShares - daveMaxRedeemShares;
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), daveRemainingShares);
        assertEq(_tokenized(address(mechanism)).totalSupply(), charlieRemainingShares + daveRemainingShares);
        
        uint256 expectedDaveAssets = (daveMaxRedeemShares * totalAssets) / totalSupply;
        assertApproxEqAbs(daveAssets, expectedDaveAssets, 1, "Dave assets within 1 wei");
        
        // Charlie remaining redemption - redeem whatever is left and allowed
        uint256 charlieMaxRedeem2 = _tokenized(address(mechanism)).maxRedeem(charlie);
        vm.prank(charlie);
        uint256 charlieAssets2 = _tokenized(address(mechanism)).redeem(charlieMaxRedeem2, charlie, charlie);
        
        // If Charlie has any remaining shares due to rounding, redeem them too
        uint256 charlieRemainingAfterSecond = _tokenized(address(mechanism)).balanceOf(charlie);
        uint256 charlieAssets3 = 0;
        if (charlieRemainingAfterSecond > 0) {
            uint256 charlieMaxRedeem3 = _tokenized(address(mechanism)).maxRedeem(charlie);
            if (charlieMaxRedeem3 > 0) {
                vm.prank(charlie);
                charlieAssets3 = _tokenized(address(mechanism)).redeem(charlieMaxRedeem3, charlie, charlie);
            }
        }
        
        // Charlie should now have redeemed all shares
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0, "Charlie should have redeemed all shares");
        assertEq(_tokenized(address(mechanism)).totalSupply(), daveRemainingShares);
        
        uint256 expectedCharlieAssets2 = (charlieMaxRedeem2 * totalAssets) / totalSupply;
        assertApproxEqAbs(charlieAssets2, expectedCharlieAssets2, 1, "Charlie assets2 within 1 wei");
        
        // Let Dave redeem any remaining shares too
        uint256 daveAssets2 = 0;
        if (daveRemainingShares > 0) {
            uint256 daveMaxRedeem2 = _tokenized(address(mechanism)).maxRedeem(dave);
            if (daveMaxRedeem2 > 0) {
                vm.prank(dave);
                daveAssets2 = _tokenized(address(mechanism)).redeem(daveMaxRedeem2, dave, dave);
            }
        }
        
        // Verify total assets redeemed correctly with matching pool conversion
        uint256 charlieActualSharesRedeemed = charliePartialRedeem + charlieMaxRedeem2;
        if (charlieAssets3 > 0) {
            // If there was a third redemption, include it
            charlieActualSharesRedeemed += charlieRemainingAfterSecond;
        }
        uint256 expectedCharlieTotal = (charlieActualSharesRedeemed * totalAssets) / totalSupply;
        assertApproxEqAbs(charlieAssets1 + charlieAssets2 + charlieAssets3, expectedCharlieTotal, 3, "Charlie total within 3 wei");
        
        // Both recipients should have redeemed all or nearly all their shares
        uint256 totalRemainingShares = _tokenized(address(mechanism)).totalSupply();
        assertTrue(totalRemainingShares <= 1, "Should have at most 1 remaining share due to rounding");
        
        // Verify total assets conservation - almost all assets should be redeemed
        uint256 totalAssetsRedeemed = charlieAssets1 + charlieAssets2 + charlieAssets3 + daveAssets + daveAssets2;
        assertApproxEqAbs(totalAssetsRedeemed, totalAssets, 10, "Total assets redeemed should be close to total assets");
    }
    
    /// @notice Test recipient share transferability and ERC20 functionality
    function testRecipientShares_TransferabilityERC20() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
        // Setup successful allocation
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();
        
        uint256 pid = _createProposal(alice, charlie, "Charlie's Project");
        
        vm.roll(startBlock + VOTING_DELAY + 1);
        
        _castVote(alice, pid, 30);
        
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success,) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");
        
        (bool success2,) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue proposal failed");
        
        // Charlie receives shares from QuadraticFunding calculation
        uint256 charlieShares = _tokenized(address(mechanism)).balanceOf(charlie);
        assertTrue(charlieShares > 0, "Charlie should receive shares");
        
        // Test share transferability (use reasonable portion of actual shares)
        uint256 transferAmount = charlieShares / 3; // Transfer 1/3 of shares
        vm.prank(charlie);
        _tokenized(address(mechanism)).transfer(dave, transferAmount);
        
        // Verify transfer
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), charlieShares - transferAmount);
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), transferAmount);
        assertEq(_tokenized(address(mechanism)).totalSupply(), charlieShares);
        
        // Test approval and transferFrom
        uint256 allowanceAmount = charlieShares / 5; // Approve 1/5 of original shares
        vm.prank(charlie);
        _tokenized(address(mechanism)).approve(dave, allowanceAmount);
        
        assertEq(_tokenized(address(mechanism)).allowance(charlie, dave), allowanceAmount);
        
        vm.prank(dave);
        _tokenized(address(mechanism)).transferFrom(charlie, eve, allowanceAmount);
        
        // Verify transferFrom effects
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), charlieShares - transferAmount - allowanceAmount);
        assertEq(_tokenized(address(mechanism)).balanceOf(eve), allowanceAmount);
        assertEq(_tokenized(address(mechanism)).allowance(charlie, dave), 0);
        
        // Fast forward and test redemption by transferees
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        
        // Dave can redeem transferred shares
        vm.prank(dave);
        uint256 daveAssets = _tokenized(address(mechanism)).redeem(transferAmount, dave, dave);
        
        // With matching pool: total assets = 1000 (alice) + 2000 (matching pool) = 3000 ether
        // Conversion ratio = 3000 ether / 900 shares = 3.333... ether per share
        uint256 totalAssets = LARGE_DEPOSIT + 2000 ether; // 3000 ether
        uint256 expectedDaveAssets = (transferAmount * totalAssets) / charlieShares;
        assertEq(daveAssets, expectedDaveAssets);
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), 0);
        
        // Eve can redeem transferred shares
        vm.prank(eve);
        uint256 eveAssets = _tokenized(address(mechanism)).redeem(allowanceAmount, eve, eve);
        
        uint256 expectedEveAssets = (allowanceAmount * totalAssets) / charlieShares;
        assertEq(eveAssets, expectedEveAssets);
        assertEq(_tokenized(address(mechanism)).balanceOf(eve), 0);
    }
}