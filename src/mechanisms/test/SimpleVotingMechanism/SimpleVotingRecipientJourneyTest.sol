// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { SimpleVotingMechanism } from "src/mechanisms/mechanism/SimpleVotingMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/// @title Recipient Journey Integration Tests
/// @notice Comprehensive tests for recipient user journey covering advocacy, allocation, and redemption
contract SimpleVotingRecipientJourneyTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address dave = address(0x4);
    address eve = address(0x5);
    address frank = address(0x6);

    uint256 constant LARGE_DEPOSIT = 1000 ether;
    uint256 constant MEDIUM_DEPOSIT = 500 ether;
    uint256 constant QUORUM_REQUIREMENT = 200 ether;
    uint256 constant VOTING_DELAY = 100;
    uint256 constant VOTING_PERIOD = 1000;
    uint256 constant TIMELOCK_DELAY = 1 days;

    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
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

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }

    /// @notice Test recipient proposal advocacy and creation
    function testRecipientAdvocacy_ProposalCreation() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Recipients need proposers with voting power
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        // Successful proposal creation for recipient
        vm.prank(alice);
        uint256 pid1 = _tokenized(address(mechanism)).propose(charlie, "Charlie's Clean Energy Initiative");

        TokenizedAllocationMechanism.Proposal memory proposal1 = _tokenized(address(mechanism)).proposals(pid1);
        assertEq(proposal1.proposer, alice);
        assertEq(proposal1.recipient, charlie);
        assertEq(proposal1.description, "Charlie's Clean Energy Initiative");
        assertFalse(proposal1.claimed);
        assertFalse(proposal1.canceled);
        assertEq(proposal1.earliestRedeemableTime, 0);

        // Multiple recipients can have proposals
        vm.prank(bob);
        uint256 pid2 = _tokenized(address(mechanism)).propose(dave, "Dave's Education Platform");
        console.log("Created proposal", pid2);

        vm.prank(alice);
        uint256 pid3 = _tokenized(address(mechanism)).propose(eve, "Eve's Healthcare Program");
        console.log("Created proposal", pid3);

        assertEq(_tokenized(address(mechanism)).getProposalCount(), 3);

        // Recipient uniqueness constraint
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.RecipientUsed.selector, charlie));
        vm.prank(bob);
        _tokenized(address(mechanism)).propose(charlie, "Another proposal for Charlie");

        // Recipient cannot self-propose (no voting power)
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.ProposeNotAllowed.selector, charlie));
        vm.prank(charlie);
        _tokenized(address(mechanism)).propose(frank, "Self-initiated proposal");

        // Zero address cannot be recipient
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.InvalidRecipient.selector, address(0)));
        vm.prank(alice);
        _tokenized(address(mechanism)).propose(address(0), "Invalid recipient");
    }

    /// @notice Test recipient monitoring and outcome tracking
    function testRecipientMonitoring_OutcomeTracking() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup voting scenario with multiple outcomes
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(frank);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        // Create proposals for different recipients
        vm.prank(alice);
        uint256 pidCharlie = _tokenized(address(mechanism)).propose(charlie, "Charlie's Project");

        vm.prank(bob);
        uint256 pidDave = _tokenized(address(mechanism)).propose(dave, "Dave's Project");

        vm.prank(frank);
        uint256 pidEve = _tokenized(address(mechanism)).propose(eve, "Eve's Project");

        vm.roll(startBlock + VOTING_DELAY + 1);

        // Create different voting outcomes
        // Charlie: Successful (meets quorum)
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pidCharlie, TokenizedAllocationMechanism.VoteType.For, 800 ether);
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pidCharlie, TokenizedAllocationMechanism.VoteType.For, 200 ether);

        // Dave: Failed (below quorum)
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pidDave, TokenizedAllocationMechanism.VoteType.For, 150 ether);

        // Eve: Negative outcome
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pidEve, TokenizedAllocationMechanism.VoteType.Against, 200 ether);
        vm.prank(frank);
        _tokenized(address(mechanism)).castVote(pidEve, TokenizedAllocationMechanism.VoteType.For, 100 ether);

        // Recipients can monitor progress in real-time
        (uint256 charlieFor, uint256 charlieAgainst, ) = mechanism.voteTallies(pidCharlie);
        assertEq(charlieFor, 1000 ether);
        assertEq(charlieAgainst, 0);

        (uint256 daveFor, , ) = mechanism.voteTallies(pidDave);
        assertEq(daveFor, 150 ether);

        (uint256 eveFor, uint256 eveAgainst, ) = mechanism.voteTallies(pidEve);
        assertEq(eveFor, 100 ether);
        assertEq(eveAgainst, 200 ether);

        // End voting and finalize
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Test outcome tracking
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidCharlie)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidDave)),
            uint(TokenizedAllocationMechanism.ProposalState.Defeated)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidEve)),
            uint(TokenizedAllocationMechanism.ProposalState.Defeated)
        );
    }

    /// @notice Test recipient share allocation and redemption
    function testRecipientShares_AllocationRedemption() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup successful proposal scenario
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Charlie's Successful Project");

        vm.roll(startBlock + VOTING_DELAY + 1);

        // Generate successful vote outcome
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 700 ether);

        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 300 ether);

        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Share allocation on queuing
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 0);

        uint256 timestampBefore = block.timestamp;
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue proposal failed");

        // Verify share allocation
        uint256 expectedShares = 1000 ether;
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), expectedShares);
        assertEq(_tokenized(address(mechanism)).totalSupply(), expectedShares);
        // Total assets should reflect actual deposits: 1000 + 500 = 1500 ether
        assertEq(_tokenized(address(mechanism)).totalAssets(), 1500 ether);
        assertEq(_tokenized(address(mechanism)).proposalShares(pid), expectedShares);

        // Timelock enforcement
        uint256 redeemableTime = _tokenized(address(mechanism)).redeemableAfter(charlie);
        assertEq(redeemableTime, timestampBefore + TIMELOCK_DELAY);
        assertGt(redeemableTime, block.timestamp);

        // Cannot redeem before timelock
        vm.expectRevert("Allocation: redeem more than max");
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(expectedShares, charlie, charlie);

        // Successful redemption after timelock
        vm.warp(redeemableTime + 1);

        uint256 charlieTokensBefore = token.balanceOf(charlie);
        uint256 mechanismTokensBefore = token.balanceOf(address(mechanism));

        // Calculate expected assets based on proper accounting
        // Total deposits: 1000 + 500 = 1500 ether
        // Share price: 1500/1000 = 1.5 assets per share
        uint256 expectedAssets = (expectedShares * 1500 ether) / 1000 ether;

        vm.prank(charlie);
        uint256 assetsReceived = _tokenized(address(mechanism)).redeem(expectedShares, charlie, charlie);

        // Verify redemption effects
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 0);
        assertEq(token.balanceOf(charlie), charlieTokensBefore + assetsReceived);
        assertEq(token.balanceOf(address(mechanism)), mechanismTokensBefore - assetsReceived);
        assertApproxEqAbs(assetsReceived, expectedAssets, 3);
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

        vm.prank(alice);
        uint256 pid1 = _tokenized(address(mechanism)).propose(charlie, "Charlie's Project");

        vm.prank(bob);
        uint256 pid2 = _tokenized(address(mechanism)).propose(dave, "Dave's Project");

        vm.roll(startBlock + VOTING_DELAY + 1);

        // Vote for both proposals
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.For, 600 ether);

        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.For, 400 ether);

        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Queue both proposals
        (bool success1, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid1));
        require(success1, "Queue proposal 1 failed");

        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid2));
        require(success2, "Queue proposal 2 failed");

        // Verify both recipients received shares
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 600 ether);
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), 400 ether);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 1000 ether);

        // Fast forward past timelock
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Calculate expected assets based on proper accounting
        // Total deposits: 1000 + 500 = 1500 ether
        // Total shares: 600 + 400 = 1000 ether
        // Share price: 1500/1000 = 1.5 assets per share
        uint256 totalDeposits = 1500 ether;
        uint256 totalShares = 1000 ether;

        // Charlie partial redemption (50%)
        uint256 charliePartialRedeem = 300 ether;
        uint256 expectedCharlieAssets1 = (charliePartialRedeem * totalDeposits) / totalShares;

        vm.prank(charlie);
        uint256 charlieAssets1 = _tokenized(address(mechanism)).redeem(charliePartialRedeem, charlie, charlie);

        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 300 ether);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 700 ether);
        assertApproxEqAbs(charlieAssets1, expectedCharlieAssets1, 3);

        // Dave full redemption
        uint256 expectedDaveAssets = (400 ether * totalDeposits) / totalShares;

        vm.prank(dave);
        uint256 daveAssets = _tokenized(address(mechanism)).redeem(400 ether, dave, dave);

        assertEq(_tokenized(address(mechanism)).balanceOf(dave), 0);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 300 ether);
        assertApproxEqAbs(daveAssets, expectedDaveAssets, 3);

        // Charlie remaining redemption
        uint256 expectedCharlieAssets2 = (300 ether * totalDeposits) / totalShares;

        vm.prank(charlie);
        uint256 charlieAssets2 = _tokenized(address(mechanism)).redeem(300 ether, charlie, charlie);

        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 0);
        assertApproxEqAbs(charlieAssets2, expectedCharlieAssets2, 3);

        // Verify total assets redeemed correctly with proper accounting
        uint256 expectedTotalCharlieAssets = (600 ether * totalDeposits) / totalShares;
        assertApproxEqAbs(charlieAssets1 + charlieAssets2, expectedTotalCharlieAssets, 3);
        assertApproxEqAbs(daveAssets, expectedDaveAssets, 3);
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

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Charlie's Project");

        vm.roll(startBlock + VOTING_DELAY + 1);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether);

        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue proposal failed");

        // Charlie receives shares
        uint256 charlieShares = 500 ether;
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), charlieShares);

        // Test share transferability
        uint256 transferAmount = 200 ether;
        vm.prank(charlie);
        _tokenized(address(mechanism)).transfer(dave, transferAmount);

        // Verify transfer
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), charlieShares - transferAmount);
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), transferAmount);
        assertEq(_tokenized(address(mechanism)).totalSupply(), charlieShares);

        // Test approval and transferFrom
        uint256 allowanceAmount = 100 ether;
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

        // Calculate expected assets based on proper accounting
        // Total deposits: 1000 ether (alice's deposit)
        // Total shares: 500 ether (net votes)
        // Share price: 1000/500 = 2 assets per share
        uint256 totalDeposits = 1000 ether;
        uint256 totalShares = 500 ether;

        // Dave can redeem transferred shares
        uint256 expectedDaveAssets = (transferAmount * totalDeposits) / totalShares;

        vm.prank(dave);
        uint256 daveAssets = _tokenized(address(mechanism)).redeem(transferAmount, dave, dave);
        assertApproxEqAbs(daveAssets, expectedDaveAssets, 3);
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), 0);

        // Eve can redeem transferred shares
        uint256 expectedEveAssets = (allowanceAmount * totalDeposits) / totalShares;

        vm.prank(eve);
        uint256 eveAssets = _tokenized(address(mechanism)).redeem(allowanceAmount, eve, eve);
        assertApproxEqAbs(eveAssets, expectedEveAssets, 3);
        assertEq(_tokenized(address(mechanism)).balanceOf(eve), 0);
    }
}
