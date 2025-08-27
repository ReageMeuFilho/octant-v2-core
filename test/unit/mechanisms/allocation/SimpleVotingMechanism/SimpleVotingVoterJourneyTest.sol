// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { SimpleVotingMechanism } from "src/mechanisms/SimpleVotingMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/// @title Voter Journey Integration Tests
/// @notice Comprehensive tests for voter user journey with full branch coverage
contract SimpleVotingVoterJourneyTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address dave = address(0x4);
    address frank = address(0x6);
    address grace = address(0x7);
    address henry = address(0x8);

    uint256 constant LARGE_DEPOSIT = 1000 ether;
    uint256 constant MEDIUM_DEPOSIT = 500 ether;
    uint256 constant SMALL_DEPOSIT = 100 ether;
    uint256 constant QUORUM_REQUIREMENT = 200 ether;
    uint256 constant VOTING_DELAY = 100;
    uint256 constant VOTING_PERIOD = 1000;

    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
    }

    function setUp() public {
        factory = new AllocationMechanismFactory();
        token = new ERC20Mock();

        // Mint tokens to test actors
        token.mint(alice, 2000 ether);
        token.mint(bob, 1500 ether);
        token.mint(frank, 200 ether);
        token.mint(grace, 50 ether);
        token.mint(henry, 300 ether);

        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Voter Journey Test",
            symbol: "VJTEST",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_REQUIREMENT,
            timelockDelay: 1 days,
            gracePeriod: 7 days,
            owner: address(0)
        });

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }

    /// @notice Test voter registration with various deposit amounts
    function testVoterRegistration_VariousDeposits() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingStartTime = deploymentTime + votingDelay;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        // Large deposit registration
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        assertEq(_tokenized(address(mechanism)).votingPower(alice), LARGE_DEPOSIT);
        assertEq(token.balanceOf(alice), 2000 ether - LARGE_DEPOSIT);

        // Medium deposit registration
        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        assertEq(_tokenized(address(mechanism)).votingPower(bob), MEDIUM_DEPOSIT);

        // Zero deposit registration
        vm.prank(grace);
        _tokenized(address(mechanism)).signup(0);
        assertEq(_tokenized(address(mechanism)).votingPower(grace), 0);

        // Small deposit registration
        vm.startPrank(frank);
        token.approve(address(mechanism), SMALL_DEPOSIT);
        _tokenized(address(mechanism)).signup(SMALL_DEPOSIT);
        vm.stopPrank();

        assertEq(_tokenized(address(mechanism)).votingPower(frank), SMALL_DEPOSIT);

        // Verify total mechanism balance
        assertEq(token.balanceOf(address(mechanism)), LARGE_DEPOSIT + MEDIUM_DEPOSIT + SMALL_DEPOSIT);
    }

    /// @notice Test voter registration edge cases
    function testVoterRegistration_EdgeCases() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        // Register alice first
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        // Cannot register multiple times in SimpleVotingMechanism (blocks re-registration)
        vm.startPrank(alice);
        token.approve(address(mechanism), SMALL_DEPOSIT);
        vm.expectRevert(abi.encodeWithSignature("RegistrationBlocked(address)", alice));
        _tokenized(address(mechanism)).signup(SMALL_DEPOSIT);
        vm.stopPrank();

        // Verify voting power unchanged after blocked re-registration
        uint256 alicePowerAfter = _tokenized(address(mechanism)).votingPower(alice);
        assertEq(alicePowerAfter, LARGE_DEPOSIT, "Re-registration should be blocked, voting power unchanged");

        // Cannot register after voting period ends
        vm.warp(votingEndTime + 1);
        vm.startPrank(henry);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        vm.expectRevert();
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        // Can register at the last valid moment
        vm.warp(votingEndTime - 1);
        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();

        assertEq(_tokenized(address(mechanism)).votingPower(bob), MEDIUM_DEPOSIT);
    }

    /// @notice Test comprehensive voting patterns
    function testVotingPatterns_Comprehensive() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingStartTime = deploymentTime + votingDelay;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        // Register voters
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

        // Create proposals
        vm.prank(alice);
        uint256 pid1 = _tokenized(address(mechanism)).propose(charlie, "Fund Charlie's Project");

        vm.prank(bob);
        uint256 pid2 = _tokenized(address(mechanism)).propose(dave, "Fund Dave's Project");

        // Move to voting period
        vm.warp(votingStartTime + 1);

        // Full power voting
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(
            pid1,
            TokenizedAllocationMechanism.VoteType.For,
            LARGE_DEPOSIT,
            charlie
        );

        assertEq(_tokenized(address(mechanism)).votingPower(alice), 0);
        // SimpleVoting now allows multiple votes per person, so we don't check hasVoted

        // Partial power voting across proposals
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(
            pid1,
            TokenizedAllocationMechanism.VoteType.Against,
            200 ether,
            charlie
        );
        assertEq(_tokenized(address(mechanism)).votingPower(bob), 300 ether);

        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.For, 200 ether, dave);
        assertEq(_tokenized(address(mechanism)).votingPower(bob), 100 ether);

        // Strategic voting
        vm.prank(frank);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.For, 50 ether, dave);
        assertEq(_tokenized(address(mechanism)).votingPower(frank), 50 ether);

        // Verify vote tallies
        (uint256 p1For, uint256 p1Against, ) = mechanism.voteTallies(pid1);
        assertEq(p1For, LARGE_DEPOSIT);
        assertEq(p1Against, 200 ether);

        (uint256 p2For, , ) = mechanism.voteTallies(pid2);
        assertEq(p2For, 250 ether);
    }

    /// @notice Test voting error conditions
    function testVoting_ErrorConditions() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Test Proposal");

        // Cannot vote before voting period
        vm.warp(votingStartTime - 50);
        vm.expectRevert();
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether, charlie);

        // Move to voting period
        vm.warp(votingStartTime + 1);

        // Cannot vote with more power than available
        vm.expectRevert();
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(
            pid,
            TokenizedAllocationMechanism.VoteType.For,
            LARGE_DEPOSIT + 1,
            charlie
        );

        // SimpleVoting now allows multiple votes per person
        // Alice can vote multiple times with remaining power
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether, charlie);

        // Alice can vote again with her remaining power
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.Against, 100 ether, charlie);

        // Verify Alice has used 200 ether total voting power
        assertEq(_tokenized(address(mechanism)).votingPower(alice), LARGE_DEPOSIT - 200 ether);

        // Cannot vote after voting period
        vm.warp(votingEndTime + 1);
        vm.expectRevert();
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether, charlie);

        // Unregistered user cannot vote (back in voting period)
        vm.warp(votingStartTime + 500);
        vm.expectRevert();
        vm.prank(henry);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 1, charlie);
    }

    /// @notice Test voter power conservation and management
    function testVoterPower_ConservationAndManagement() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingStartTime = deploymentTime + votingDelay;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.prank(alice);
        uint256 pid1 = _tokenized(address(mechanism)).propose(charlie, "Proposal 1");
        vm.prank(alice);
        uint256 pid2 = _tokenized(address(mechanism)).propose(dave, "Proposal 2");

        // Move to voting period
        vm.warp(votingStartTime + 1);

        // Track power consumption across multiple votes
        uint256 initialPower = _tokenized(address(mechanism)).votingPower(alice);
        assertEq(initialPower, LARGE_DEPOSIT);

        // First vote
        uint256 vote1Weight = 300 ether;
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.For, vote1Weight, charlie);

        uint256 powerAfterVote1 = _tokenized(address(mechanism)).votingPower(alice);
        assertEq(powerAfterVote1, initialPower - vote1Weight);

        // Second vote with remaining power
        uint256 vote2Weight = 200 ether;
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.Against, vote2Weight, dave);

        uint256 powerAfterVote2 = _tokenized(address(mechanism)).votingPower(alice);
        assertEq(powerAfterVote2, initialPower - vote1Weight - vote2Weight);
        assertEq(powerAfterVote2, 500 ether);

        // Verify vote records
        // SimpleVoting now allows multiple votes per person, so we don't check hasVoted
        // SimpleVoting now allows multiple votes per person, so we don't check hasVoted
        assertEq(_tokenized(address(mechanism)).getRemainingVotingPower(alice), 500 ether);
    }
}
