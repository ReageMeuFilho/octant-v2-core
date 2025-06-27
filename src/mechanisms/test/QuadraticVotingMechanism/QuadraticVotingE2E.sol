// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { QuadraticVotingMechanism } from "src/mechanisms/mechanism/QuadraticVotingMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/// @title Quadratic Voting End-to-End Test
/// @notice Complete end-to-end testing of the quadratic voting mechanism
/// @dev Tests the full user journey from registration through final redemption
contract QuadraticVotingE2E is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    QuadraticVotingMechanism mechanism;

    // Test actors
    address alice = address(0x101); // Voter 1
    address bob = address(0x102); // Voter 2
    address charlie = address(0x103); // Voter 3
    address recipient1 = address(0x201); // Project recipient 1
    address recipient2 = address(0x202); // Project recipient 2
    address recipient3 = address(0x203); // Project recipient 3

    // Test parameters
    uint256 constant INITIAL_TOKEN_BALANCE = 2000 ether;
    uint256 constant DEPOSIT_AMOUNT = 1000 ether;
    uint256 constant ALPHA_NUMERATOR = 1; // 100% quadratic funding
    uint256 constant ALPHA_DENOMINATOR = 1;
    uint256 constant QUORUM_REQUIREMENT = 500;
    uint256 constant VOTING_DELAY = 100;
    uint256 constant VOTING_PERIOD = 1000;
    uint256 constant TIMELOCK_DELAY = 1 days;
    uint256 constant GRACE_PERIOD = 7 days;

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
    function _createProposal(
        address proposer,
        address recipient,
        string memory description
    ) internal returns (uint256 pid) {
        vm.prank(proposer);
        pid = _tokenized(address(mechanism)).propose(recipient, description);
    }

    /// @notice Helper function to cast a vote on a proposal
    /// @param voter Address casting the vote
    /// @param pid Proposal ID to vote on
    /// @param weight Vote weight (quadratic cost = weight^2)
    /// @return previousPower Voting power before the vote
    /// @return newPower Voting power after the vote
    function _castVote(
        address voter,
        uint256 pid,
        uint256 weight
    ) internal returns (uint256 previousPower, uint256 newPower) {
        previousPower = _tokenized(address(mechanism)).votingPower(voter);
        vm.prank(voter);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, weight);
        newPower = _tokenized(address(mechanism)).votingPower(voter);
    }

    /// @notice Calculate matching funds needed for 1:1 shares-to-assets ratio
    /// @dev For alpha=1: totalShares = totalQuadraticSum, matchingFunds = totalQuadraticSum - totalLinearSum
    /// @return matchingFundsNeeded Amount of additional funds needed for 1:1 ratio
    /// @return totalQuadraticSum Total quadratic sum from all proposals
    /// @return totalLinearSum Total linear sum from all proposals (user contributions)
    function _calculateMatchingFunds(
        uint256 totalUserDeposits
    ) internal view returns (uint256 matchingFundsNeeded, uint256 totalQuadraticSum, uint256 totalLinearSum) {
        totalQuadraticSum = mechanism.totalQuadraticSum();
        totalLinearSum = mechanism.totalLinearSum();

        // For alpha = 1 (100% quadratic funding):
        // Total shares to be minted = totalQuadraticSum
        // Assets already in contract = totalLinearSum (from user deposits/contributions)
        // Matching funds needed = totalQuadraticSum - totalLinearSum
        if (totalQuadraticSum >= totalLinearSum) {
            matchingFundsNeeded = totalQuadraticSum - totalUserDeposits;
        } else {
            matchingFundsNeeded = 0;
        }
    }

    /// @notice Calculate optimal alpha for 1:1 shares-to-assets ratio given fixed matching pool amount
    /// @dev Formula: We want total funding = total assets available
    /// @dev Total funding = α × totalQuadraticSum + (1-α) × totalLinearSum
    /// @dev Total assets = totalUserDeposits + matchingPoolAmount
    /// @dev Solving: α × totalQuadraticSum + (1-α) × totalLinearSum = totalUserDeposits + matchingPoolAmount
    /// @dev Rearranging: α × (totalQuadraticSum - totalLinearSum) = totalUserDeposits + matchingPoolAmount - totalLinearSum
    /// @param matchingPoolAmount Fixed amount of matching funds available
    /// @param totalQuadraticSum Total quadratic sum across all proposals
    /// @param totalLinearSum Total linear sum across all proposals (voting costs)
    /// @param totalUserDeposits Total user deposits in the mechanism
    /// @return alphaNumerator Calculated alpha numerator
    /// @return alphaDenominator Calculated alpha denominator
    function _calculateOptimalAlpha(
        uint256 matchingPoolAmount,
        uint256 totalQuadraticSum,
        uint256 totalLinearSum,
        uint256 totalUserDeposits
    ) internal pure returns (uint256 alphaNumerator, uint256 alphaDenominator) {
        // Handle edge cases
        if (totalQuadraticSum <= totalLinearSum) {
            // No quadratic funding benefit, set alpha to 0
            alphaNumerator = 0;
            alphaDenominator = 1;
            return (alphaNumerator, alphaDenominator);
        }

        uint256 totalAssetsAvailable = totalUserDeposits + matchingPoolAmount;
        uint256 quadraticAdvantage = totalQuadraticSum - totalLinearSum;

        // We want: α × totalQuadraticSum + (1-α) × totalLinearSum = totalAssetsAvailable
        // Solving for α: α × (totalQuadraticSum - totalLinearSum) = totalAssetsAvailable - totalLinearSum
        // Therefore: α = (totalAssetsAvailable - totalLinearSum) / (totalQuadraticSum - totalLinearSum)

        if (totalAssetsAvailable <= totalLinearSum) {
            // Not enough assets even for linear funding, set alpha to 0
            alphaNumerator = 0;
            alphaDenominator = 1;
        } else {
            uint256 numerator = totalAssetsAvailable - totalLinearSum;

            if (numerator >= quadraticAdvantage) {
                // Enough assets for full quadratic funding
                alphaNumerator = 1;
                alphaDenominator = 1;
            } else {
                // Calculate fractional alpha
                alphaNumerator = numerator;
                alphaDenominator = quadraticAdvantage;
            }
        }
    }

    function setUp() public {
        // Deploy factory and mock token
        factory = new AllocationMechanismFactory();
        token = new ERC20Mock();

        // Mint tokens to all test actors
        token.mint(alice, INITIAL_TOKEN_BALANCE);
        token.mint(bob, INITIAL_TOKEN_BALANCE);
        token.mint(charlie, INITIAL_TOKEN_BALANCE);

        // Configure the allocation mechanism
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "E2E Test Mechanism",
            symbol: "E2E",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_REQUIREMENT,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: GRACE_PERIOD,
            startBlock: block.number + 50,
            owner: address(0)
        });

        // Deploy quadratic voting mechanism with 100% quadratic funding
        address mechanismAddr = factory.deployQuadraticVotingMechanism(config, ALPHA_NUMERATOR, ALPHA_DENOMINATOR);
        mechanism = QuadraticVotingMechanism(payable(mechanismAddr));

        console.log("=== E2E TEST SETUP COMPLETE ===");
        console.log("Mechanism deployed at:", address(mechanism));
        console.log("Test token deployed at:", address(token));
        console.log("Start block:", _tokenized(address(mechanism)).startBlock());
        console.log("Alice balance:", token.balanceOf(alice));
        console.log("Bob balance:", token.balanceOf(bob));
        console.log("Charlie balance:", token.balanceOf(charlie));
    }

    /// @notice Verify the setup configuration and initial state
    function testSetupVerification() public view {
        // Verify mechanism deployment
        assertTrue(address(mechanism) != address(0), "Mechanism should be deployed");
        assertTrue(address(factory) != address(0), "Factory should be deployed");
        assertTrue(address(token) != address(0), "Token should be deployed");

        // Verify mechanism configuration
        assertEq(address(_tokenized(address(mechanism)).asset()), address(token), "Asset should be test token");
        assertEq(_tokenized(address(mechanism)).name(), "E2E Test Mechanism", "Name should match");
        assertEq(_tokenized(address(mechanism)).symbol(), "E2E", "Symbol should match");
        assertEq(_tokenized(address(mechanism)).votingDelay(), VOTING_DELAY, "Voting delay should match");
        assertEq(_tokenized(address(mechanism)).votingPeriod(), VOTING_PERIOD, "Voting period should match");
        assertEq(_tokenized(address(mechanism)).quorumShares(), QUORUM_REQUIREMENT, "Quorum should match");
        assertEq(_tokenized(address(mechanism)).timelockDelay(), TIMELOCK_DELAY, "Timelock delay should match");
        assertEq(_tokenized(address(mechanism)).gracePeriod(), GRACE_PERIOD, "Grace period should match");
        assertEq(_tokenized(address(mechanism)).startBlock(), block.number + 50, "Start block should match");

        // Verify quadratic voting mechanism specific configuration
        (uint256 alphaNumerator, uint256 alphaDenominator) = mechanism.getAlpha();
        assertEq(alphaNumerator, ALPHA_NUMERATOR, "Alpha numerator should match");
        assertEq(alphaDenominator, ALPHA_DENOMINATOR, "Alpha denominator should match");

        // Verify initial token balances
        assertEq(token.balanceOf(alice), INITIAL_TOKEN_BALANCE, "Alice initial balance should match");
        assertEq(token.balanceOf(bob), INITIAL_TOKEN_BALANCE, "Bob initial balance should match");
        assertEq(token.balanceOf(charlie), INITIAL_TOKEN_BALANCE, "Charlie initial balance should match");
        assertEq(token.balanceOf(address(mechanism)), 0, "Mechanism should start with zero balance");

        // Verify initial mechanism state
        assertEq(_tokenized(address(mechanism)).totalSupply(), 0, "No shares should exist initially");
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 0, "Alice should have no voting power initially");
        assertEq(_tokenized(address(mechanism)).votingPower(bob), 0, "Bob should have no voting power initially");
        assertEq(
            _tokenized(address(mechanism)).votingPower(charlie),
            0,
            "Charlie should have no voting power initially"
        );

        // Verify recipient addresses have zero balances
        assertEq(token.balanceOf(recipient1), 0, "Recipient1 should start with zero balance");
        assertEq(token.balanceOf(recipient2), 0, "Recipient2 should start with zero balance");
        assertEq(token.balanceOf(recipient3), 0, "Recipient3 should start with zero balance");
    }

    /// @notice Test user signup functionality with helper function
    function testUserSignup() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Initial state verification
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 0, "Alice should have no voting power initially");
        assertEq(token.balanceOf(address(mechanism)), 0, "Mechanism should have no tokens initially");

        // Sign up Alice with deposit
        _signupUser(alice, DEPOSIT_AMOUNT);

        // Verify signup effects
        assertEq(
            _tokenized(address(mechanism)).votingPower(alice),
            DEPOSIT_AMOUNT,
            "Alice should have voting power equal to deposit"
        );
        assertEq(
            token.balanceOf(alice),
            INITIAL_TOKEN_BALANCE - DEPOSIT_AMOUNT,
            "Alice token balance should decrease by deposit amount"
        );
        assertEq(token.balanceOf(address(mechanism)), DEPOSIT_AMOUNT, "Mechanism should receive Alice's deposit");

        // Sign up Bob with different deposit
        uint256 bobDeposit = 500 ether;
        _signupUser(bob, bobDeposit);

        // Verify Bob's signup
        assertEq(
            _tokenized(address(mechanism)).votingPower(bob),
            bobDeposit,
            "Bob should have voting power equal to his deposit"
        );
        assertEq(
            token.balanceOf(address(mechanism)),
            DEPOSIT_AMOUNT + bobDeposit,
            "Mechanism should have both deposits"
        );

        // Sign up Charlie with zero deposit
        _signupUser(charlie, 0);

        // Verify Charlie's zero deposit signup
        assertEq(_tokenized(address(mechanism)).votingPower(charlie), 0, "Charlie should have zero voting power");
        assertEq(token.balanceOf(charlie), INITIAL_TOKEN_BALANCE, "Charlie's token balance should be unchanged");
        assertEq(
            token.balanceOf(address(mechanism)),
            DEPOSIT_AMOUNT + bobDeposit,
            "Mechanism balance should be unchanged by zero deposit"
        );
    }

    /// @notice Test proposal creation functionality with helper function
    function testProposalCreation() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Sign up users first (only registered users can propose)
        _signupUser(alice, DEPOSIT_AMOUNT);
        _signupUser(bob, DEPOSIT_AMOUNT);

        // Create first proposal
        uint256 pid1 = _createProposal(alice, recipient1, "Education Initiative");

        // Verify proposal creation
        assertTrue(pid1 > 0, "Proposal ID should be greater than 0");

        // Get proposal details
        TokenizedAllocationMechanism.Proposal memory proposal1 = _tokenized(address(mechanism)).proposals(pid1);
        assertEq(proposal1.proposer, alice, "Proposer should be Alice");
        assertEq(proposal1.recipient, recipient1, "Recipient should be recipient1");
        assertEq(proposal1.description, "Education Initiative", "Description should match");
        assertEq(
            uint8(_tokenized(address(mechanism)).state(pid1)),
            uint8(TokenizedAllocationMechanism.ProposalState.Pending),
            "Proposal should be Pending"
        );
        assertEq(proposal1.earliestRedeemableTime, 0, "Earliest redeemable time should be 0");

        // Create second proposal from different user
        uint256 pid2 = _createProposal(bob, recipient2, "Healthcare Project");

        // Verify second proposal
        assertTrue(pid2 > pid1, "Second proposal ID should be greater than first");

        TokenizedAllocationMechanism.Proposal memory proposal2 = _tokenized(address(mechanism)).proposals(pid2);
        assertEq(proposal2.proposer, bob, "Proposer should be Bob");
        assertEq(proposal2.recipient, recipient2, "Recipient should be recipient2");
        assertEq(proposal2.description, "Healthcare Project", "Description should match");

        // Test edge cases

        // Unregistered user cannot propose
        vm.expectRevert();
        _createProposal(charlie, recipient3, "Should fail - unregistered");

        // User with zero voting power cannot propose (Charlie is registered but has no voting power)
        _signupUser(charlie, 0);
        vm.expectRevert();
        _createProposal(charlie, recipient3, "Should fail - no voting power");

        // Same user can create multiple proposals
        uint256 pid3 = _createProposal(alice, recipient3, "Alice's Second Project");
        assertTrue(pid3 > pid2, "Third proposal ID should be greater than second");

        TokenizedAllocationMechanism.Proposal memory proposal3 = _tokenized(address(mechanism)).proposals(pid3);
        assertEq(proposal3.proposer, alice, "Proposer should still be Alice");
        assertEq(proposal3.recipient, recipient3, "Recipient should be recipient3");
    }

    /// @notice Test combined signup and proposal workflow
    function testSignupAndProposalWorkflow() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Phase 1: User signup
        console.log("=== Phase 1: User Signup ===");
        _signupUser(alice, DEPOSIT_AMOUNT);
        _signupUser(bob, 750 ether);
        _signupUser(charlie, 250 ether);

        uint256 totalDeposits = DEPOSIT_AMOUNT + 750 ether + 250 ether;
        assertEq(token.balanceOf(address(mechanism)), totalDeposits, "Total deposits should be tracked correctly");

        // Phase 2: Proposal creation
        console.log("=== Phase 2: Proposal Creation ===");
        uint256 pid1 = _createProposal(alice, recipient1, "Green Energy Initiative");
        uint256 pid2 = _createProposal(bob, recipient2, "Community Development");
        uint256 pid3 = _createProposal(charlie, recipient3, "Education Technology");

        // Verify all proposals are created correctly
        assertTrue(pid1 < pid2 && pid2 < pid3, "Proposal IDs should be sequential");

        // Verify proposal states
        TokenizedAllocationMechanism.Proposal memory p1 = _tokenized(address(mechanism)).proposals(pid1);
        TokenizedAllocationMechanism.Proposal memory p2 = _tokenized(address(mechanism)).proposals(pid2);
        TokenizedAllocationMechanism.Proposal memory p3 = _tokenized(address(mechanism)).proposals(pid3);

        assertEq(
            uint8(_tokenized(address(mechanism)).state(pid1)),
            uint8(TokenizedAllocationMechanism.ProposalState.Pending),
            "Proposal 1 should be Pending"
        );
        assertEq(
            uint8(_tokenized(address(mechanism)).state(pid2)),
            uint8(TokenizedAllocationMechanism.ProposalState.Pending),
            "Proposal 2 should be Pending"
        );
        assertEq(
            uint8(_tokenized(address(mechanism)).state(pid3)),
            uint8(TokenizedAllocationMechanism.ProposalState.Pending),
            "Proposal 3 should be Pending"
        );

        // Verify recipients are different
        assertTrue(
            p1.recipient != p2.recipient && p2.recipient != p3.recipient && p1.recipient != p3.recipient,
            "All recipients should be unique"
        );

        // Verify mechanism state remains consistent
        assertEq(
            token.balanceOf(address(mechanism)),
            totalDeposits,
            "Mechanism balance should be unchanged by proposals"
        );
        assertEq(
            _tokenized(address(mechanism)).totalSupply(),
            0,
            "No shares should be minted during proposal creation"
        );

        console.log("Workflow test complete - 3 users signed up, 3 proposals created");
    }
    /// @notice Test voting edge cases and error conditions
    function testVotingErrorConditions() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup
        _signupUser(alice, DEPOSIT_AMOUNT);
        _signupUser(bob, 50); // Small deposit for testing insufficient power (50 wei is much smaller than 10000)
        uint256 pid = _createProposal(alice, recipient1, "Test Proposal");

        // Cannot vote before voting period starts
        vm.expectRevert();
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 10);

        // Move to voting period
        vm.roll(startBlock + VOTING_DELAY + 1);

        // Cannot vote with insufficient voting power
        vm.expectRevert(); // Bob has 50 wei, but voting weight 100 costs 10000
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100);

        // Alice votes successfully
        _castVote(alice, pid, 10);

        // Cannot vote twice on same proposal
        vm.expectRevert();
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 5);

        // Unregistered user cannot vote
        vm.expectRevert();
        vm.prank(charlie);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 1);

        // Cannot vote after voting period ends
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        vm.expectRevert();
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 5);

        // Cannot vote on non-existent proposal
        vm.roll(startBlock + VOTING_DELAY + 500); // Back in voting period
        vm.expectRevert();
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(999, TokenizedAllocationMechanism.VoteType.For, 5); // Non-existent proposal ID
    }

    /// @notice Test complex multi-user voting scenario
    function testMultiUserVotingScenario() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup: 3 users with different voting power, 3 proposals
        _signupUser(alice, 1000 ether); // 1000 voting power
        _signupUser(bob, 500 ether); // 500 voting power
        _signupUser(charlie, 200 ether); // 200 voting power

        uint256 pid1 = _createProposal(alice, recipient1, "Education");
        uint256 pid2 = _createProposal(bob, recipient2, "Healthcare");
        uint256 pid3 = _createProposal(charlie, recipient3, "Environment");

        vm.roll(startBlock + VOTING_DELAY + 1);

        console.log("=== Multi-User Voting Scenario ===");

        // Alice votes on all three proposals
        console.log("Alice voting...");
        _castVote(alice, pid1, 25e9); // Cost: 625 ether
        _castVote(alice, pid2, 15e9); // Cost: 225 ether
        _castVote(alice, pid3, 10e9); // Cost: 100 ether
        // Alice remaining power: 1000 ether - 625 - 225 - 100 = 1000 ether - 950
        assertEq(_tokenized(address(mechanism)).votingPower(alice), 1000 ether - 950 ether, "Alice remaining power");

        // Bob votes on two proposals
        console.log("Bob voting...");
        _castVote(bob, pid1, 20e9); // Cost: 400 ether
        _castVote(bob, pid2, 10e9); // Cost: 100 ether
        // Bob remaining power: 500 ether - 400 - 100 = 500 ether - 500
        assertEq(_tokenized(address(mechanism)).votingPower(bob), 500 ether - 500 ether, "Bob remaining power");

        // Charlie votes on one proposal
        // console.log("Charlie voting...");
        _castVote(charlie, pid3, 14e9); // Cost: 196 ether
        // Charlie remaining power: 200 ether - 196 = 200 ether - 196
        assertEq(_tokenized(address(mechanism)).votingPower(charlie), 200 ether - 196 ether, "Charlie remaining power");

        // Verify all vote records
        assertTrue(_tokenized(address(mechanism)).hasVoted(pid1, alice), "Alice voted on pid1");
        assertTrue(_tokenized(address(mechanism)).hasVoted(pid2, alice), "Alice voted on pid2");
        assertTrue(_tokenized(address(mechanism)).hasVoted(pid3, alice), "Alice voted on pid3");
        assertTrue(_tokenized(address(mechanism)).hasVoted(pid1, bob), "Bob voted on pid1");
        assertTrue(_tokenized(address(mechanism)).hasVoted(pid2, bob), "Bob voted on pid2");
        assertFalse(_tokenized(address(mechanism)).hasVoted(pid3, bob), "Bob didn't vote on pid3");
        assertFalse(_tokenized(address(mechanism)).hasVoted(pid1, charlie), "Charlie didn't vote on pid1");
        assertFalse(_tokenized(address(mechanism)).hasVoted(pid2, charlie), "Charlie didn't vote on pid2");
        assertTrue(_tokenized(address(mechanism)).hasVoted(pid3, charlie), "Charlie voted on pid3");

        // Verify vote tallies using getTally from ProperQF
        // console.log("=== Verifying Vote Tallies ===");

        // Project 1 (Education): Alice(25e9) + Bob(20e9) = weight sum 45e9
        // Linear contributions: Alice(625 ether) + Bob(400 ether) = 1025 ether
        // Quadratic calculation: (25e9 + 20e9)² = (45e9)² = 2025e18 = 2025 ether
        (uint256 p1Contributions, uint256 p1SqrtSum, uint256 p1Quadratic, uint256 p1Linear) = mechanism.getTally(pid1);
        // console.log("Project 1 - Contributions:", p1Contributions);
        // console.log("Project 1 - SqrtSum:", p1SqrtSum);
        // console.log("Project 1 - Quadratic:", p1Quadratic);
        // console.log("Project 1 - Linear:", p1Linear);

        assertEq(p1Contributions, 625 ether + 400 ether, "Project 1 contributions should be sum of quadratic costs");
        assertEq(p1SqrtSum, 25e9 + 20e9, "Project 1 sqrt sum should be sum of vote weights");
        // With alpha = 1: quadratic funding = 1 * (45e9)² = 2025 ether, linear funding = 0 * 1025 = 0
        assertEq(p1Quadratic, 2025 ether, "Project 1 quadratic funding should be (45e9)^2");
        assertEq(p1Linear, 0 ether, "Project 1 linear funding should be 0 with alpha=1");

        // Project 2 (Healthcare): Alice(15e9) + Bob(10e9) = weight sum 25e9
        // Linear contributions: Alice(225 ether) + Bob(100 ether) = 325 ether
        // Quadratic calculation: (15e9 + 10e9)² = (25e9)² = 625e18 = 625 ether
        (uint256 p2Contributions, uint256 p2SqrtSum, uint256 p2Quadratic, uint256 p2Linear) = mechanism.getTally(pid2);
        // console.log("Project 2 - Contributions:", p2Contributions);
        // console.log("Project 2 - SqrtSum:", p2SqrtSum);
        // console.log("Project 2 - Quadratic:", p2Quadratic);
        // console.log("Project 2 - Linear:", p2Linear);

        assertEq(p2Contributions, 225 ether + 100 ether, "Project 2 contributions should be sum of quadratic costs");
        assertEq(p2SqrtSum, 15e9 + 10e9, "Project 2 sqrt sum should be sum of vote weights");
        assertEq(p2Quadratic, 625 ether, "Project 2 quadratic funding should be (25e9)^2");
        assertEq(p2Linear, 0 ether, "Project 2 linear funding should be 0 with alpha=1");

        // Project 3 (Environment): Alice(10e9) + Charlie(14e9) = weight sum 24e9
        // Linear contributions: Alice(100 ether) + Charlie(196 ether) = 296 ether
        // Quadratic calculation: (10e9 + 14e9)² = (24e9)² = 576e18 = 576 ether
        (uint256 p3Contributions, uint256 p3SqrtSum, uint256 p3Quadratic, uint256 p3Linear) = mechanism.getTally(pid3);
        // console.log("Project 3 - Contributions:", p3Contributions);
        // console.log("Project 3 - SqrtSum:", p3SqrtSum);
        // console.log("Project 3 - Quadratic:", p3Quadratic);
        // console.log("Project 3 - Linear:", p3Linear);

        assertEq(p3Contributions, 100 ether + 196 ether, "Project 3 contributions should be sum of quadratic costs");
        assertEq(p3SqrtSum, 10e9 + 14e9, "Project 3 sqrt sum should be sum of vote weights");
        assertEq(p3Quadratic, 576 ether, "Project 3 quadratic funding should be (24e9)^2");
        assertEq(p3Linear, 0 ether, "Project 3 linear funding should be 0 with alpha=1");

        // Verify total funding allocation using direct assertions to reduce stack usage
        assertEq(
            p1Quadratic + p2Quadratic + p3Quadratic,
            2025 ether + 625 ether + 576 ether,
            "Total quadratic funding calculation"
        );
        assertEq(p1Linear + p2Linear + p3Linear, 0 ether, "Total linear funding should be 0 with alpha=1");
        assertEq(
            p1Contributions + p2Contributions + p3Contributions,
            1025 ether + 325 ether + 296 ether,
            "Total contributions calculation"
        );

        // Verify quadratic funding formula: each project gets α × (sum_sqrt)² + (1-α) × sum_contributions
        // With alpha = 1: funding = 1 × quadratic + 0 × linear = quadratic only
        assertEq(p1Quadratic + p1Linear, 2025 ether, "Project 1 total funding should be 2025");
        assertEq(p2Quadratic + p2Linear, 625 ether, "Project 2 total funding should be 625");
        assertEq(p3Quadratic + p3Linear, 576 ether, "Project 3 total funding should be 576");

        // console.log("Multi-user voting scenario complete");
        // console.log("Alice remaining power:", _tokenized(address(mechanism)).votingPower(alice));
        // console.log("Bob remaining power:", _tokenized(address(mechanism)).votingPower(bob));
        // console.log("Charlie remaining power:", _tokenized(address(mechanism)).votingPower(charlie));
    }

    /// @notice Test matching fund calculation and 1:1 shares-to-assets ratio verification
    function testMatchingFundsCalculationAnd1to1Ratio() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup: 3 users with different voting power
        uint256 totalUserDeposits = 1000 ether + 500 ether + 200 ether; // User signup deposits
        _signupUser(alice, 1000 ether);
        _signupUser(bob, 500 ether);
        _signupUser(charlie, 200 ether);

        // Create proposals
        uint256 pid1 = _createProposal(alice, recipient1, "Project Alpha");
        uint256 pid2 = _createProposal(bob, recipient2, "Project Beta");

        // Move to voting period
        vm.roll(startBlock + VOTING_DELAY + 1);

        // Cast votes with specific weights to create known quadratic/linear sums
        _castVote(alice, pid1, 20e9); // Cost: 400 ether
        _castVote(bob, pid1, 15e9); // Cost: 225 ether
        _castVote(alice, pid2, 10e9); // Cost: 100 ether (Alice remaining: 1000-400-100=500)
        _castVote(charlie, pid2, 14e9); // Cost: 196 ether

        console.log("=== MATCHING FUNDS CALCULATION TEST ===");

        // Calculate matching funds needed before finalization
        (uint256 matchingFundsNeeded, uint256 totalQuadraticSum, uint256 totalLinearSum) = _calculateMatchingFunds(
            totalUserDeposits
        );

        console.log("Total Quadratic Sum:", totalQuadraticSum);
        console.log("Total Linear Sum:", totalLinearSum);
        console.log("Matching Funds Needed:", matchingFundsNeeded);

        // Verify the calculation
        // Project 1: (20e9 + 15e9)² = (35e9)² = 1225e18 = 1225 ether
        // Project 2: (10e9 + 14e9)² = (24e9)² = 576e18 = 576 ether
        // Total quadratic sum = 1225 + 576 = 1801 ether
        assertEq(totalQuadraticSum, 1801 ether, "Total quadratic sum should be 1801 ether");

        // Total linear sum = 400 + 225 + 100 + 196 = 921 ether
        assertEq(totalLinearSum, 921 ether, "Total linear sum should be 921 ether");

        // Matching funds needed = 1801 - 921 = 880 ether
        assertEq(matchingFundsNeeded, totalQuadraticSum - totalUserDeposits, "Matching funds should be 880 ether");

        // Verify contract balance vs linear sum
        uint256 contractBalanceBeforeMatching = token.balanceOf(address(mechanism));
        assertEq(contractBalanceBeforeMatching, totalUserDeposits, "Contract should hold total user deposits");

        console.log("Contract balance (user deposits):", contractBalanceBeforeMatching);
        console.log("Total linear sum (vote costs):", totalLinearSum);
        console.log("Difference (unused voting power):", contractBalanceBeforeMatching - totalLinearSum);

        // Add the calculated matching funds
        console.log("Adding matching funds:", matchingFundsNeeded);
        token.mint(address(this), matchingFundsNeeded);
        token.transfer(address(mechanism), matchingFundsNeeded);

        // Verify total contract balance now equals total quadratic sum
        uint256 contractBalanceAfterMatching = token.balanceOf(address(mechanism));
        assertEq(
            contractBalanceAfterMatching,
            totalQuadraticSum,
            "Contract should hold exactly the total quadratic sum after matching"
        );

        // Move past voting period and finalize
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        _tokenized(address(mechanism)).finalizeVoteTally();

        // Queue proposals to actually mint shares and verify ratio is maintained
        _tokenized(address(mechanism)).queueProposal(pid1);
        _tokenized(address(mechanism)).queueProposal(pid2);

        // Verify shares were minted correctly
        uint256 totalSharesIssued = _tokenized(address(mechanism)).totalSupply();
        assertEq(totalSharesIssued, totalQuadraticSum, "Total shares issued should equal total quadratic sum");

        // Verify 1:1 ratio is set after share minting
        uint256 assetsFor1ShareAfterMinting = _tokenized(address(mechanism)).convertToAssets(1e18);
        assertEq(assetsFor1ShareAfterMinting, 1e18, "1:1 ratio should be maintained after share minting");

        // Verify individual recipients got correct share amounts
        uint256 recipient1Shares = _tokenized(address(mechanism)).balanceOf(recipient1);
        uint256 recipient2Shares = _tokenized(address(mechanism)).balanceOf(recipient2);

        assertEq(recipient1Shares, 1225 ether, "Recipient 1 should receive 1225 ether shares");
        assertEq(recipient2Shares, 576 ether, "Recipient 2 should receive 576 ether shares");
        assertEq(recipient1Shares + recipient2Shares, totalSharesIssued, "Individual shares should sum to total");

        console.log("=== TEST COMPLETE ===");
        console.log("Perfect 1:1 shares-to-assets ratio achieved!");
        console.log("Total assets in contract:", token.balanceOf(address(mechanism)));
        console.log("Total shares issued:", totalSharesIssued);
        console.log("Ratio verification: 1e18 shares =", assetsFor1ShareAfterMinting, "assets");
    }

    /// @notice Test optimal alpha calculation for 1:1 shares-to-assets ratio with fixed matching pool
    function testOptimalAlphaCalculationWith1to1Ratio() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup: 3 users with different voting power
        uint256 totalUserDeposits = 1000 ether + 500 ether + 200 ether;
        _signupUser(alice, 1000 ether);
        _signupUser(bob, 500 ether);
        _signupUser(charlie, 200 ether);

        // Create proposals
        uint256 pid1 = _createProposal(alice, recipient1, "Project A");
        uint256 pid2 = _createProposal(bob, recipient2, "Project B");

        // Move to voting period
        vm.roll(startBlock + VOTING_DELAY + 1);

        // Cast votes to create known sums (closer to signup amounts)
        _castVote(alice, pid1, 30e9); // Cost: 900 ether
        _castVote(bob, pid1, 20e9); // Cost: 400 ether
        _castVote(charlie, pid2, 14e9); // Cost: 196 ether

        // console.log("=== OPTIMAL ALPHA CALCULATION TEST ===");

        // Get totals after voting
        uint256 totalQuadraticSum = mechanism.totalQuadraticSum();
        uint256 totalLinearSum = mechanism.totalLinearSum();

        // console.log("Total Quadratic Sum:", totalQuadraticSum);
        // console.log("Total Linear Sum:", totalLinearSum);
        // console.log("Total User Deposits:", totalUserDeposits);

        // Project 1: (30e9 + 20e9)² = (50e9)² = 2500e18 = 2500 ether
        // Project 2: (14e9)² = 196e18 = 196 ether
        // Total quadratic sum = 2500 + 196 = 2696 ether
        assertEq(totalQuadraticSum, 2696 ether, "Total quadratic sum should be 2696 ether");

        // Total linear sum = 900 + 400 + 196 = 1496 ether
        assertEq(totalLinearSum, 1496 ether, "Total linear sum should be 1496 ether");

        // Define a fixed matching pool amount (less than full quadratic advantage)
        uint256 fixedMatchingPool = 300 ether;

        // Calculate optimal alpha
        (uint256 alphaNumerator, uint256 alphaDenominator) = _calculateOptimalAlpha(
            fixedMatchingPool,
            totalQuadraticSum,
            totalLinearSum,
            totalUserDeposits
        );

        // console.log("Fixed matching pool:", fixedMatchingPool);
        // console.log("Calculated alpha:", alphaNumerator, "/", alphaDenominator);

        // Verify alpha calculation using scoping for intermediate variables
        {
            uint256 totalAssetsAvailable = totalUserDeposits + fixedMatchingPool; // 1700 + 300 = 2000
            uint256 quadraticAdvantage = totalQuadraticSum - totalLinearSum; // 2696 - 1496 = 1200
            uint256 expectedNumerator = totalAssetsAvailable - totalLinearSum; // 2000 - 1496 = 504

            // expectedNumerator (504) < quadraticAdvantage (1200), so alpha should be fractional
            assertEq(alphaNumerator, expectedNumerator, "Alpha numerator should be total assets minus linear sum");
            assertEq(alphaDenominator, quadraticAdvantage, "Alpha denominator should be quadratic advantage");
        }

        // Add the fixed matching pool to the mechanism
        token.mint(address(this), fixedMatchingPool);
        token.transfer(address(mechanism), fixedMatchingPool);

        // Update alpha to the calculated optimal value using scoping
        {
            mechanism.setAlpha(alphaNumerator, alphaDenominator);

            // Verify alpha was set correctly
            (uint256 newAlphaNumerator, uint256 newAlphaDenominator) = mechanism.getAlpha();
            assertEq(newAlphaNumerator, alphaNumerator, "Alpha numerator should be updated");
            assertEq(newAlphaDenominator, alphaDenominator, "Alpha denominator should be updated");
        }

        // Verify total assets and calculate expected funding
        uint256 totalAssets = token.balanceOf(address(mechanism));
        assertEq(totalAssets, totalUserDeposits + fixedMatchingPool, "Total assets should be deposits + matching pool");

        // Calculate expected total funding with this alpha using scoping for intermediate variables
        uint256 expectedTotalFunding;
        {
            uint256 expectedQuadraticComponent = (totalQuadraticSum * alphaNumerator) / alphaDenominator;
            uint256 expectedLinearComponent = (totalLinearSum * (alphaDenominator - alphaNumerator)) / alphaDenominator;
            expectedTotalFunding = expectedQuadraticComponent + expectedLinearComponent;

            // console.log("Expected quadratic component:", expectedQuadraticComponent);
            // console.log("Expected linear component:", expectedLinearComponent);
            // console.log("Expected total funding:", expectedTotalFunding);
            // console.log("Actual total assets:", totalAssets);
        }

        // Move past voting period and finalize using scoping for intermediate variables
        {
            vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
            _tokenized(address(mechanism)).finalizeVoteTally();

            // Queue proposals to mint shares
            _tokenized(address(mechanism)).queueProposal(pid1);
            _tokenized(address(mechanism)).queueProposal(pid2);
        }

        // Verify 1:1 ratio is maintained using scoping
        {
            uint256 assetsFor1Share = _tokenized(address(mechanism)).convertToAssets(1e18);
            assertEq(assetsFor1Share, 1e18, "1:1 ratio should be maintained with optimal alpha");

            // Verify total shares match total assets
            uint256 totalShares = _tokenized(address(mechanism)).totalSupply();
            assertEq(totalShares, totalAssets, "Total shares should equal total assets");
            assertEq(totalShares, expectedTotalFunding, "Total shares should equal expected total funding");
        }

        // console.log("=== OPTIMAL ALPHA TEST COMPLETE ===");
        // console.log("Perfect 1:1 ratio achieved with alpha =", alphaNumerator, "/", alphaDenominator);
        // console.log("Total assets:", totalAssets);
        // console.log("Total shares:", totalShares);
        // console.log("1e18 shares converts to:", assetsFor1Share, "assets");
    }
}
