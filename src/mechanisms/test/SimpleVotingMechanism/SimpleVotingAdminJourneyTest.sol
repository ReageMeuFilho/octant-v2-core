// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { TokenizedAllocationMechanism } from "../../TokenizedAllocationMechanism.sol";
import { SimpleVotingMechanism } from "../../mechanism/SimpleVotingMechanism.sol";
import { AllocationMechanismFactory } from "../../AllocationMechanismFactory.sol";
import { AllocationConfig } from "../../BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/// @title Admin Journey Integration Tests
/// @notice Comprehensive tests for admin user journey covering deployment, monitoring, and execution
contract SimpleVotingAdminJourneyTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;
    
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address dave = address(0x4);
    address newOwner = address(0xa);
    
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
        
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Admin Journey Test",
            symbol: "AJTEST",
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
    
    /// @notice Test admin deployment and configuration verification
    function testAdminDeployment_ConfigurationVerification() public {
        // Verify factory deployment state
        assertEq(factory.getDeployedCount(), 1);
        assertTrue(factory.isMechanism(address(mechanism)));
        assertNotEq(factory.tokenizedAllocationImplementation(), address(0));
        
        // Verify mechanism configuration
        assertEq(_tokenized(address(mechanism)).name(), "Admin Journey Test");
        assertEq(_tokenized(address(mechanism)).symbol(), "AJTEST");
        assertEq(address(_tokenized(address(mechanism)).asset()), address(token));
        assertEq(_tokenized(address(mechanism)).votingDelay(), VOTING_DELAY);
        assertEq(_tokenized(address(mechanism)).votingPeriod(), VOTING_PERIOD);
        assertEq(_tokenized(address(mechanism)).quorumShares(), QUORUM_REQUIREMENT);
        assertEq(_tokenized(address(mechanism)).timelockDelay(), TIMELOCK_DELAY);
        
        // Verify owner context (deployer becomes owner)
        assertEq(_tokenized(address(mechanism)).owner(), address(this));
        
        // Deploy second mechanism to test isolation
        AllocationConfig memory config2 = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Second Mechanism",
            symbol: "SECOND",
            votingDelay: 50,
            votingPeriod: 500,
            quorumShares: 100 ether,
            timelockDelay: 2 days,
            gracePeriod: 14 days,
            startBlock: block.number + 100,
            owner: address(0)
        });
        
        address mechanism2Addr = factory.deploySimpleVotingMechanism(config2);
        
        // Verify isolation between mechanisms
        assertEq(factory.getDeployedCount(), 2);
        assertEq(_tokenized(address(mechanism)).name(), "Admin Journey Test");
        assertEq(_tokenized(mechanism2Addr).name(), "Second Mechanism");
        assertEq(_tokenized(address(mechanism)).votingDelay(), VOTING_DELAY);
        assertEq(_tokenized(mechanism2Addr).votingDelay(), 50);
    }
    
    /// @notice Test admin monitoring during voting process
    function testAdminMonitoring_VotingProcess() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
        // Setup realistic voting scenario
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();
        
        // Admin monitors proposal creation
        vm.prank(alice);
        uint256 pid1 = _tokenized(address(mechanism)).propose(charlie, "Infrastructure Project");
        
        vm.prank(bob);
        uint256 pid2 = _tokenized(address(mechanism)).propose(dave, "Community Initiative");
        
        assertEq(_tokenized(address(mechanism)).getProposalCount(), 2);
        
        // Admin monitors voting progress
        vm.roll(startBlock + VOTING_DELAY + 1);
        
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.For, 600 ether);
        
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.Against, 100 ether);
        
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.For, 400 ether);
        
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.For, 400 ether);
        
        // Admin checks real-time vote tallies
        (uint256 p1For, uint256 p1Against,) = _tokenized(address(mechanism)).getVoteTally(pid1);
        assertEq(p1For, 600 ether);
        assertEq(p1Against, 100 ether);
        
        (uint256 p2For,,) = _tokenized(address(mechanism)).getVoteTally(pid2);
        assertEq(p2For, 800 ether);
        
        // Admin monitors proposal states during voting
        assertEq(uint(_tokenized(address(mechanism)).state(pid1)), uint(TokenizedAllocationMechanism.ProposalState.Active));
        assertEq(uint(_tokenized(address(mechanism)).state(pid2)), uint(TokenizedAllocationMechanism.ProposalState.Active));
    }
    
    /// @notice Test admin finalization process
    function testAdminFinalization_Process() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
        // Setup voting
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();
        
        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Test Proposal");
        
        vm.roll(startBlock + VOTING_DELAY + 1);
        
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether);
        
        // Cannot finalize before voting period ends
        vm.expectRevert();
        _tokenized(address(mechanism)).finalizeVoteTally();
        
        // Successful finalization after voting period
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        assertFalse(_tokenized(address(mechanism)).tallyFinalized());
        
        _tokenized(address(mechanism)).finalizeVoteTally();
        assertTrue(_tokenized(address(mechanism)).tallyFinalized());
        
        // Cannot finalize twice
        vm.expectRevert(TokenizedAllocationMechanism.TallyAlreadyFinalized.selector);
        _tokenized(address(mechanism)).finalizeVoteTally();
    }
    
    /// @notice Test admin proposal queuing and execution
    function testAdminExecution_ProposalQueuing() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
        // Setup successful and failed proposals
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        token.approve(address(mechanism), MEDIUM_DEPOSIT);
        _tokenized(address(mechanism)).signup(MEDIUM_DEPOSIT);
        vm.stopPrank();
        
        vm.prank(alice);
        uint256 pidSuccessful = _tokenized(address(mechanism)).propose(charlie, "Successful Project");
        
        vm.prank(bob);
        uint256 pidFailed = _tokenized(address(mechanism)).propose(dave, "Failed Project");
        
        vm.roll(startBlock + VOTING_DELAY + 1);
        
        // Create outcomes: one success, one failure
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pidSuccessful, TokenizedAllocationMechanism.VoteType.For, 800 ether);
        
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pidSuccessful, TokenizedAllocationMechanism.VoteType.For, 300 ether);
        
        // Failed proposal gets insufficient votes
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pidFailed, TokenizedAllocationMechanism.VoteType.For, 100 ether);
        
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success,) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");
        
        // Queue successful proposal
        assertEq(uint(_tokenized(address(mechanism)).state(pidSuccessful)), uint(TokenizedAllocationMechanism.ProposalState.Succeeded));
        
        uint256 timestampBefore = block.timestamp;
        (bool success2,) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pidSuccessful));
        require(success2, "Queue successful proposal failed");
        
        // Verify queuing effects
        assertEq(uint(_tokenized(address(mechanism)).state(pidSuccessful)), uint(TokenizedAllocationMechanism.ProposalState.Queued));
        assertEq(_tokenized(address(mechanism)).proposalShares(pidSuccessful), 1100 ether);
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 1100 ether);
        assertEq(_tokenized(address(mechanism)).redeemableAfter(charlie), timestampBefore + TIMELOCK_DELAY);
        
        // Cannot queue failed proposal
        assertEq(uint(_tokenized(address(mechanism)).state(pidFailed)), uint(TokenizedAllocationMechanism.ProposalState.Defeated));
        
        vm.expectRevert(); // Should revert with NoQuorum or similar for defeated proposal
        _tokenized(address(mechanism)).queueProposal(pidFailed);
        
        // Cannot queue already queued proposal
        vm.expectRevert(abi.encodeWithSelector(TokenizedAllocationMechanism.AlreadyQueued.selector, pidSuccessful));
        _tokenized(address(mechanism)).queueProposal(pidSuccessful);
    }
    
    /// @notice Test admin emergency functions
    function testAdminEmergency_Functions() public {
        // Test pause mechanism
        assertFalse(_tokenized(address(mechanism)).paused());
        
        (bool success,) = address(mechanism).call(abi.encodeWithSignature("pause()"));
        require(success, "Pause failed");
        assertTrue(_tokenized(address(mechanism)).paused());
        
        // Paused mechanism blocks operations
        vm.expectRevert(TokenizedAllocationMechanism.PausedError.selector);
        vm.prank(alice);
        _tokenized(address(mechanism)).signup(100 ether);
        
        // Unpause mechanism
        (bool success2,) = address(mechanism).call(abi.encodeWithSignature("unpause()"));
        require(success2, "Unpause failed");
        assertFalse(_tokenized(address(mechanism)).paused());
        
        // Transfer ownership
        (bool success3,) = address(mechanism).call(abi.encodeWithSignature("transferOwnership(address)", newOwner));
        require(success3, "Transfer ownership failed");
        assertEq(_tokenized(address(mechanism)).owner(), newOwner);
        
        // Old owner cannot perform owner functions
        vm.expectRevert(TokenizedAllocationMechanism.Unauthorized.selector);
        _tokenized(address(mechanism)).pause();
        
        // New owner can perform owner functions
        vm.startPrank(newOwner);
        (bool success5,) = address(mechanism).call(abi.encodeWithSignature("pause()"));
        require(success5, "New owner pause failed");
        assertTrue(_tokenized(address(mechanism)).paused());
        vm.stopPrank();
    }
    
    /// @notice Test admin crisis management and recovery
    function testAdminCrisis_ManagementRecovery() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
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
        
        vm.roll(startBlock + VOTING_DELAY + 1);
        
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether);
        
        // Emergency pause during voting
        (bool success,) = address(mechanism).call(abi.encodeWithSignature("pause()"));
        require(success, "Pause failed");
        
        // All operations blocked
        vm.expectRevert(TokenizedAllocationMechanism.PausedError.selector);
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether);
        
        // Resume operations
        (bool success2,) = address(mechanism).call(abi.encodeWithSignature("unpause()"));
        require(success2, "Unpause failed");
        
        // Operations work again - use bob since alice already voted
        vm.prank(bob);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 100 ether);
        
        // Ownership transfer during crisis
        address emergencyAdmin = newOwner;
        (bool success3,) = address(mechanism).call(abi.encodeWithSignature("transferOwnership(address)", emergencyAdmin));
        require(success3, "Transfer ownership failed");
        
        // New owner manages crisis
        vm.startPrank(emergencyAdmin);
        (bool success4,) = address(mechanism).call(abi.encodeWithSignature("pause()"));
        require(success4, "Emergency admin pause failed");
        vm.stopPrank();
        
        // System recovery after crisis
        vm.startPrank(emergencyAdmin);
        (bool success5,) = address(mechanism).call(abi.encodeWithSignature("unpause()"));
        require(success5, "Recovery unpause failed");
        vm.stopPrank();
        
        // Complete voting cycle to verify system integrity
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        
        vm.startPrank(emergencyAdmin);
        (bool success6,) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success6, "Emergency finalization failed");
        
        (bool success7,) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success7, "Emergency queuing failed");
        vm.stopPrank();
        
        // System functions normally - both alice (500) and bob (100) votes = 600 total
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 600 ether);
        assertEq(uint(_tokenized(address(mechanism)).state(pid)), uint(TokenizedAllocationMechanism.ProposalState.Queued));
    }
}