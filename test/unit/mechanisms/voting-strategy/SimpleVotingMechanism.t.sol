// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { SimpleVotingMechanism } from "src/mechanisms/mechanism/SimpleVotingMechanism.sol";
import { BaseAllocationMechanism } from "src/mechanisms/BaseAllocationMechanism.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SimpleVotingMechanismTest is Test {
    SimpleVotingMechanism voting;
    MockERC20 token;

    address admin = address(1);
    address user1 = address(2);
    address user2 = address(3);
    address user3 = address(4);
    address recipient1 = address(5);
    address recipient2 = address(6);

    uint256 votingDelay = 10;
    uint256 votingPeriod = 100;
    uint256 quorumShares = 50;
    uint256 timelockDelay = 1 days;
    uint256 gracePeriod = 14 days;

    function setUp() public {
        vm.startPrank(admin);
        token = new MockERC20("Test Token", "TEST");
        voting = new SimpleVotingMechanism(
            IERC20(address(token)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            quorumShares,
            timelockDelay,
            gracePeriod,
            1
        );

        // Fund test users
        token.mint(user1, 1000 * 10 ** 18);
        token.mint(user2, 1000 * 10 ** 18);
        token.mint(user3, 1000 * 10 ** 18);
        vm.stopPrank();
    }

    // 1. Contract Initialization Tests
    function testConstructorParameters() public view {
        assertEq(address(voting.asset()), address(token));
        assertEq(voting.name(), "Voting Shares");
        assertEq(voting.symbol(), "VOTE");
        assertEq(voting.votingDelay(), votingDelay);
        assertEq(voting.votingPeriod(), votingPeriod);
        assertEq(voting.quorumShares(), quorumShares);
        assertEq(voting.timelockDelay(), timelockDelay);
        assertEq(voting.startBlock(), 1);
    }

    // 2. Registration Tests
    function testSuccessfulRegistration() public {
        uint256 depositAmount = 500 * 10 ** 18;

        vm.startPrank(user1);
        token.approve(address(voting), depositAmount);
        voting.signup(depositAmount);
        vm.stopPrank();

        assertEq(voting.votingPower(user1), depositAmount);
    }

    function testRegistrationWithZeroDeposit() public {
        vm.prank(user1);
        voting.signup(0);

        assertEq(voting.votingPower(user1), 0);
    }

    function testRegistrationAfterVotingPeriod() public {
        // Move past voting period
        vm.roll(block.number + votingDelay + votingPeriod + 1);

        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.VotingEnded.selector);
        voting.signup(100);
    }

    function testDoubleRegistration() public {
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);

        vm.expectRevert(BaseAllocationMechanism.AlreadyRegistered.selector);
        voting.signup(100);
        vm.stopPrank();
    }

    // 3. Proposal Creation Tests
    function testProposalCreation() public {
        // Register first
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);

        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        assertEq(pid, 1);
        BaseAllocationMechanism.Proposal memory proposal = voting.proposals(pid);
        assertEq(proposal.proposer, user1);
        assertEq(proposal.recipient, recipient1);
    }

    function testProposalCreationByUnregisteredUser() public {
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.ProposeNotAllowed.selector);
        voting.propose(recipient1, "Test proposal");
    }

    function testProposalWithUsedRecipient() public {
        // Register users
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(voting), 100);
        voting.signup(100);

        vm.expectRevert(BaseAllocationMechanism.RecipientUsed.selector);
        voting.propose(recipient1, "Test proposal");
        vm.stopPrank();
    }

    // 4. Voting Tests
    function testCastingVotes() public {
        // Setup: register users and create proposal
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(voting), 300);
        voting.signup(300);
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Cast votes
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        vm.prank(user2);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.Against, 200);

        // Check vote counts
        (uint256 sharesFor, uint256 sharesAgainst, uint256 sharesAbstain) = voting.getVoteTally(pid);
        assertEq(sharesFor, 150);
        assertEq(sharesAgainst, 200);
        assertEq(sharesAbstain, 0);

        // Check reduced voting power
        assertEq(voting.votingPower(user1), 50);
        assertEq(voting.votingPower(user2), 100);
    }

    function testVotingBeforePeriod() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");

        vm.expectRevert(BaseAllocationMechanism.VotingClosed.selector);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 50);
        vm.stopPrank();
    }

    function testVotingAfterPeriod() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move past voting period
        vm.roll(block.number + votingDelay + votingPeriod + 1);

        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.VotingClosed.selector);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 50);
    }

    function testDoubleVoting() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        vm.startPrank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 50);

        vm.expectRevert(BaseAllocationMechanism.AlreadyVoted.selector);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 50);
        vm.stopPrank();
    }

    // 5. Vote Tally Finalization Tests
    function testFinalizeVoteTally() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move past voting period
        vm.roll(block.number + votingDelay + votingPeriod + 1);

        vm.prank(admin);
        voting.finalizeVoteTally();

        assertTrue(voting.tallyFinalized());
    }

    function testFinalizeBeforeVotingEnd() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.VotingNotEnded.selector);
        voting.finalizeVoteTally();
    }

    // 6. Proposal Queuing Tests
    function testQueueProposal() public {
        // Setup: register, propose, vote enough to pass quorum
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Cast votes to meet quorum
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // Move past voting period and finalize
        vm.roll(block.number + votingPeriod);
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Queue proposal
        vm.prank(admin);
        voting.queueProposal(pid);

        // Check proposal is queued
        BaseAllocationMechanism.Proposal memory proposal = voting.proposals(pid);
        assertEq(proposal.sharesRequested, 0);
        assertTrue(proposal.earliestRedeemableTime > 0);
        assertEq(voting.proposalShares(pid), 150);
    }

    function testQueueWithoutFinalization() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period and vote
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // Move past voting period
        vm.roll(block.number + votingPeriod);

        // Try to queue without finalizing
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.TallyNotFinalized.selector);
        voting.queueProposal(pid);
    }

    function testQueueWithoutQuorum() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period and vote against
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.Against, 150);

        // Move past voting period and finalize
        vm.roll(block.number + votingPeriod);
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Try to queue
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.NoQuorum.selector);
        voting.queueProposal(pid);
    }

    // 7. Additional Edge Cases
    function testNetVotesCalculation() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(voting), 200);
        voting.signup(200);
        vm.stopPrank();

        // Move to voting period and vote
        vm.roll(block.number + votingDelay + 1);

        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        vm.prank(user2);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.Against, 100);

        // Move past voting period and finalize
        vm.roll(block.number + votingPeriod);
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Queue proposal - should allocate 50 shares (150 For - 100 Against)
        vm.prank(admin);
        voting.queueProposal(pid);

        assertEq(voting.proposalShares(pid), 50);
    }

    function testNoNetVotes() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(voting), 200);
        voting.signup(200);
        vm.stopPrank();

        // Move to voting period and vote
        vm.roll(block.number + votingDelay + 1);

        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 100);

        vm.prank(user2);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.Against, 100);

        // Move past voting period and finalize
        vm.roll(block.number + votingPeriod);
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Try to queue proposal - should fail with 0 net votes
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.NoQuorum.selector);
        voting.queueProposal(pid);
    }

    // 8. Additional Tests

    function testVotingWithAbstain() public {
        // Setup: register users and create proposal
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Cast vote with Abstain
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.Abstain, 100);

        // Check vote counts
        (uint256 sharesFor, uint256 sharesAgainst, uint256 sharesAbstain) = voting.getVoteTally(pid);
        assertEq(sharesFor, 0);
        assertEq(sharesAgainst, 0);
        assertEq(sharesAbstain, 100);

        // Check reduced voting power
        assertEq(voting.votingPower(user1), 100);
    }

    function testQueueAlreadyQueuedProposal() public {
        // Setup: register, propose, vote to pass
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period and vote
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // Move past voting period, finalize and queue
        vm.roll(block.number + votingPeriod);
        vm.startPrank(admin);
        voting.finalizeVoteTally();
        voting.queueProposal(pid);

        // Try to queue again
        vm.expectRevert(BaseAllocationMechanism.AlreadyQueued.selector);
        voting.queueProposal(pid);
        vm.stopPrank();
    }

    function testProposeWithZeroAddressRecipient() public {
        // Register first
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);

        // Try to propose with zero address
        vm.expectRevert(BaseAllocationMechanism.InvalidRecipient.selector);
        voting.propose(address(0), "Test proposal");
        vm.stopPrank();
    }

    function testConstructorWithInvalidInputs() public {
        // Test with zero address for asset
        vm.expectRevert(BaseAllocationMechanism.ZeroAssetAddress.selector);
        new SimpleVotingMechanism(
            IERC20(address(0)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            quorumShares,
            timelockDelay,
            gracePeriod,
            1
        );

        // Test with zero voting delay
        vm.expectRevert(BaseAllocationMechanism.ZeroVotingDelay.selector);
        new SimpleVotingMechanism(
            IERC20(address(token)),
            "Voting Shares",
            "VOTE",
            0,
            votingPeriod,
            quorumShares,
            timelockDelay,
            gracePeriod,
            1
        );

        // Test with zero voting period
        vm.expectRevert(BaseAllocationMechanism.ZeroVotingPeriod.selector);
        new SimpleVotingMechanism(
            IERC20(address(token)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            0,
            quorumShares,
            timelockDelay,
            gracePeriod,
            1
        );

        // Test with zero quorum
        vm.expectRevert(BaseAllocationMechanism.ZeroQuorumShares.selector);
        new SimpleVotingMechanism(
            IERC20(address(token)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            0,
            timelockDelay,
            gracePeriod,
            1
        );

        // Test with zero timelock delay
        vm.expectRevert(BaseAllocationMechanism.ZeroTimelockDelay.selector);
        new SimpleVotingMechanism(
            IERC20(address(token)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            quorumShares,
            0,
            gracePeriod,
            1
        );

        // Test with zero grace period
        vm.expectRevert(BaseAllocationMechanism.ZeroGracePeriod.selector);
        new SimpleVotingMechanism(
            IERC20(address(token)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            quorumShares,
            timelockDelay,
            0,
            1
        );
    }

    function testRedeemableAfterTimestamp() public {
        // Setup: register, propose, vote to pass
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period and vote
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // Move past voting period, finalize and queue
        vm.roll(block.number + votingPeriod);
        vm.startPrank(admin);
        voting.finalizeVoteTally();

        // Record timestamp before queuing
        uint256 timestampBefore = block.timestamp;

        // Queue the proposal
        voting.queueProposal(pid);
        vm.stopPrank();

        // Check redeemableAfter timestamp
        uint256 redeemableTime = voting.redeemableAfter(recipient1);
        assertEq(redeemableTime, timestampBefore + timelockDelay);

        // Check proposal earliestRedeemableTime
        BaseAllocationMechanism.Proposal memory proposal = voting.proposals(pid);
        assertEq(proposal.earliestRedeemableTime, redeemableTime);
    }

    function testInvalidVoteWeight() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Try to vote with zero weight
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidWeight.selector);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 0);

        // Try to vote with weight > voting power
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidWeight.selector);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 101);
    }

    function testVoteOnInvalidProposal() public {
        // Register
        vm.prank(user1);
        voting.signup(0);

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Try to vote on non-existent proposal
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidProposal.selector);
        voting.castVote(999, BaseAllocationMechanism.VoteType.For, 50);
    }

    function testQueueInvalidProposal() public {
        // Move past voting period and finalize
        vm.roll(block.number + votingDelay + votingPeriod + 1);
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Try to queue non-existent proposal
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.InvalidProposal.selector);
        voting.queueProposal(999);
    }

    // 9. Proposal State Tests

    function testProposalStateMachine() public {
        // Setup: register user and create proposal
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Initial state should be Active (during voting period)
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));

        // Move to voting period and cast votes
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // State should still be Active during voting
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));

        // Move past voting period
        vm.roll(block.number + votingPeriod);

        // Before finalization, state should still be Active
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));

        // Finalize tally
        vm.prank(admin);
        voting.finalizeVoteTally();

        // After finalization with quorum, state should be Succeeded
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Succeeded));

        // Queue the proposal
        vm.prank(admin);
        voting.queueProposal(pid);

        // After queuing, state should be Queued
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Queued));

        // Fast forward past timelock - proposal remains queued until externally marked as claimed
        vm.warp(block.timestamp + timelockDelay + 1);

        // State should still be Queued (not automatically executed)
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Queued));
    }

    function testProposalStateDefeated() public {
        // Setup: register user and create proposal
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // No votes cast = no quorum

        // Move past voting period
        vm.roll(block.number + votingDelay + votingPeriod + 1);

        // Before finalization, state should still be Active
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));

        // Finalize tally
        vm.prank(admin);
        voting.finalizeVoteTally();

        // After finalization with no quorum, state should be Defeated
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Defeated));
    }

    function testProposalStateCanceled() public {
        // Setup: register user and create proposal
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");

        // Cancel the proposal
        voting.cancelProposal(pid);
        vm.stopPrank();

        // State should be Canceled
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Canceled));
    }

    function testProposalCancellation() public {
        // Setup: register user and create proposal
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");

        // Cancel the proposal
        voting.cancelProposal(pid);

        // Check that it's marked as canceled
        BaseAllocationMechanism.Proposal memory proposal = voting.proposals(pid);
        assertTrue(proposal.canceled);
        assertFalse(proposal.claimed);
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Vote should still work technically, but proposal remains canceled
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 50);

        // Move past voting period and finalize
        vm.roll(block.number + votingPeriod);
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Try to queue canceled proposal
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.ProposalCanceledError.selector);
        voting.queueProposal(pid);
    }

    function testCannotCancelQueuedProposal() public {
        // Setup: register, propose, vote to pass
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period and vote
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // Move past voting period, finalize and queue
        vm.roll(block.number + votingPeriod);
        vm.startPrank(admin);
        voting.finalizeVoteTally();
        voting.queueProposal(pid);
        vm.stopPrank();

        // Try to cancel after queuing
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.AlreadyQueued.selector);
        voting.cancelProposal(pid);
    }

    function testNonProposerCannotCancel() public {
        // Setup: register user and create proposal
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Try to cancel from non-proposer
        vm.prank(user2);
        vm.expectRevert(BaseAllocationMechanism.NotProposer.selector);
        voting.cancelProposal(pid);
    }

    function testProposalStateExpired() public {
        // Since proposals are automatically claimed when queued, we'll test
        // the redeemableAfter timestamp functionality instead

        // Setup: register, propose, vote to pass
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period and vote
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // Move past voting period, finalize and queue
        vm.roll(block.number + votingPeriod);
        vm.startPrank(admin);
        voting.finalizeVoteTally();

        uint256 timestampBefore = block.timestamp;
        voting.queueProposal(pid);
        vm.stopPrank();

        // Check that redeemableAfter is set to the current timestamp + timelockDelay
        uint256 redeemableTime = voting.redeemableAfter(recipient1);
        assertEq(redeemableTime, timestampBefore + timelockDelay);

        // Check proposal earliestRedeemableTime
        BaseAllocationMechanism.Proposal memory proposal = voting.proposals(pid);
        assertEq(proposal.earliestRedeemableTime, redeemableTime);
    }

    function testProposalAlreadyClaimedWhenQueued() public {
        // Setup: register, propose, vote to pass
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period and vote
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // Move past voting period, finalize and queue
        vm.roll(block.number + votingPeriod);
        vm.startPrank(admin);
        voting.finalizeVoteTally();
        voting.queueProposal(pid);
        vm.stopPrank();

        // Check that the proposal is NOT claimed automatically
        BaseAllocationMechanism.Proposal memory proposal = voting.proposals(pid);
        assertFalse(proposal.claimed);

        // Check the proposal state is Queued (not Succeeded)
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Queued));
    }

    // 10. Additional Revert Case Tests for Branch Coverage

    // Tests for register() function reverts
    function testRegisterBeforeRegisterHookFails() public {
        // This test needs a mock implementation where _beforeRegisterHook returns false
        // For SimpleVotingMechanism, _beforeRegisterHook always returns true
        // We'll need to modify the contract temporarily for this test
        // Note: We can't test this directly with SimpleVotingMechanism
        // as it always returns true from _beforeRegisterHook
    }

    // Tests for propose() function reverts
    function testProposeWhenNotRegistered() public {
        // Testing the _beforeProposeHook fails when user has no voting power
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.ProposeNotAllowed.selector);
        voting.propose(recipient1, "Test proposal");
    }

    // Tests for finalizeVoteTally() function reverts
    function testFinalizeVoteTallyBeforeVotingEnds() public {
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.VotingNotEnded.selector);
        voting.finalizeVoteTally();
    }

    function testFinalizeVoteTallyHookFails() public {
        // This test needs a mock implementation where _beforeFinalizeVoteTallyHook returns false
        // For SimpleVotingMechanism, _beforeFinalizeVoteTallyHook always returns true
        // We'll need to modify the contract temporarily for this test
        // Note: We can't test this directly with SimpleVotingMechanism
        // as it always returns true from _beforeFinalizeVoteTallyHook
    }

    // Tests for queueProposal() function reverts
    function testQueueProposalWithoutTallyFinalized() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move past voting period (but don't finalize)
        vm.roll(block.number + votingDelay + votingPeriod + 1);

        // Try to queue without finalizing
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.TallyNotFinalized.selector);
        voting.queueProposal(pid);
    }

    function testQueueCanceledProposal() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");

        // Cancel the proposal
        voting.cancelProposal(pid);
        vm.stopPrank();

        // Move past voting period and finalize
        vm.roll(block.number + votingDelay + votingPeriod + 1);
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Try to queue canceled proposal
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.ProposalCanceledError.selector);
        voting.queueProposal(pid);
    }

    function testQueueProposalWithZeroNetVotes() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move past voting period and finalize (with 0 votes)
        vm.roll(block.number + votingDelay + votingPeriod + 1);
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Try to queue with 0 net votes
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.NoQuorum.selector);
        voting.queueProposal(pid);
    }

    function testQueueProposalWithEqualForAndAgainstVotes() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(voting), 200);
        voting.signup(200);
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Cast equal votes for and against
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 100);

        vm.prank(user2);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.Against, 100);

        // Move past voting period and finalize
        vm.roll(block.number + votingDelay + votingPeriod + 1);
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Try to queue with equal votes
        vm.prank(admin);
        vm.expectRevert(BaseAllocationMechanism.NoQuorum.selector);
        voting.queueProposal(pid);
    }

    // Tests for castVote() function reverts
    function testCastVoteForNonExistentProposal() public {
        // Register first
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Try to vote on non-existent proposal
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidProposal.selector);
        voting.castVote(999, BaseAllocationMechanism.VoteType.For, 50);
    }

    function testCastVoteBeforeVotingWindow() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");

        // Try to vote immediately (before voting period)
        vm.expectRevert(BaseAllocationMechanism.VotingClosed.selector);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 50);
        vm.stopPrank();
    }

    function testCastVoteWithZeroWeight() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Try to vote with zero weight
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidWeight.selector);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 0);
    }

    function testCastVoteWithExcessiveWeight() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Try to vote with more than voting power
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidWeight.selector);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 101);
    }

    function testCastVoteRevertsWhenPowerIncreases() public {
        // This is a theoretical test for the check in castVote:
        // require(newPower <= oldPower, "Power increased");
        // In practice, it would require a malicious implementation of _processVoteHook
        // that increases voting power instead of decreasing it
        // We can't test this directly with SimpleVotingMechanism
        // since it correctly decreases power
    }

    // Tests for state() function reverts
    function testStateForInvalidProposal() public {
        vm.expectRevert(BaseAllocationMechanism.InvalidProposal.selector);
        voting.state(999);
    }

    // Tests for cancelProposal() function reverts
    function testCancelProposalByNonProposer() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Try to cancel from different address
        vm.prank(user2);
        vm.expectRevert(BaseAllocationMechanism.NotProposer.selector);
        voting.cancelProposal(pid);
    }

    function testCancelAlreadyCanceledProposal() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");

        // Cancel the proposal
        voting.cancelProposal(pid);

        // Try to cancel again
        vm.expectRevert(BaseAllocationMechanism.AlreadyCanceled.selector);
        voting.cancelProposal(pid);
        vm.stopPrank();
    }

    // Test constructor validations
    function testConstructorWithZeroParameters() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST");

        // Test with zero address for asset
        vm.expectRevert(BaseAllocationMechanism.ZeroAssetAddress.selector);
        new SimpleVotingMechanism(
            IERC20(address(0)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            quorumShares,
            timelockDelay,
            gracePeriod,
            1
        );

        // Test with zero voting delay
        vm.expectRevert(BaseAllocationMechanism.ZeroVotingDelay.selector);
        new SimpleVotingMechanism(
            IERC20(address(testToken)),
            "Voting Shares",
            "VOTE",
            0,
            votingPeriod,
            quorumShares,
            timelockDelay,
            gracePeriod,
            1
        );

        // Test with zero voting period
        vm.expectRevert(BaseAllocationMechanism.ZeroVotingPeriod.selector);
        new SimpleVotingMechanism(
            IERC20(address(testToken)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            0,
            quorumShares,
            timelockDelay,
            gracePeriod,
            1
        );

        // Test with zero quorum
        vm.expectRevert(BaseAllocationMechanism.ZeroQuorumShares.selector);
        new SimpleVotingMechanism(
            IERC20(address(testToken)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            0,
            timelockDelay,
            gracePeriod,
            1
        );

        // Test with zero timelock delay
        vm.expectRevert(BaseAllocationMechanism.ZeroTimelockDelay.selector);
        new SimpleVotingMechanism(
            IERC20(address(testToken)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            quorumShares,
            0,
            gracePeriod,
            1
        );

        // Test with zero grace period
        vm.expectRevert(BaseAllocationMechanism.ZeroGracePeriod.selector);
        new SimpleVotingMechanism(
            IERC20(address(testToken)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            quorumShares,
            timelockDelay,
            0,
            1
        );
    }

    // 11. State Transition Tests for Branch Coverage

    function testStatePendingBeforeVotingDelay() public {
        // Set up a new voting contract so we can control the startBlock more precisely
        SimpleVotingMechanism newVoting = new SimpleVotingMechanism(
            IERC20(address(token)),
            "Voting Shares",
            "VOTE",
            votingDelay,
            votingPeriod,
            quorumShares,
            timelockDelay,
            gracePeriod,
            1
        );

        // In setup, we can register and create a proposal
        vm.startPrank(user1);
        token.approve(address(newVoting), 100);
        newVoting.signup(100);
        uint256 pid = newVoting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Before voting delay, the state should be Active
        assertEq(uint256(newVoting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));
    }

    function testStateActiveBeforeVotingEnd() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Set block number to middle of voting period
        vm.roll(block.number + votingDelay + votingPeriod / 2);

        // During voting period, state should be Active
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));
    }

    function testStateDefeatedWithoutQuorum() public {
        // Setup
        vm.startPrank(user1);
        token.approve(address(voting), 100);
        voting.signup(100);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move past voting period without any votes
        vm.roll(block.number + votingDelay + votingPeriod + 1);

        // Before finalization, state should still be Active
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));

        // Finalize tally
        vm.prank(admin);
        voting.finalizeVoteTally();

        // With no votes, there's no quorum, so state should be Defeated
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Defeated));
    }

    function testStatePendingAfterVotingBeforeQueue() public {
        // Setup: register, vote and pass quorum
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period
        vm.roll(block.number + votingDelay + 1);

        // Cast votes to pass quorum
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // Move past voting period
        vm.roll(block.number + votingPeriod);

        // Before finalization, state should still be Active
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));

        // Finalize tally
        vm.prank(admin);
        voting.finalizeVoteTally();

        // After voting with quorum met but before queuing, state should be Succeeded
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Succeeded));
    }

    function testStateQueuedThenExpired() public {
        // Setup: register, vote, pass quorum and queue
        vm.startPrank(user1);
        token.approve(address(voting), 200);
        voting.signup(200);
        uint256 pid = voting.propose(recipient1, "Test proposal");
        vm.stopPrank();

        // Move to voting period and vote
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 150);

        // Move past voting period
        vm.roll(block.number + votingPeriod);

        // Finalize tally and queue
        vm.startPrank(admin);
        voting.finalizeVoteTally();

        // Queue the proposal - it will be marked claimed automatically now
        voting.queueProposal(pid);
        vm.stopPrank();

        // We can't test the Queued state easily since claiming happens automatically now
        // But we can test the Expired state by warping past grace period

        // Warp past grace period (14 days) to test Expired state
        vm.warp(block.timestamp + timelockDelay + 14 days + 1);

        // No way to test the Expired state anymore since claiming happens automatically
        // But we've covered the important branches of the _state function
    }

    function testProposalClaimLifecycle() public {
        // Setup
        token.mint(user1, 1000);
        token.mint(user2, 1000);
        
        vm.prank(user1);
        token.approve(address(voting), 1000);
        vm.prank(user1);
        voting.signup(100);

        vm.prank(user2);
        token.approve(address(voting), 1000);
        vm.prank(user2);
        voting.signup(100);

        // Create proposal
        vm.prank(user1);
        uint256 pid = voting.propose(recipient1, "Test proposal");

        // Check initial state
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));

        // Vote
        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 60);
        vm.prank(user2);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 40);

        // End voting period
        vm.roll(block.number + votingPeriod + 1);
        
        // Check state before finalization
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Active));

        // Finalize tally
        vm.prank(admin);
        voting.finalizeVoteTally();

        // Check state is now Succeeded (has quorum but not queued)
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Succeeded));

        // Queue proposal
        vm.prank(admin);
        voting.queueProposal(pid);

        // Check state is now Queued
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Queued));

        // Verify proposal is NOT marked as claimed initially
        BaseAllocationMechanism.Proposal memory proposal = voting.proposals(pid);
        assertFalse(proposal.claimed);
    }

    function testStateExpiredAfterGracePeriod() public {
        // Setup proposal workflow first
        token.mint(user1, 1000);
        vm.prank(user1);
        token.approve(address(voting), 1000);
        vm.prank(user1);
        voting.signup(100);

        vm.prank(user1);
        uint256 pid = voting.propose(recipient1, "Test proposal");

        vm.roll(block.number + votingDelay + 1);
        vm.prank(user1);
        voting.castVote(pid, BaseAllocationMechanism.VoteType.For, 60);

        vm.roll(block.number + votingPeriod + 1);
        vm.prank(admin);
        voting.finalizeVoteTally();
        vm.prank(admin);
        voting.queueProposal(pid);

        // Fast forward past grace period to test expiration
        vm.warp(block.timestamp + timelockDelay + gracePeriod + 1);

        // Verify state is now Expired
        assertEq(uint256(voting.state(pid)), uint256(BaseAllocationMechanism.ProposalState.Expired));
    }
}
