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

/// @title Proposal State Journey Tests
/// @notice Comprehensive tests for all possible proposal states and recipient experiences
contract SimpleVotingProposalStateTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;

    address alice = address(0x1); // Voter/Proposer
    address bob = address(0x2); // Voter
    address charlie = address(0x3); // Recipient
    address dave = address(0x4); // Recipient
    address eve = address(0x5); // Recipient
    address frank = address(0x6); // Recipient
    address grace = address(0x7); // Recipient
    address henry = address(0x8); // Recipient

    uint256 constant LARGE_DEPOSIT = 1000 ether;
    uint256 constant MEDIUM_DEPOSIT = 500 ether;
    uint256 constant QUORUM_REQUIREMENT = 200 ether;
    uint256 constant VOTING_DELAY = 100;
    uint256 constant VOTING_PERIOD = 1000;
    uint256 constant TIMELOCK_DELAY = 1 days;
    uint256 constant GRACE_PERIOD = 7 days;

    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
    }

    function setUp() public {
        factory = new AllocationMechanismFactory();
        token = new ERC20Mock();

        token.mint(alice, 2000 ether);
        token.mint(bob, 1500 ether);

        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Proposal State Test",
            symbol: "PSTEST",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_REQUIREMENT,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: GRACE_PERIOD,
            startBlock: block.number + 50,
            owner: address(0)
        });

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }

    /// @notice Test PENDING state - proposal created before mechanism starts
    function testProposalState_Pending() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();

        // Before mechanism starts
        vm.roll(startBlock - 10);

        // Register and create proposal
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Charlie's Pending Proposal");
        vm.stopPrank();

        // Verify PENDING state
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Pending)
        );

        // Recipient can monitor but cannot vote yet
        TokenizedAllocationMechanism.Proposal memory proposal = _tokenized(address(mechanism)).proposals(pid);
        assertEq(proposal.recipient, charlie);
        assertEq(proposal.proposer, alice);

        // Move closer to start but still pending
        vm.roll(startBlock - 1);
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Pending)
        );
    }

    /// @notice Test ACTIVE state - proposal during voting delay and voting period
    function testProposalState_Active() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup and create proposal
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(dave, "Dave's Active Proposal");
        vm.stopPrank();

        // During voting delay - ACTIVE
        vm.roll(startBlock + 50);
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Active)
        );

        // During voting period - ACTIVE
        vm.roll(startBlock + VOTING_DELAY + 50);
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Active)
        );

        // Recipient can monitor voting progress
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 300 ether);

        (uint256 forVotes, , ) = _tokenized(address(mechanism)).getVoteTally(pid);
        assertEq(forVotes, 300 ether);

        // Still ACTIVE until finalized
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 10);
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Active)
        );
    }

    /// @notice Test CANCELED state - proposer cancels before queuing
    function testProposalState_Canceled() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(eve, "Eve's Canceled Proposal");
        vm.stopPrank();

        // Proposer cancels during active period
        vm.roll(startBlock + VOTING_DELAY + 50);
        vm.prank(alice);
        _tokenized(address(mechanism)).cancelProposal(pid);

        // Verify CANCELED state
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Canceled)
        );

        // Recipient cannot receive anything from canceled proposal
        TokenizedAllocationMechanism.Proposal memory proposal = _tokenized(address(mechanism)).proposals(pid);
        assertTrue(proposal.canceled);
        assertEq(proposal.earliestRedeemableTime, 0);

        // Cannot vote on canceled proposal
        vm.expectRevert();
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether);

        // State remains CANCELED permanently
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 100);
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Canceled)
        );
    }

    /// @notice Test DEFEATED state - proposal fails to meet quorum or has negative votes
    function testProposalState_Defeated() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup voters
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        // Create proposals that will be defeated
        vm.prank(alice);
        uint256 pidLowVotes = _tokenized(address(mechanism)).propose(frank, "Frank's Low Vote Proposal");

        vm.prank(bob);
        uint256 pidNegativeVotes = _tokenized(address(mechanism)).propose(grace, "Grace's Negative Vote Proposal");

        vm.roll(startBlock + VOTING_DELAY + 1);

        // Proposal 1: Insufficient votes (below quorum)
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pidLowVotes, TokenizedAllocationMechanism.VoteType.For, 150 ether);

        // Proposal 2: Negative net votes
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(
            pidNegativeVotes,
            TokenizedAllocationMechanism.VoteType.Against,
            400 ether
        );
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pidNegativeVotes, TokenizedAllocationMechanism.VoteType.For, 200 ether);

        // Finalize voting
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Verify DEFEATED states
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidLowVotes)),
            uint(TokenizedAllocationMechanism.ProposalState.Defeated)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidNegativeVotes)),
            uint(TokenizedAllocationMechanism.ProposalState.Defeated)
        );

        // Recipients get nothing from defeated proposals
        assertEq(_tokenized(address(mechanism)).balanceOf(frank), 0);
        assertEq(_tokenized(address(mechanism)).balanceOf(grace), 0);

        // Cannot queue defeated proposals should revert with NoQuorum
        vm.expectRevert();
        _tokenized(address(mechanism)).queueProposal(pidLowVotes);

        vm.expectRevert();
        _tokenized(address(mechanism)).queueProposal(pidNegativeVotes);
    }

    /// @notice Test SUCCEEDED state - proposal meets quorum but not yet queued
    function testProposalState_Succeeded() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(henry, "Henry's Successful Proposal");
        vm.stopPrank();

        vm.roll(startBlock + VOTING_DELAY + 1);

        // Vote to meet quorum
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 300 ether);

        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Verify SUCCEEDED state
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );

        // Recipient knows they will receive allocation but shares not minted yet
        assertEq(_tokenized(address(mechanism)).balanceOf(henry), 0);

        // Proposal can be queued by admin
        TokenizedAllocationMechanism.Proposal memory proposal = _tokenized(address(mechanism)).proposals(pid);
        assertEq(proposal.earliestRedeemableTime, 0); // Not queued yet
        assertFalse(proposal.canceled);

        // Verify vote tallies are correct
        (uint256 forVotes, uint256 againstVotes, ) = _tokenized(address(mechanism)).getVoteTally(pid);
        assertEq(forVotes, 300 ether);
        assertEq(againstVotes, 0);
        assertTrue(forVotes - againstVotes >= QUORUM_REQUIREMENT);
    }

    /// @notice Test QUEUED state - proposal queued with shares minted and timelock active
    function testProposalState_Queued() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup successful proposal
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Charlie's Queued Proposal");
        vm.stopPrank();

        vm.roll(startBlock + VOTING_DELAY + 1);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 400 ether);

        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Queue the proposal
        uint256 timestampBefore = block.timestamp;
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");

        // Verify QUEUED state
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Queued)
        );

        // Recipient receives shares but cannot redeem yet due to timelock
        uint256 expectedShares = 400 ether;
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), expectedShares);
        assertEq(_tokenized(address(mechanism)).proposalShares(pid), expectedShares);

        // Timelock is active
        TokenizedAllocationMechanism.Proposal memory proposal = _tokenized(address(mechanism)).proposals(pid);
        assertEq(proposal.earliestRedeemableTime, timestampBefore + TIMELOCK_DELAY);
        assertEq(_tokenized(address(mechanism)).redeemableAfter(charlie), timestampBefore + TIMELOCK_DELAY);
        assertGt(proposal.earliestRedeemableTime, block.timestamp);

        // Cannot redeem during timelock
        vm.expectRevert("ERC4626: redeem more than max");
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(expectedShares, charlie, charlie);

        // Cannot queue again
        vm.expectRevert(TokenizedAllocationMechanism.AlreadyQueued.selector);
        (bool success3, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        assertFalse(success3);
    }

    /// @notice Test EXECUTED state - shares redeemed after timelock
    function testProposalState_Executed() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup and execute successful proposal
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(dave, "Dave's Executed Proposal");
        vm.stopPrank();

        vm.roll(startBlock + VOTING_DELAY + 1);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether);

        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");

        // Fast forward past timelock
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Recipient redeems shares with proper asset accounting
        uint256 daveTokensBefore = token.balanceOf(dave);

        // Get actual redeemable shares (accounting for proper share price)
        uint256 daveMaxShares = _tokenized(address(mechanism)).maxRedeem(dave);

        vm.prank(dave);
        uint256 assetsReceived = _tokenized(address(mechanism)).redeem(daveMaxShares, dave, dave);

        // Calculate expected assets based on proper accounting
        // Total deposits: 1000 ether (alice's deposit)
        // Total shares: 500 ether (net votes)
        // Share price: 1000/500 = 2 assets per share
        uint256 totalDeposits = 1000 ether;
        uint256 totalShares = 500 ether;
        uint256 expectedAssets = (500 ether * totalDeposits) / totalShares;

        // Verify redemption effects
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), 0);
        assertEq(token.balanceOf(dave), daveTokensBefore + assetsReceived);
        assertApproxEqAbs(assetsReceived, expectedAssets, 3);

        // In current implementation, state is still QUEUED after redemption
        // This could be enhanced to track EXECUTED state when all shares are redeemed
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Queued)
        );
    }

    /// @notice Test EXPIRED state - proposal queued but grace period exceeded
    function testProposalState_Expired() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup proposal that will expire
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(eve, "Eve's Expired Proposal");
        vm.stopPrank();

        vm.roll(startBlock + VOTING_DELAY + 1);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 300 ether);

        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");

        // Fast forward past timelock + grace period
        vm.warp(block.timestamp + TIMELOCK_DELAY + GRACE_PERIOD + 1);

        // Verify EXPIRED state
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Expired)
        );

        // Recipient still has shares but cannot redeem (expired)
        assertEq(_tokenized(address(mechanism)).balanceOf(eve), 300 ether);

        // Redemption should fail due to expiration
        vm.expectRevert("ERC4626: redeem more than max");
        vm.prank(eve);
        _tokenized(address(mechanism)).redeem(300 ether, eve, eve);
    }

    /// @notice Test complete recipient journey through multiple proposal states
    function testRecipientJourney_MultipleProposalStates() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup multiple voters
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        // Create proposals that will have different outcomes
        vm.prank(alice);
        uint256 pidSuccessful = _tokenized(address(mechanism)).propose(charlie, "Charlie's Success Story");

        vm.prank(bob);
        uint256 pidDefeated = _tokenized(address(mechanism)).propose(dave, "Dave's Defeat");

        vm.prank(alice);
        uint256 pidCanceled = _tokenized(address(mechanism)).propose(eve, "Eve's Cancellation");

        // Start with all in PENDING
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidSuccessful)),
            uint(TokenizedAllocationMechanism.ProposalState.Pending)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidDefeated)),
            uint(TokenizedAllocationMechanism.ProposalState.Pending)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidCanceled)),
            uint(TokenizedAllocationMechanism.ProposalState.Pending)
        );

        // Move to ACTIVE
        vm.roll(startBlock + VOTING_DELAY + 1);
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidSuccessful)),
            uint(TokenizedAllocationMechanism.ProposalState.Active)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidDefeated)),
            uint(TokenizedAllocationMechanism.ProposalState.Active)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidCanceled)),
            uint(TokenizedAllocationMechanism.ProposalState.Active)
        );

        // Cancel one proposal
        vm.prank(alice);
        _tokenized(address(mechanism)).cancelProposal(pidCanceled);
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidCanceled)),
            uint(TokenizedAllocationMechanism.ProposalState.Canceled)
        );

        // Vote on remaining proposals
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pidSuccessful, TokenizedAllocationMechanism.VoteType.For, 600 ether);

        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pidDefeated, TokenizedAllocationMechanism.VoteType.For, 150 ether); // Below quorum

        // Finalize
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Check final states
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidSuccessful)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidDefeated)),
            uint(TokenizedAllocationMechanism.ProposalState.Defeated)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidCanceled)),
            uint(TokenizedAllocationMechanism.ProposalState.Canceled)
        );

        // Queue successful proposal
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pidSuccessful));
        require(success2, "Queue failed");

        assertEq(
            uint(_tokenized(address(mechanism)).state(pidSuccessful)),
            uint(TokenizedAllocationMechanism.ProposalState.Queued)
        );

        // Verify recipient outcomes
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 600 ether); // Success
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), 0); // Defeated
        assertEq(_tokenized(address(mechanism)).balanceOf(eve), 0); // Canceled

        // Fast forward and redeem with proper asset accounting
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Calculate expected assets based on proper accounting
        // Total deposits: 1000 + 500 = 1500 ether (alice + bob)
        // Total shares: 600 ether (charlie's net votes)
        // Share price: 1500/600 = 2.5 assets per share
        uint256 totalDeposits = 1500 ether;
        uint256 totalShares = 600 ether;
        uint256 expectedAssets = (600 ether * totalDeposits) / totalShares;

        // Get actual redeemable shares (accounting for proper share price)
        uint256 charlieMaxShares = _tokenized(address(mechanism)).maxRedeem(charlie);

        vm.prank(charlie);
        uint256 charlieAssets = _tokenized(address(mechanism)).redeem(charlieMaxShares, charlie, charlie);
        assertApproxEqAbs(charlieAssets, expectedAssets, 3);

        // Final verification: Charlie got paid, others didn't
        assertGt(token.balanceOf(charlie), 0);
        assertEq(token.balanceOf(dave), 0);
        assertEq(token.balanceOf(eve), 0);
    }
}
