// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { SimpleVotingMechanism } from "test/mocks/SimpleVotingMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/// @title Cross-Journey Integration Tests
/// @notice Tests complete end-to-end workflows across voter, admin, and recipient journeys
contract SimpleVotingCrossJourneyTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;

    address alice = address(0x1); // Primary voter
    address bob = address(0x2); // Secondary voter
    address charlie = address(0x3); // Recipient 1
    address dave = address(0x4); // Recipient 2
    address eve = address(0x5); // Recipient 3
    address frank = address(0x6); // Small voter
    address emergencyAdmin = address(0xa);

    uint256 constant LARGE_DEPOSIT = 1000 ether;
    uint256 constant MEDIUM_DEPOSIT = 500 ether;
    uint256 constant SMALL_DEPOSIT = 100 ether;
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

        // Mint tokens to all actors (including large amount for edge case testing)
        token.mint(alice, type(uint128).max);
        token.mint(bob, 1500 ether);
        token.mint(frank, 200 ether);

        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Cross Journey Integration Test",
            symbol: "CJITEST",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_REQUIREMENT,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: 7 days,
            owner: address(0)
        });

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }

    /// @notice Test complete end-to-end integration across all user journeys
    function testCompleteEndToEnd_Integration() public {
        // ✅ CORRECT: Fetch absolute timeline from contract
        uint256 deploymentTime = block.timestamp; // When mechanism was deployed
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // PHASE 1: ADMIN SETUP AND COMMUNITY ONBOARDING

        // Admin monitors community joining
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(frank);
        token.approve(address(mechanism), SMALL_DEPOSIT);
        _tokenized(address(mechanism)).signup(SMALL_DEPOSIT);
        vm.stopPrank();

        // PHASE 2: RECIPIENT ADVOCACY AND PROPOSAL CREATION

        // Recipients work with proposers
        vm.prank(alice);
        uint256 pidCharlie = _tokenized(address(mechanism)).propose(charlie, "Charlie's Renewable Energy Grid");

        vm.prank(bob);
        uint256 pidDave = _tokenized(address(mechanism)).propose(dave, "Dave's Digital Literacy Program");

        vm.prank(frank);
        uint256 pidEve = _tokenized(address(mechanism)).propose(eve, "Eve's Community Health Clinic");

        // PHASE 3: DEMOCRATIC VOTING PROCESS

        vm.warp(votingStartTime + 1);

        // Complex voting patterns
        // Alice: Strategic voter supporting energy and education
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(
            pidCharlie,
            TokenizedAllocationMechanism.VoteType.For,
            600 ether,
            charlie
        );

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pidDave, TokenizedAllocationMechanism.VoteType.For, 400 ether, dave);

        // Bob: Focused on education with opposition to energy
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pidDave, TokenizedAllocationMechanism.VoteType.For, 400 ether, dave);

        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(
            pidCharlie,
            TokenizedAllocationMechanism.VoteType.Against,
            100 ether,
            charlie
        );

        // Frank: Supporting healthcare
        vm.prank(frank);
        _tokenized(address(mechanism)).castVote(pidEve, TokenizedAllocationMechanism.VoteType.For, 100 ether, eve);

        // PHASE 4: ADMIN FINALIZATION AND EXECUTION

        vm.warp(votingEndTime + 1);

        // Admin finalizes voting
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Check final outcomes
        // Charlie: 600 For - 100 Against = 500 net (exceeds 200 quorum) ✓
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidCharlie)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );

        // Dave: 800 For - 0 Against = 800 net (exceeds 200 quorum) ✓
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidDave)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );

        // Eve: 100 For - 0 Against = 100 net (below 200 quorum) ✗
        assertEq(
            uint(_tokenized(address(mechanism)).state(pidEve)),
            uint(TokenizedAllocationMechanism.ProposalState.Defeated)
        );

        // Admin queues successful proposals
        (bool success1, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pidCharlie));
        require(success1, "Queue Charlie failed");

        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pidDave));
        require(success2, "Queue Dave failed");

        // PHASE 5: RECIPIENT REDEMPTION AND ASSET UTILIZATION

        // Verify share distribution
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 500 ether);
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), 800 ether);
        assertEq(_tokenized(address(mechanism)).balanceOf(eve), 0);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 1300 ether);

        // Fast forward past timelock
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Recipients redeem allocations
        uint256 charlieTokensBefore = token.balanceOf(charlie);
        uint256 daveTokensBefore = token.balanceOf(dave);

        // Get actual redeemable shares (accounting for proper share price)
        uint256 charlieMaxShares = _tokenized(address(mechanism)).maxRedeem(charlie);
        uint256 daveMaxShares = _tokenized(address(mechanism)).maxRedeem(dave);

        vm.prank(charlie);
        uint256 charlieAssets = _tokenized(address(mechanism)).redeem(charlieMaxShares, charlie, charlie);

        vm.prank(dave);
        uint256 daveAssets = _tokenized(address(mechanism)).redeem(daveMaxShares, dave, dave);

        // Calculate expected assets based on proper accounting
        // Total deposits: 1000 + 500 + 100 = 1600 ether
        // Total shares: 500 + 800 = 1300 ether
        // Share price: 1600/1300 assets per share
        uint256 totalDeposits = 1600 ether;
        uint256 totalShares = 1300 ether;
        uint256 expectedCharlieAssets = (500 ether * totalDeposits) / totalShares; // ~615.38 ether
        uint256 expectedDaveAssets = (800 ether * totalDeposits) / totalShares; // ~984.62 ether

        // Verify final state with proper asset accounting
        assertEq(token.balanceOf(charlie), charlieTokensBefore + charlieAssets);
        assertEq(token.balanceOf(dave), daveTokensBefore + daveAssets);
        // Account for tiny rounding remainder (should be very small)
        assertTrue(_tokenized(address(mechanism)).totalSupply() <= 2);
        // Account for rounding errors due to floor rounding
        assertApproxEqAbs(charlieAssets, expectedCharlieAssets, 3);
        assertApproxEqAbs(daveAssets, expectedDaveAssets, 3);

        // Verify conservation - should be very close to total deposits (within rounding error)
        uint256 totalRedeemed = charlieAssets + daveAssets;
        assertTrue(totalRedeemed >= totalDeposits - 10 && totalRedeemed <= totalDeposits + 10);

        // PHASE 6: SYSTEM INTEGRITY VERIFICATION

        // Verify clean state (allow for tiny rounding remainder)
        assertTrue(_tokenized(address(mechanism)).totalSupply() <= 2);
        assertTrue(_tokenized(address(mechanism)).tallyFinalized());
        assertEq(_tokenized(address(mechanism)).getProposalCount(), 3);

        // Verify voter power consumption
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 0);
        assertEq(_tokenized(address(mechanism)).votingPower(bob), 0);
        assertEq(_tokenized(address(mechanism)).votingPower(frank), 0);
    }

    /// @notice Test crisis recovery and system resilience
    function testCrisisRecovery_SystemResilience() public {
        // ✅ CORRECT: Fetch absolute timeline from contract
        uint256 deploymentTime = block.timestamp; // When mechanism was deployed
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Setup scenario with potential failures
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Test proposal");

        vm.warp(votingStartTime + 1);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether, charlie);

        // Emergency pause during voting
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("pause()"));
        require(success, "Pause failed");

        // All operations blocked
        vm.expectRevert(TokenizedAllocationMechanism.PausedError.selector);
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether, charlie);

        // Resume operations
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("unpause()"));
        require(success2, "Unpause failed");

        // Operations work again - use bob since alice already voted
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether, charlie);

        // Ownership transfer during crisis
        (bool success3, ) = address(mechanism).call(
            abi.encodeWithSignature("transferOwnership(address)", emergencyAdmin)
        );
        require(success3, "Transfer ownership failed");

        // New owner accepts ownership
        vm.prank(emergencyAdmin);
        (bool success3b, ) = address(mechanism).call(abi.encodeWithSignature("acceptOwnership()"));
        require(success3b, "Accept ownership failed");

        // New owner manages crisis
        vm.startPrank(emergencyAdmin);
        (bool success4, ) = address(mechanism).call(abi.encodeWithSignature("pause()"));
        require(success4, "Emergency admin pause failed");
        vm.stopPrank();

        // System recovery
        vm.startPrank(emergencyAdmin);
        (bool success5, ) = address(mechanism).call(abi.encodeWithSignature("unpause()"));
        require(success5, "Recovery unpause failed");
        vm.stopPrank();

        // Complete voting cycle
        vm.warp(votingEndTime + 1);

        vm.startPrank(emergencyAdmin);
        (bool success6, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success6, "Emergency finalization failed");

        (bool success7, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success7, "Emergency queuing failed");
        vm.stopPrank();

        // System functions normally - alice (500) + bob (100) = 600 total
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 600 ether);
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Queued)
        );
    }

    /// @notice Test edge cases and boundary conditions across journeys
    function testEdgeCases_BoundaryConditions() public {
        // ✅ CORRECT: Fetch absolute timeline from contract
        uint256 deploymentTime = block.timestamp; // When mechanism was deployed
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Maximum safe values
        vm.startPrank(alice);
        token.approve(address(mechanism), type(uint128).max);
        _tokenized(address(mechanism)).signup(type(uint128).max);
        vm.stopPrank();

        assertEq(_tokenized(address(mechanism)).votingPower(alice), type(uint128).max);

        // Zero voting power operations
        vm.prank(frank);
        _tokenized(address(mechanism)).signup(0);

        // Cannot propose with zero power
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.ProposeNotAllowed.selector, frank));
        vm.prank(frank);
        _tokenized(address(mechanism)).propose(eve, "Should fail");

        // Boundary voting timing - ensure bob has registered before voting starts
        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Boundary test");

        // Exactly at voting start
        vm.warp(votingStartTime);
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 1000 ether, charlie);

        // Exactly at voting end
        vm.warp(votingEndTime);
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.Against, 100 ether, charlie);

        // One second later should fail
        vm.warp(votingEndTime + 1);
        vm.expectRevert();
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 1 ether, charlie);
    }

    /// @notice Test proposal cancellation across journeys
    function testProposalCancellation_CrossJourney() public {
        // ✅ CORRECT: Fetch absolute timeline from contract
        uint256 deploymentTime = block.timestamp; // When mechanism was deployed
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingStartTime = deploymentTime + votingDelay;

        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        // Test proposal states during cancellation
        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Cancellable proposal");

        // Should be in Pending state (before voting starts)
        // No need to warp - we're already before votingStartTime
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Pending)
        );

        // During voting period - warp to active state
        vm.warp(votingStartTime + 1);
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Active)
        );

        // Proposer cancels
        vm.prank(alice);
        _tokenized(address(mechanism)).cancelProposal(pid);

        assertEq(
            uint(_tokenized(address(mechanism)).state(pid)),
            uint(TokenizedAllocationMechanism.ProposalState.Canceled)
        );

        // Cannot vote on canceled proposal
        vm.warp(votingStartTime + 1);
        vm.expectRevert();
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether, charlie);

        // Non-proposer cannot cancel
        vm.prank(alice);
        uint256 pid2 = _tokenized(address(mechanism)).propose(dave, "Another proposal");

        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.NotProposer.selector, bob, alice));
        vm.prank(bob);
        _tokenized(address(mechanism)).cancelProposal(pid2);
    }

    /// @notice Test multi-proposal complex scenarios
    function testMultiProposal_ComplexScenarios() public {
        // ✅ CORRECT: Fetch absolute timeline from contract
        uint256 deploymentTime = block.timestamp; // When mechanism was deployed
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Setup diverse voter base
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(frank);
        token.approve(address(mechanism), SMALL_DEPOSIT);
        _tokenized(address(mechanism)).signup(SMALL_DEPOSIT);
        vm.stopPrank();

        // Create competing proposals
        vm.prank(alice);
        uint256 pid1 = _tokenized(address(mechanism)).propose(charlie, "High-impact Infrastructure");

        vm.prank(bob);
        uint256 pid2 = _tokenized(address(mechanism)).propose(dave, "Community Education");

        vm.prank(frank);
        uint256 pid3 = _tokenized(address(mechanism)).propose(eve, "Healthcare Access");

        vm.warp(votingStartTime + 1);

        // Strategic voting with power distribution
        // Alice: Supports infrastructure but opposes healthcare
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.For, 500 ether, charlie);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid3, TokenizedAllocationMechanism.VoteType.Against, 300 ether, eve);

        // Bob: Supports education and healthcare
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.For, 400 ether, dave);

        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid3, TokenizedAllocationMechanism.VoteType.For, 100 ether, eve);

        // Frank: All-in on healthcare
        vm.prank(frank);
        _tokenized(address(mechanism)).castVote(pid3, TokenizedAllocationMechanism.VoteType.For, 100 ether, eve);

        // Finalize and determine outcomes
        vm.warp(votingEndTime + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Check complex voting outcomes
        // pid1: 500 For, 0 Against = 500 net (succeeds)
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid1)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );

        // pid2: 400 For, 0 Against = 400 net (succeeds)
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid2)),
            uint(TokenizedAllocationMechanism.ProposalState.Succeeded)
        );

        // pid3: 200 For, 300 Against = -100 net (defeated by negative votes)
        assertEq(
            uint(_tokenized(address(mechanism)).state(pid3)),
            uint(TokenizedAllocationMechanism.ProposalState.Defeated)
        );

        // Queue successful proposals
        (bool success1, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid1));
        require(success1, "Queue pid1 failed");

        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid2));
        require(success2, "Queue pid2 failed");

        // Verify share distribution
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 500 ether);
        assertEq(_tokenized(address(mechanism)).balanceOf(dave), 400 ether);
        assertEq(_tokenized(address(mechanism)).balanceOf(eve), 0);
        assertEq(_tokenized(address(mechanism)).totalSupply(), 900 ether);

        // Fast forward and verify redemption with proper asset accounting
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Calculate expected assets based on proper accounting
        // Total deposits: 1000 + 500 + 100 = 1600 ether
        // Total shares: 500 + 400 = 900 ether
        // Share price: 1600/900 assets per share
        uint256 totalDeposits = 1600 ether;
        uint256 totalShares = 900 ether;

        // Get actual redeemable shares (accounting for proper share price)
        uint256 charlieMaxShares = _tokenized(address(mechanism)).maxRedeem(charlie);
        uint256 daveMaxShares = _tokenized(address(mechanism)).maxRedeem(dave);

        vm.prank(charlie);
        uint256 charlieAssets = _tokenized(address(mechanism)).redeem(charlieMaxShares, charlie, charlie);

        vm.prank(dave);
        uint256 daveAssets = _tokenized(address(mechanism)).redeem(daveMaxShares, dave, dave);

        // Calculate expected assets
        uint256 expectedCharlieAssets = (500 ether * totalDeposits) / totalShares;
        uint256 expectedDaveAssets = (400 ether * totalDeposits) / totalShares;

        // Account for rounding errors due to floor rounding
        assertApproxEqAbs(charlieAssets, expectedCharlieAssets, 3);
        assertApproxEqAbs(daveAssets, expectedDaveAssets, 3);

        // Final state verification
        assertTrue(_tokenized(address(mechanism)).totalSupply() <= 2);

        // Verify conservation - should be very close to total deposits
        uint256 totalRedeemed = charlieAssets + daveAssets;
        assertTrue(totalRedeemed >= totalDeposits - 10 && totalRedeemed <= totalDeposits + 10);
    }
}
