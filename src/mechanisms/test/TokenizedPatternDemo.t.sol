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

contract TokenizedPatternDemoTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;
    address owner;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address dave = address(0x4);
    address eve = address(0x5);

    // Helper function to access delegated functions
    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
    }

    function setUp() public {
        owner = address(this);

        // Deploy factory (which deploys shared implementation)
        factory = new AllocationMechanismFactory();

        // Deploy mock token
        token = new ERC20Mock();
        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
        token.mint(dave, 500 ether);
        token.mint(eve, 300 ether);

        // Deploy a simple voting mechanism
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Test Voting",
            symbol: "TVOTE",
            votingDelay: 100,
            votingPeriod: 1000,
            quorumShares: 100 ether,
            timelockDelay: 1 days,
            gracePeriod: 7 days,
            startBlock: block.number + 10,
            owner: address(0) // Will be overridden by factory
        });
        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }

    // ========== PATTERN DEPLOYMENT TESTS ==========

    function testPatternDeployment() public view {
        // Verify deployment
        assertEq(factory.getDeployedCount(), 1);
        assertEq(address(mechanism), factory.getDeployedMechanism(0));
        assertTrue(factory.isMechanism(address(mechanism)));

        // Verify shared implementation is deployed
        assertNotEq(factory.tokenizedAllocationImplementation(), address(0));
    }

    function testDelegateCallPattern() public view {
        // The mechanism should have the correct name via delegatecall
        assertEq(_tokenized(address(mechanism)).name(), "Test Voting");
        assertEq(_tokenized(address(mechanism)).symbol(), "TVOTE");
        assertEq(address(_tokenized(address(mechanism)).asset()), address(token));

        // Verify configuration parameters accessible via delegatecall
        assertEq(_tokenized(address(mechanism)).votingDelay(), 100);
        assertEq(_tokenized(address(mechanism)).votingPeriod(), 1000);
        assertEq(_tokenized(address(mechanism)).quorumShares(), 100 ether);
        assertEq(_tokenized(address(mechanism)).timelockDelay(), 1 days);
        assertEq(_tokenized(address(mechanism)).gracePeriod(), 7 days);
        assertEq(_tokenized(address(mechanism)).startBlock(), block.number + 10);
    }

    function testStorageIsolation() public {
        // Deploy another mechanism using same implementation
        AllocationConfig memory config2 = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Another Voting",
            symbol: "AVOTE",
            votingDelay: 50,
            votingPeriod: 500,
            quorumShares: 50 ether,
            timelockDelay: 2 days,
            gracePeriod: 14 days,
            startBlock: block.number + 5,
            owner: address(0) // Will be overridden by factory
        });
        address mechanism2Addr = factory.deploySimpleVotingMechanism(config2);

        // Each should have independent storage
        assertEq(_tokenized(address(mechanism)).name(), "Test Voting");
        assertEq(_tokenized(mechanism2Addr).name(), "Another Voting");

        // Configuration should be independent
        assertEq(_tokenized(address(mechanism)).votingDelay(), 100);
        assertEq(_tokenized(mechanism2Addr).votingDelay(), 50);
        assertEq(_tokenized(address(mechanism)).quorumShares(), 100 ether);
        assertEq(_tokenized(mechanism2Addr).quorumShares(), 50 ether);

        // Proposals should be independent
        assertEq(_tokenized(address(mechanism)).getProposalCount(), 0);
        assertEq(_tokenized(mechanism2Addr).getProposalCount(), 0);

        // State should be independent
        assertFalse(_tokenized(address(mechanism)).tallyFinalized());
        assertFalse(_tokenized(mechanism2Addr).tallyFinalized());
    }

    // ========== REGISTRATION TESTS ==========

    function testUserRegistration() public {
        // Move to valid registration period (before voting starts)
        vm.roll(block.number + 10);

        // Alice signs up with deposit
        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        // Check voting power (1:1 deposit to power in SimpleVoting)
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 100 ether);

        // Check remaining power
        assertEq(_tokenized(address(mechanism)).getRemainingVotingPower(alice), 100 ether);

        // Check token balance transferred
        assertEq(token.balanceOf(alice), 900 ether);
        assertEq(token.balanceOf(address(mechanism)), 100 ether);
    }

    function testRegistrationWithZeroDeposit() public {
        vm.roll(block.number + 10);

        // Alice can register with zero deposit
        vm.prank(alice);
        _tokenized(address(mechanism)).signup(0);

        // Should have zero voting power
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 0);

        // No tokens transferred
        assertEq(token.balanceOf(alice), 1000 ether);
        assertEq(token.balanceOf(address(mechanism)), 0);
    }

    function testRegistrationFailures() public {
        vm.roll(block.number + 10);

        // Register alice first
        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        // Cannot register twice
        vm.startPrank(alice);
        token.approve(address(mechanism), 50 ether);
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.AlreadyRegistered.selector, alice));
        _tokenized(address(mechanism)).signup(50 ether);
        vm.stopPrank();
    }

    // ========== PROPOSAL TESTS ==========

    function testProposalCreation() public {
        // Setup: Register alice
        vm.roll(block.number + 10);
        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        // Alice creates a proposal
        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie's project");

        // Verify proposal
        assertEq(pid, 1);
        assertEq(_tokenized(address(mechanism)).getProposalCount(), 1);

        // Check proposal details via delegatecall
        TokenizedAllocationMechanism.Proposal memory proposal = _tokenized(address(mechanism)).proposals(pid);
        assertEq(proposal.proposer, alice);
        assertEq(proposal.recipient, charlie);
        assertEq(proposal.description, "Fund Charlie's project");
        assertFalse(proposal.claimed);
        assertFalse(proposal.canceled);
        assertEq(proposal.earliestRedeemableTime, 0); // Not queued yet
    }

    function testProposalCreationFailures() public {
        vm.roll(block.number + 10);

        // Cannot propose without voting power (hook validation)
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.ProposeNotAllowed.selector, alice));
        vm.prank(alice);
        _tokenized(address(mechanism)).propose(charlie, "Should fail");

        // Register alice
        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        // Cannot propose to zero address
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.InvalidRecipient.selector, address(0)));
        vm.prank(alice);
        _tokenized(address(mechanism)).propose(address(0), "Invalid recipient");

        // Cannot propose with empty description
        vm.expectRevert(TokenizedAllocationMechanism.EmptyDescription.selector);
        vm.prank(alice);
        _tokenized(address(mechanism)).propose(charlie, "");

        // Create valid proposal
        vm.prank(alice);
        _tokenized(address(mechanism)).propose(charlie, "Valid proposal");

        // Cannot reuse recipient
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.RecipientUsed.selector, charlie));
        vm.prank(alice);
        _tokenized(address(mechanism)).propose(charlie, "Another proposal");
    }

    // ========== VOTING TESTS ==========

    function testBasicVoting() public {
        // Setup
        vm.roll(block.number + 10);

        // Register users
        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), 200 ether);
        _tokenized(address(mechanism)).signup(200 ether);
        vm.stopPrank();

        // Create proposal
        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        // Move to voting period
        vm.roll(block.number + 101); // Past voting delay

        // Vote For
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether);

        // Vote Against
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.Against, 50 ether);

        // Check vote tally
        (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) = mechanism.voteTallies(pid);
        assertEq(forVotes, 100 ether);
        assertEq(againstVotes, 50 ether);
        assertEq(abstainVotes, 0);

        // Check remaining voting power (reduced by vote weight)
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 0);
        assertEq(_tokenized(address(mechanism)).votingPower(bob), 150 ether);

        // Check has voted flags
        assertTrue(_tokenized(address(mechanism)).hasVoted(pid, alice));
        assertTrue(_tokenized(address(mechanism)).hasVoted(pid, bob));
    }

    function testPartialVoting() public {
        // Setup
        vm.roll(block.number + 10);

        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        vm.roll(block.number + 101);

        // Alice votes with only part of her power
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 60 ether);

        // Check partial power usage
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 40 ether);

        (uint256 forVotes, , ) = mechanism.voteTallies(pid);
        assertEq(forVotes, 60 ether);
    }

    // ========== FINALIZATION TESTS ==========

    function testVoteTallyFinalization() public {
        // Setup complete voting scenario
        vm.roll(block.number + 10);

        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        vm.roll(block.number + 101);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether);

        // Move past voting period
        vm.roll(block.number + 1000);

        // Finalize tally (only owner can do this)
        assertFalse(_tokenized(address(mechanism)).tallyFinalized());
        // Call through the mechanism proxy to preserve owner context
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "finalizeVoteTally failed");
        assertTrue(_tokenized(address(mechanism)).tallyFinalized());
    }

    // ========== PROPOSAL QUEUING TESTS ==========

    function testSuccessfulProposalQueuing() public {
        // Setup voting scenario that meets quorum
        vm.roll(block.number + 10);

        vm.startPrank(alice);
        token.approve(address(mechanism), 150 ether);
        _tokenized(address(mechanism)).signup(150 ether);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        vm.roll(block.number + 101);

        // Vote with enough to meet quorum (100 ether)
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 150 ether);

        vm.roll(block.number + 1000); // End voting
        // Call through the mechanism proxy to preserve owner context
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "finalizeVoteTally failed");

        // Queue successful proposal
        uint256 timestampBefore = block.timestamp;
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "queueProposal failed");

        // Check proposal was queued
        TokenizedAllocationMechanism.Proposal memory proposal = _tokenized(address(mechanism)).proposals(pid);
        assertEq(proposal.earliestRedeemableTime, timestampBefore + 1 days);

        // Check shares were calculated
        assertEq(_tokenized(address(mechanism)).proposalShares(pid), 150 ether); // Net votes as shares

        // Check recipient timelock
        assertEq(_tokenized(address(mechanism)).redeemableAfter(charlie), timestampBefore + 1 days);
    }

    // ========== PROPOSAL STATE TESTS ==========

    function testProposalStates() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();

        // Before start block - register and propose
        vm.roll(startBlock - 1);

        vm.startPrank(alice);
        token.approve(address(mechanism), 150 ether);
        _tokenized(address(mechanism)).signup(150 ether);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        // Pending state (before start block)
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Pending)
        );

        // Active state (during voting delay)
        vm.roll(startBlock + 50); // During voting delay
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Active)
        );

        // Vote to meet quorum (during active voting period)
        vm.roll(startBlock + 150); // Past voting delay (100), within voting period
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 150 ether);

        // Still active until finalized
        vm.roll(startBlock + 1200); // Past voting period (100 + 1000)
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Active)
        );

        // Succeeded after finalization
        // Call through the mechanism proxy to preserve owner context
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "finalizeVoteTally failed");
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );

        // Queued after queuing
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "queueProposal failed");
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Queued)
        );
    }

    // ========== HOOK IMPLEMENTATION TESTS ==========

    function testSimpleVotingHooks() public {
        vm.roll(block.number + 10);

        // Test _beforeSignupHook (always returns true in SimpleVoting)
        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether); // Should succeed
        vm.stopPrank();

        // Test _getVotingPowerHook (1:1 deposit to power)
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 100 ether);

        // Test _beforeProposeHook (requires voting power)
        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        // Bob has no power, should fail to propose
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.ProposeNotAllowed.selector, bob));
        vm.prank(bob);
        _tokenized(address(mechanism)).propose(dave, "Should fail");

        vm.roll(block.number + 101);

        // Test _processVoteHook (simple tally update)
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether);

        (uint256 forVotes, , ) = mechanism.voteTallies(pid);
        assertEq(forVotes, 100 ether);

        vm.roll(block.number + 1000);
        // Call through the mechanism proxy to preserve owner context
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "finalizeVoteTally failed");

        // Test _hasQuorumHook (net votes >= quorum)
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );

        // Test _convertVotesToShares (net votes as shares)
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "queueProposal failed");
        assertEq(_tokenized(address(mechanism)).proposalShares(pid), 100 ether);

        // Test _getRecipientAddressHook
        TokenizedAllocationMechanism.Proposal memory proposal = _tokenized(address(mechanism)).proposals(pid);
        assertEq(proposal.recipient, charlie);
    }

    function testCompleteVotingLifecycle() public {
        // Setup: Multiple users, multiple proposals, complex voting
        vm.roll(block.number + 10);

        // Register users with different amounts
        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), 200 ether);
        _tokenized(address(mechanism)).signup(200 ether);
        vm.stopPrank();

        vm.startPrank(dave);
        token.approve(address(mechanism), 150 ether);
        _tokenized(address(mechanism)).signup(150 ether);
        vm.stopPrank();

        // Create multiple proposals
        vm.prank(alice);
        uint256 pid1 = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        vm.prank(bob);
        uint256 pid2 = _tokenized(address(mechanism)).propose(eve, "Fund Eve");

        // Move to voting period
        vm.roll(block.number + 101);

        // Complex voting pattern
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.For, 100 ether);

        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.Against, 50 ether);

        vm.prank(dave);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.For, 75 ether);

        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.For, 150 ether);

        vm.prank(dave);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.Against, 75 ether);

        // Check tallies
        (uint256 p1For, uint256 p1Against, ) = mechanism.voteTallies(pid1);
        assertEq(p1For, 175 ether); // 100 + 75
        assertEq(p1Against, 50 ether);

        (uint256 p2For, uint256 p2Against, ) = mechanism.voteTallies(pid2);
        assertEq(p2For, 150 ether);
        assertEq(p2Against, 75 ether);

        // Check remaining power
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 0);
        assertEq(_tokenized(address(mechanism)).votingPower(bob), 0); // 200 - 50 - 150
        assertEq(_tokenized(address(mechanism)).votingPower(dave), 0); // 150 - 75 - 75

        // End voting and finalize
        vm.roll(block.number + 1000);
        // Call through the mechanism proxy to preserve owner context
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "finalizeVoteTally failed");

        // Check proposal outcomes based on quorum (100 ether)
        // Proposal 1: net votes = 175 - 50 = 125 ether (meets quorum)
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid1)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );
        // Proposal 2: net votes = 150 - 75 = 75 ether (below quorum)
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid2)),
            uint(TokenizedAllocationMechanism.ProposalState.Defeated)
        );

        // Only queue the successful proposal
        (bool success1, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid1));
        require(success1, "queueProposal failed");

        // Cannot queue defeated proposal - it's defeated so we expect NoQuorum error
        vm.expectRevert(
            abi.encodeWithSelector(TokenizedAllocationMechanism.NoQuorum.selector, pid2, 150 ether, 75 ether, 100 ether)
        );
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid2));
        console.log("Expected failure result:", success2);

        // Check share calculations for successful proposal
        assertEq(_tokenized(address(mechanism)).proposalShares(pid1), 125 ether); // 175 - 50
        // Defeated proposal should have no shares
        assertEq(_tokenized(address(mechanism)).proposalShares(pid2), 0);

        // Verify final states
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid1)),
            uint(TokenizedAllocationMechanism.ProposalState.Queued)
        );
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid2)),
            uint(TokenizedAllocationMechanism.ProposalState.Defeated)
        );
    }

    // ========== SHARE MINTING TESTS ==========

    function testShareMintingOnProposalQueue() public {
        // Setup: Register user, create proposal, vote, and queue
        vm.roll(block.number + 10);

        vm.startPrank(alice);
        token.approve(address(mechanism), 150 ether);
        _tokenized(address(mechanism)).signup(150 ether);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        vm.roll(block.number + 101);

        // Vote with enough to meet quorum (100 ether)
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 150 ether);

        vm.roll(block.number + 1000); // End voting

        // Finalize voting
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "finalizeVoteTally failed");

        // Check initial share balance (should be 0)
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 0);

        // Queue proposal (this should mint shares)
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "queueProposal failed");

        // Verify shares were minted to charlie
        uint256 expectedShares = 150 ether; // Net votes (150 - 0)
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), expectedShares);
        assertEq(_tokenized(address(mechanism)).totalSupply(), expectedShares);
        assertEq(_tokenized(address(mechanism)).totalAssets(), expectedShares); // 1:1 ratio

        // Verify proposal shares recorded
        assertEq(_tokenized(address(mechanism)).proposalShares(pid), expectedShares);

        // Charlie should be able to redeem shares after timelock
        assertGt(_tokenized(address(mechanism)).redeemableAfter(charlie), block.timestamp);
    }

    function testMultipleProposalShareMinting() public {
        // Setup multiple users and proposals
        vm.roll(block.number + 10);

        // Register multiple users
        vm.startPrank(alice);
        token.approve(address(mechanism), 100 ether);
        _tokenized(address(mechanism)).signup(100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), 200 ether);
        _tokenized(address(mechanism)).signup(200 ether);
        vm.stopPrank();

        // Create two proposals
        vm.prank(alice);
        uint256 pid1 = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        vm.prank(bob);
        uint256 pid2 = _tokenized(address(mechanism)).propose(dave, "Fund Dave");

        vm.roll(block.number + 101);

        // Vote on both proposals
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.For, 100 ether);

        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.For, 200 ether);

        vm.roll(block.number + 1000);

        // Finalize voting
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "finalizeVoteTally failed");

        // Queue both proposals
        (bool success1, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid1));
        require(success1, "queueProposal 1 failed");

        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid2));
        require(success2, "queueProposal 2 failed");

        // Verify shares minted correctly
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 100 ether);
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), 200 ether);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 300 ether);
        assertEq(_tokenized(address(mechanism)).totalAssets(), 300 ether);

        // Verify both have redeemable times set
        assertGt(_tokenized(address(mechanism)).redeemableAfter(charlie), block.timestamp);
        assertGt(_tokenized(address(mechanism)).redeemableAfter(dave), block.timestamp);
    }

    function testShareRedemption() public {
        // Setup: Create proposal, vote, queue to mint shares
        vm.roll(block.number + 10);

        vm.startPrank(alice);
        token.approve(address(mechanism), 150 ether);
        _tokenized(address(mechanism)).signup(150 ether);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie");

        vm.roll(block.number + 101);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 150 ether);

        vm.roll(block.number + 1000);

        // Finalize and queue
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "finalizeVoteTally failed");

        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "queueProposal failed");

        // Verify charlie has shares
        uint256 charlieShares = 150 ether;
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), charlieShares);

        // Before timelock - charlie cannot redeem yet (if timelock is enforced)
        uint256 redeemableTime = _tokenized(address(mechanism)).redeemableAfter(charlie);
        assertGt(redeemableTime, block.timestamp);

        // Fast forward past timelock (1 day)
        vm.warp(redeemableTime + 1);

        // Charlie should be able to redeem shares for underlying assets
        uint256 charlieTokensBefore = token.balanceOf(charlie);
        uint256 mechanismTokensBefore = token.balanceOf(address(mechanism));

        // Charlie redeems all shares
        vm.prank(charlie);
        uint256 assetsReceived = _tokenized(address(mechanism)).redeem(charlieShares, charlie, charlie);

        // Verify redemption worked
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0); // Shares burned
        assertEq(token.balanceOf(charlie), charlieTokensBefore + assetsReceived); // Got tokens
        assertEq(token.balanceOf(address(mechanism)), mechanismTokensBefore - assetsReceived); // Mechanism tokens reduced

        // Total supply should be reduced
        assertEq(_tokenized(address(mechanism)).totalSupply(), 0);
    }
}
