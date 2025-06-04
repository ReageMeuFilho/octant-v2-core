// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {QuadraticVotingMechanism} from "src/allocation-mechanism/mechanism/QuadraticVotingMechanism.sol";
import {BaseAllocationMechanism} from "src/allocation-mechanism/BaseAllocationMechanism.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract QuadraticVotingMechanismTest is Test {
    QuadraticVotingMechanism public mechanism;
    MockERC20 public asset;
    
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public user3 = address(4);
    address public recipient1 = address(5);
    address public recipient2 = address(6);
    
    uint256 public constant VOTING_DELAY = 1000;
    uint256 public constant VOTING_PERIOD = 2000;
    uint256 public constant QUORUM_SHARES = 100;
    uint256 public constant TIMELOCK_DELAY = 7 days;
    uint256 public constant START_BLOCK = 1;
    uint256 public constant ALPHA_NUMERATOR = 5;
    uint256 public constant ALPHA_DENOMINATOR = 10; // 50% quadratic, 50% linear
    
    function setUp() public {
        asset = new MockERC20(18);
        vm.prank(owner);
        mechanism = new QuadraticVotingMechanism(
            asset,
            "Test Voting Mechanism",
            "TVM",
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_SHARES,
            TIMELOCK_DELAY,
            START_BLOCK,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR
        );
        
        // Mint tokens to users
        asset.mint(user1, 10000e18);
        asset.mint(user2, 5000e18);
        asset.mint(user3, 2000e18);
        
        // Approve mechanism to spend tokens
        vm.prank(user1);
        asset.approve(address(mechanism), type(uint256).max);
        vm.prank(user2);
        asset.approve(address(mechanism), type(uint256).max);
        vm.prank(user3);
        asset.approve(address(mechanism), type(uint256).max);
    }
    
    // ===== Constructor Tests =====
    
    function testConstructorParameters() public view {
        assertEq(address(mechanism.asset()), address(asset));
        assertEq(mechanism.name(), "Test Voting Mechanism");
        assertEq(mechanism.symbol(), "TVM");
        assertEq(mechanism.votingDelay(), VOTING_DELAY);
        assertEq(mechanism.votingPeriod(), VOTING_PERIOD);
        assertEq(mechanism.quorumShares(), QUORUM_SHARES);
        assertEq(mechanism.timelockDelay(), TIMELOCK_DELAY);
        assertEq(mechanism.startBlock(), START_BLOCK);
        assertEq(mechanism.alphaNumerator(), ALPHA_NUMERATOR);
        assertEq(mechanism.alphaDenominator(), ALPHA_DENOMINATOR);
    }
    
    function testConstructorWithInvalidParameters() public {
        vm.startPrank(owner);
        
        // Test zero voting delay
        vm.expectRevert(BaseAllocationMechanism.ZeroVotingDelay.selector);
        new QuadraticVotingMechanism(
            asset, "Test", "TST", 0, VOTING_PERIOD, QUORUM_SHARES, TIMELOCK_DELAY, START_BLOCK, ALPHA_NUMERATOR, ALPHA_DENOMINATOR
        );
        
        // Test zero voting period
        vm.expectRevert(BaseAllocationMechanism.ZeroVotingPeriod.selector);
        new QuadraticVotingMechanism(
            asset, "Test", "TST", VOTING_DELAY, 0, QUORUM_SHARES, TIMELOCK_DELAY, START_BLOCK, ALPHA_NUMERATOR, ALPHA_DENOMINATOR
        );
        
        // Test zero quorum
        vm.expectRevert(BaseAllocationMechanism.ZeroQuorumShares.selector);
        new QuadraticVotingMechanism(
            asset, "Test", "TST", VOTING_DELAY, VOTING_PERIOD, 0, TIMELOCK_DELAY, START_BLOCK, ALPHA_NUMERATOR, ALPHA_DENOMINATOR
        );
        
        // Test zero timelock delay
        vm.expectRevert(BaseAllocationMechanism.ZeroTimelockDelay.selector);
        new QuadraticVotingMechanism(
            asset, "Test", "TST", VOTING_DELAY, VOTING_PERIOD, QUORUM_SHARES, 0, START_BLOCK, ALPHA_NUMERATOR, ALPHA_DENOMINATOR
        );
        
        // Test alpha > 1 (numerator > denominator) - this is checked first
        vm.expectRevert(QuadraticVotingMechanism.AlphaMustBeLEQOne.selector);
        new QuadraticVotingMechanism(
            asset, "Test", "TST", VOTING_DELAY, VOTING_PERIOD, QUORUM_SHARES, TIMELOCK_DELAY, START_BLOCK, 11, 10
        );
        
        // Test zero denominator with numerator <= denominator to avoid the first check
        vm.expectRevert(QuadraticVotingMechanism.AlphaDenominatorMustBePositive.selector);
        new QuadraticVotingMechanism(
            asset, "Test", "TST", VOTING_DELAY, VOTING_PERIOD, QUORUM_SHARES, TIMELOCK_DELAY, START_BLOCK, 0, 0
        );
        
        vm.stopPrank();
    }
    
    // ===== Registration Tests =====
    
    function testSuccessfulRegistration() public {
        uint256 deposit = 1000e18;
        
        vm.prank(user1);
        mechanism.signup(deposit);
        
        assertEq(mechanism.votingPower(user1), deposit);
        assertEq(asset.balanceOf(user1), 10000e18 - deposit);
        assertEq(asset.balanceOf(address(mechanism)), deposit);
    }
    
    function testRegistrationWithZeroDeposit() public {
        vm.prank(user1);
        mechanism.signup(0);
        
        assertEq(mechanism.votingPower(user1), 0);
        assertEq(asset.balanceOf(user1), 10000e18);
        assertEq(asset.balanceOf(address(mechanism)), 0);
    }
    
    function testDoubleRegistration() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.AlreadyRegistered.selector);
        mechanism.signup(500e18);
    }
    
    function testRegistrationAfterVotingPeriod() public {
        // Move to after voting period
        vm.roll(START_BLOCK + VOTING_DELAY + VOTING_PERIOD + 1);
        
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.VotingEnded.selector);
        mechanism.signup(1000e18);
    }
    
    // ===== Proposal Tests =====
    
    function testProposalCreation() public {
        // Register user first
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        assertEq(pid, 1);
        
        BaseAllocationMechanism.Proposal memory proposal = mechanism.proposals(pid);
        assertEq(proposal.proposer, user1);
        assertEq(proposal.recipient, recipient1);
        assertEq(proposal.description, "Test proposal");
        assertEq(proposal.claimed, false);
        assertEq(proposal.canceled, false);
    }
    
    function testProposalCreationByUnregisteredUser() public {
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.ProposeNotAllowed.selector);
        mechanism.propose(recipient1, "Test proposal");
    }
    
    function testProposalWithZeroAddressRecipient() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidRecipient.selector);
        mechanism.propose(address(0), "Test proposal");
    }
    
    function testProposalWithUsedRecipient() public {
        // Register users
        vm.prank(user1);
        mechanism.signup(1000e18);
        vm.prank(user2);
        mechanism.signup(500e18);
        
        // First proposal
        vm.prank(user1);
        mechanism.propose(recipient1, "First proposal");
        
        // Second proposal with same recipient should fail
        vm.prank(user2);
        vm.expectRevert(BaseAllocationMechanism.RecipientUsed.selector);
        mechanism.propose(recipient1, "Second proposal");
    }
    
    // ===== Voting Tests =====
    
    function testQuadraticVoting() public {
        // Setup: Register users and create proposal
        vm.prank(user1);
        mechanism.signup(1000e18); // 1000 voting power
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        // Move to voting period
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        // Vote with weight 10, should cost 10^2 = 100 voting power
        vm.prank(user1);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 10);
        
        // Check remaining voting power
        assertEq(mechanism.votingPower(user1), 1000e18 - 100);
        
        // Check total voting power tracked
        assertEq(mechanism.totalVotingPower(), 10);
        
        // Check proposal funding
        (uint256 sumContributions, uint256 sumSquareRoots, uint256 quadraticFunding, uint256 linearFunding) = 
            mechanism.getProposalFunding(pid);
        
        assertEq(sumContributions, 100); // contribution = quadratic cost
        assertEq(sumSquareRoots, 10);    // sqrt(100) = 10
        assertEq(linearFunding, 100);    // same as contribution
        assertEq(quadraticFunding, 50); // alpha-weighted: (sqrt(100))^2 * 0.5 = 50
    }
    
    function testMultipleVotesOnSameProposal() public {
        // Setup
        vm.prank(user1);
        mechanism.signup(1000e18);
        vm.prank(user2);
        mechanism.signup(500e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        // User1 votes with weight 10 (cost 100)
        vm.prank(user1);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 10);
        
        // User2 votes with weight 5 (cost 25)
        vm.prank(user2);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 5);
        
        // Check total voting power
        assertEq(mechanism.totalVotingPower(), 15); // 10 + 5
        
        // Check individual remaining power
        assertEq(mechanism.votingPower(user1), 1000e18 - 100);
        assertEq(mechanism.votingPower(user2), 500e18 - 25);
        
        // Check proposal funding (should be cumulative)
        (uint256 sumContributions, uint256 sumSquareRoots, uint256 quadraticFunding, uint256 linearFunding) = 
            mechanism.getProposalFunding(pid);
        
        assertEq(sumContributions, 125); // 100 + 25
        assertEq(sumSquareRoots, 15);    // 10 + 5
        assertEq(linearFunding, 125);    // same as contributions
        assertEq(quadraticFunding, 112); // alpha-weighted: (10 + 5)^2 * 0.5 = 225 * 0.5 = 112 (rounded)
    }
    
    function testVoteWithInsufficientVotingPower() public {
        vm.prank(user1);
        mechanism.signup(100); // Only 100 voting power
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        // Try to vote with weight 20, which would cost 400 > 100
        vm.prank(user1);
        vm.expectRevert(QuadraticVotingMechanism.InsufficientVotingPowerForQuadraticCost.selector);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 20);
    }
    
    function testOnlyForVotesSupported() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        // Against votes should revert
        vm.prank(user1);
        vm.expectRevert(QuadraticVotingMechanism.OnlyForVotesSupported.selector);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.Against, 10);
        
        // Abstain votes should revert
        vm.prank(user1);
        vm.expectRevert(QuadraticVotingMechanism.OnlyForVotesSupported.selector);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.Abstain, 10);
    }
    
    function testVoteWeightTooLarge() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        // Weight larger than uint128.max should revert with InvalidWeight since it's too large for voting power
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidWeight.selector);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, uint256(type(uint128).max) + 1);
    }
    
    function testDoubleVoting() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        // First vote
        vm.prank(user1);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 10);
        
        // Second vote should fail
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.AlreadyVoted.selector);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 5);
    }
    
    // ===== Quorum Tests =====
    
    function testQuorumWithSufficientFunding() public {
        vm.prank(user1);
        mechanism.signup(10000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        // Vote with enough weight to meet quorum
        // With alpha = 0.5, we need sufficient weighted funding >= 100
        // Let's vote with weight 15: quadratic = 225, linear = 225, weighted = 0.5*225 + 0.5*225 = 225
        vm.prank(user1);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 15);
        
        // Move past voting period
        vm.roll(START_BLOCK + VOTING_DELAY + VOTING_PERIOD + 1);
        
        // Finalize tally
        vm.prank(owner);
        mechanism.finalizeVoteTally();
        
        // Check state - should be succeeded after queuing
        vm.prank(owner);
        mechanism.queueProposal(pid);
        
        assertEq(uint8(mechanism.state(pid)), uint8(BaseAllocationMechanism.ProposalState.Succeeded));
    }
    
    function testQuorumWithInsufficientFunding() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        // Vote with small weight - not enough for quorum
        vm.prank(user1);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 5);
        
        vm.roll(START_BLOCK + VOTING_DELAY + VOTING_PERIOD + 1);
        
        vm.prank(owner);
        mechanism.finalizeVoteTally();
        
        // Should fail to queue due to insufficient quorum
        vm.prank(owner);
        vm.expectRevert(BaseAllocationMechanism.NoQuorum.selector);
        mechanism.queueProposal(pid);
    }
    
    // ===== Alpha Parameter Tests =====
    
    function testSetAlpha() public {
        // Only owner can set alpha
        vm.prank(owner);
        mechanism.setAlpha(3, 4); // 75% quadratic, 25% linear
        
        assertEq(mechanism.alphaNumerator(), 3);
        assertEq(mechanism.alphaDenominator(), 4);
    }
    
    function testSetAlphaByNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        mechanism.setAlpha(1, 2);
    }
    
    function testAlphaAffectsFunding() public {
        // Setup two identical voting scenarios with different alpha values
        QuadraticVotingMechanism mechanism2;
        vm.prank(owner);
        mechanism2 = new QuadraticVotingMechanism(
            asset,
            "Test2",
            "TST2", 
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_SHARES,
            TIMELOCK_DELAY,
            START_BLOCK,
            9, // 90% quadratic
            10
        );
        
        // Register and vote on mechanism1 (50% quadratic)
        vm.prank(user1);
        mechanism.signup(1000e18);
        vm.prank(user1);
        uint256 pid1 = mechanism.propose(recipient1, "Test 1");
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        vm.prank(user1);
        mechanism.castVote(pid1, BaseAllocationMechanism.VoteType.For, 20); // Higher weight to meet quorum
        
        // Register and vote on mechanism2 (90% quadratic)
        vm.prank(user2);
        asset.approve(address(mechanism2), type(uint256).max);
        vm.prank(user2);
        mechanism2.signup(1000e18);
        vm.prank(user2);
        uint256 pid2 = mechanism2.propose(recipient2, "Test 2");
        vm.prank(user2);
        mechanism2.castVote(pid2, BaseAllocationMechanism.VoteType.For, 20); // Higher weight to meet quorum
        
        // Move past voting and finalize both
        vm.roll(START_BLOCK + VOTING_DELAY + VOTING_PERIOD + 1);
        vm.startPrank(owner);
        mechanism.finalizeVoteTally();
        mechanism2.finalizeVoteTally();
        vm.stopPrank();
        
        // Queue and check share allocation
        vm.startPrank(owner);
        mechanism.queueProposal(pid1);
        mechanism2.queueProposal(pid2);
        vm.stopPrank();
        
        uint256 shares1 = mechanism.proposalShares(pid1);
        uint256 shares2 = mechanism2.proposalShares(pid2);
        
        // With higher alpha (more quadratic), mechanism2 should allocate more shares
        // Both have same votes but different alpha weighting
        assertGt(shares2, shares1);
    }
    
    // ===== State Machine Tests =====
    
    function testProposalStateMachine() public {
        vm.prank(user1);
        mechanism.signup(10000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        // Make sure we're before start block  
        vm.roll(START_BLOCK - 1);
        // Before start block - should be Pending
        assertEq(uint8(mechanism.state(pid)), uint8(BaseAllocationMechanism.ProposalState.Pending));
        
        // During voting delay - should be Active (we're past start block)  
        vm.roll(START_BLOCK + VOTING_DELAY - 1);
        assertEq(uint8(mechanism.state(pid)), uint8(BaseAllocationMechanism.ProposalState.Active));
        
        // During voting period - should be Active
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        assertEq(uint8(mechanism.state(pid)), uint8(BaseAllocationMechanism.ProposalState.Active));
        
        // Vote to meet quorum
        vm.prank(user1);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 15);
        
        // After voting period, before finalization - should be Pending
        vm.roll(START_BLOCK + VOTING_DELAY + VOTING_PERIOD + 1);
        assertEq(uint8(mechanism.state(pid)), uint8(BaseAllocationMechanism.ProposalState.Pending));
        
        // After finalization and queuing - should be Succeeded
        vm.prank(owner);
        mechanism.finalizeVoteTally();
        vm.prank(owner);
        mechanism.queueProposal(pid);
        assertEq(uint8(mechanism.state(pid)), uint8(BaseAllocationMechanism.ProposalState.Succeeded));
    }
    
    function testProposalCancellation() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        // Proposer can cancel
        vm.prank(user1);
        mechanism.cancelProposal(pid);
        
        assertEq(uint8(mechanism.state(pid)), uint8(BaseAllocationMechanism.ProposalState.Canceled));
        
        BaseAllocationMechanism.Proposal memory proposal = mechanism.proposals(pid);
        assertTrue(proposal.canceled);
    }
    
    function testNonProposerCannotCancel() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.prank(user2);
        vm.expectRevert(BaseAllocationMechanism.NotProposer.selector);
        mechanism.cancelProposal(pid);
    }
    
    // ===== Integration Tests =====
    
    function testCompleteVotingFlow() public {
        // Multiple users register with different amounts
        vm.prank(user1);
        mechanism.signup(10000e18);
        vm.prank(user2);
        mechanism.signup(5000e18);
        vm.prank(user3);
        mechanism.signup(2000e18);
        
        // Create proposals
        vm.prank(user1);
        uint256 pid1 = mechanism.propose(recipient1, "Proposal 1");
        vm.prank(user2);
        uint256 pid2 = mechanism.propose(recipient2, "Proposal 2");
        
        // Move to voting period
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        // Users vote on different proposals with different weights
        vm.prank(user1);
        mechanism.castVote(pid1, BaseAllocationMechanism.VoteType.For, 20); // cost: 400
        
        vm.prank(user2);
        mechanism.castVote(pid1, BaseAllocationMechanism.VoteType.For, 15); // cost: 225
        
        vm.prank(user3);
        mechanism.castVote(pid2, BaseAllocationMechanism.VoteType.For, 10); // cost: 100
        
        // Check total voting power distributed
        assertEq(mechanism.totalVotingPower(), 45); // 20 + 15 + 10
        
        // Move past voting period
        vm.roll(START_BLOCK + VOTING_DELAY + VOTING_PERIOD + 1);
        
        // Finalize tally
        vm.prank(owner);
        mechanism.finalizeVoteTally();
        
        // Queue proposals that meet quorum
        vm.prank(owner);
        mechanism.queueProposal(pid1);
        
        // Check proposal 1 has more shares than proposal 2 due to more votes
        uint256 shares1 = mechanism.proposalShares(pid1);
        assertGt(shares1, 0);
        
        // Proposal 2 might not meet quorum with only 10 vote weight
        // Check if it can be queued
        try mechanism.queueProposal(pid2) {
            uint256 shares2 = mechanism.proposalShares(pid2);
            assertLt(shares2, shares1); // Should have fewer shares
        } catch {
            // Proposal 2 didn't meet quorum, which is expected
        }
    }
    
    // ===== Error Handling Tests =====
    
    function testGetProposalFundingInvalidProposal() public {
        vm.expectRevert(BaseAllocationMechanism.InvalidProposal.selector);
        mechanism.getProposalFunding(999);
    }
    
    function testVoteOnInvalidProposal() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidProposal.selector);
        mechanism.castVote(999, BaseAllocationMechanism.VoteType.For, 10);
    }
    
    function testZeroAddressCannotPropose() public {
        // The hook should prevent zero address from proposing, but it's covered by contract logic
        // This test verifies the custom error exists and can be triggered
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidRecipient.selector);
        mechanism.propose(address(0), "Test proposal");
    }
    
    // ===== Gas Usage Tests =====
    
    function testGasUsageVoting() public {
        vm.prank(user1);
        mechanism.signup(10000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        uint256 gasStart = gasleft();
        vm.prank(user1);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 10);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for voting:", gasUsed);
        assertLt(gasUsed, 300000); // Should be reasonable gas usage
    }
    
    // ===== Edge Cases =====
    
    function testMaximumVoteWeight() public {
        // Test voting with a large but safe weight
        uint256 maxWeight = 1000000; // 1M weight
        uint256 maxCost = maxWeight * maxWeight;
        
        vm.prank(user1);
        mechanism.signup(maxCost);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        vm.prank(user1);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, maxWeight);
        
        assertEq(mechanism.votingPower(user1), 0); // All power used
        assertEq(mechanism.totalVotingPower(), maxWeight);
    }
    
    function testZeroVoteWeight() public {
        vm.prank(user1);
        mechanism.signup(1000e18);
        
        vm.prank(user1);
        uint256 pid = mechanism.propose(recipient1, "Test proposal");
        
        vm.roll(START_BLOCK + VOTING_DELAY + 1);
        
        vm.prank(user1);
        vm.expectRevert(BaseAllocationMechanism.InvalidWeight.selector);
        mechanism.castVote(pid, BaseAllocationMechanism.VoteType.For, 0);
    }
}
