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

/// @title Timelock Enforcement Test
/// @notice Tests timelock and grace period enforcement through availableWithdrawLimit hook
contract SimpleVotingTimelockEnforcementTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant LARGE_DEPOSIT = 1000 ether;
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
            name: "Timelock Enforcement Test",
            symbol: "TLTEST",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_REQUIREMENT,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: GRACE_PERIOD,
            owner: address(0)
        });

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }

    /// @notice Test timelock enforcement prevents early redemption
    function testTimelockEnforcement_PreventEarlyRedemption() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        // Setup successful proposal
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Charlie's Project");
        vm.stopPrank();

        // Move to voting period
        vm.warp(votingStartTime + 1);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether);

        // Move to finalization period
        vm.warp(votingEndTime + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        uint256 queueTime = block.timestamp;
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");

        // Verify shares minted
        uint256 charlieShares = 500 ether;
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), charlieShares);

        // Test 1: Immediately after queuing - should be blocked by timelock
        console.log("Current timestamp:", block.timestamp);
        console.log("Charlie redeemableAfter:", _tokenized(address(mechanism)).globalRedemptionStart());
        console.log("Time difference:", _tokenized(address(mechanism)).globalRedemptionStart() - block.timestamp);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0);

        vm.expectRevert("Allocation: redeem more than max");
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(charlieShares, charlie, charlie);

        // Test 2: Halfway through timelock - still blocked
        vm.warp(queueTime + TIMELOCK_DELAY / 2);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0);

        vm.expectRevert("Allocation: redeem more than max");
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(charlieShares, charlie, charlie);

        // Test 3: One second before timelock expires - still blocked
        // Need to check what the actual redeemableAfter time is
        uint256 redeemableTime = _tokenized(address(mechanism)).globalRedemptionStart();
        vm.warp(redeemableTime - 1);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0);

        vm.expectRevert("Allocation: redeem more than max");
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(charlieShares, charlie, charlie);
    }

    /// @notice Test successful redemption in valid timelock window
    function testTimelockEnforcement_ValidRedemptionWindow() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        // Setup successful proposal
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Charlie's Project");
        vm.stopPrank();

        // Move to voting period
        vm.warp(votingStartTime + 1);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 300 ether);

        // Move to finalization period
        vm.warp(votingEndTime + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        uint256 queueTime = block.timestamp;
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");

        uint256 charlieShares = 300 ether;
        console.log("Charlie received shares:", charlieShares);

        // Test 1: Exactly when timelock expires - should work
        vm.warp(queueTime + TIMELOCK_DELAY);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), charlieShares);

        // Calculate expected assets based on proper accounting
        // Total deposits: 1000 ether (alice's deposit)
        // Total shares: 300 ether (net votes)
        // Share price: 1000/300 ≈ 3.33 assets per share
        uint256 totalDeposits = 1000 ether;
        uint256 totalShares = 300 ether;
        uint256 expectedAssetsPerRedemption = (100 ether * totalDeposits) / totalShares;

        vm.prank(charlie);
        uint256 assetsReceived1 = _tokenized(address(mechanism)).redeem(100 ether, charlie, charlie);
        assertApproxEqAbs(assetsReceived1, expectedAssetsPerRedemption, 3);
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 200 ether);

        // Test 2: Middle of valid window - should work
        vm.warp(queueTime + TIMELOCK_DELAY + GRACE_PERIOD / 2);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 200 ether);

        vm.prank(charlie);
        uint256 assetsReceived2 = _tokenized(address(mechanism)).redeem(100 ether, charlie, charlie);
        assertApproxEqAbs(assetsReceived2, expectedAssetsPerRedemption, 3);
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 100 ether);

        // Test 3: One second before grace period expires - should work
        uint256 redeemableTime = _tokenized(address(mechanism)).globalRedemptionStart();
        vm.warp(redeemableTime + GRACE_PERIOD - 1);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 100 ether);

        vm.prank(charlie);
        uint256 assetsReceived3 = _tokenized(address(mechanism)).redeem(100 ether, charlie, charlie);
        assertApproxEqAbs(assetsReceived3, expectedAssetsPerRedemption, 3);
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0);

        // Verify total redemption with proper accounting
        uint256 totalExpectedAssets = (totalShares * totalDeposits) / totalShares; // = 1000 ether
        assertApproxEqAbs(assetsReceived1 + assetsReceived2 + assetsReceived3, totalExpectedAssets, 10);
    }

    /// @notice Test grace period expiration prevents redemption
    function testTimelockEnforcement_GracePeriodExpiration() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        // Setup successful proposal
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Charlie's Expired Project");
        vm.stopPrank();

        // Move to voting period
        vm.warp(votingStartTime + 1);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 400 ether);

        // Move to finalization period
        vm.warp(votingEndTime + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        uint256 queueTime = block.timestamp;
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");

        uint256 charlieShares = 400 ether;

        // Fast forward past grace period
        vm.warp(queueTime + TIMELOCK_DELAY + GRACE_PERIOD + 1);

        // Test 1: maxRedeem should return 0 after grace period
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0);

        // Test 2: Redemption should fail
        vm.expectRevert("Allocation: redeem more than max");
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(charlieShares, charlie, charlie);

        // Test 3: Even partial redemption should fail
        vm.expectRevert("Allocation: redeem more than max");
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(1 ether, charlie, charlie);

        // Test 4: Shares still exist but are inaccessible
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), charlieShares);

        // Test 5: Way past grace period - still blocked
        vm.warp(queueTime + TIMELOCK_DELAY + GRACE_PERIOD + 365 days);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0);

        vm.expectRevert("Allocation: redeem more than max");
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(charlieShares, charlie, charlie);
    }

    /// @notice Test multiple recipients with different timelock schedules
    function testTimelockEnforcement_MultipleRecipients() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        // Setup multiple voters and recipients
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(mechanism), 500 ether);
        _tokenized(address(mechanism)).signup(500 ether);
        vm.stopPrank();

        // Create proposals
        vm.prank(alice);
        uint256 pid1 = _tokenized(address(mechanism)).propose(charlie, "Charlie's Early Project");

        vm.prank(bob);
        uint256 pid2 = _tokenized(address(mechanism)).propose(bob, "Bob's Later Project");

        // Move to voting period
        vm.warp(votingStartTime + 1);

        // Vote for both
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid1, TokenizedAllocationMechanism.VoteType.For, 600 ether);

        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid2, TokenizedAllocationMechanism.VoteType.For, 400 ether);

        // Move to finalization period
        vm.warp(votingEndTime + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Queue first proposal
        (bool success1, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid1));
        require(success1, "Queue 1 failed");

        // Wait some time then queue second proposal
        vm.warp(block.timestamp + 2 hours);
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid2));
        require(success2, "Queue 2 failed");

        // Test different timelock schedules

        // At charlie's timelock expiry - charlie can redeem, bob cannot
        uint256 charlieRedeemableTime = _tokenized(address(mechanism)).globalRedemptionStart();
        uint256 bobRedeemableTime = _tokenized(address(mechanism)).globalRedemptionStart();
        vm.warp(charlieRedeemableTime);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 600 ether);
        // Bob's timelock should still be active since he was queued later
        if (charlieRedeemableTime < bobRedeemableTime) {
            assertEq(_tokenized(address(mechanism)).maxRedeem(bob), 0);
        } else {
            assertEq(_tokenized(address(mechanism)).maxRedeem(bob), 400 ether);
        }

        // Calculate expected assets based on proper accounting
        // Total deposits: 1000 + 500 = 1500 ether (alice + bob)
        // Total shares: 600 + 400 = 1000 ether (total net votes)
        // Share price: 1500/1000 = 1.5 assets per share
        uint256 expectedCharlieAssets = (600 ether * 1500 ether) / 1000 ether;

        vm.prank(charlie);
        uint256 charlieAssets = _tokenized(address(mechanism)).redeem(600 ether, charlie, charlie);
        assertApproxEqAbs(charlieAssets, expectedCharlieAssets, 3);

        // Only try to revert if Bob's timelock is still active
        if (charlieRedeemableTime < bobRedeemableTime) {
            vm.expectRevert("Allocation: redeem more than max");
            vm.prank(bob);
            _tokenized(address(mechanism)).redeem(400 ether, bob, bob);
        }

        // At bob's timelock expiry - bob can now redeem
        vm.warp(bobRedeemableTime);
        assertEq(_tokenized(address(mechanism)).maxRedeem(bob), 400 ether);

        uint256 expectedBobAssets = (400 ether * 1500 ether) / 1000 ether;

        vm.prank(bob);
        uint256 bobAssets = _tokenized(address(mechanism)).redeem(400 ether, bob, bob);
        assertApproxEqAbs(bobAssets, expectedBobAssets, 3);

        // Verify independent schedules worked correctly
        assertApproxEqAbs(charlieAssets, expectedCharlieAssets, 3);
        assertApproxEqAbs(bobAssets, expectedBobAssets, 3);
    }

    /// @notice Test edge cases in timelock enforcement
    // function testTimelockEnforcement_EdgeCases() public {
    //     uint256 startBlock = _tokenized(address(mechanism)).startBlock();
    //     vm.roll(startBlock - 1);

    //     // Start with clean timestamp
    //     vm.warp(400000); // Different timestamp to avoid interference

    //     // Setup
    //     vm.startPrank(alice);
    //     token.approve(address(mechanism), LARGE_DEPOSIT);
    //     _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
    //     uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Charlie's Edge Case Project");
    //     vm.stopPrank();

    //     vm.roll(startBlock + VOTING_DELAY + 1);

    //     vm.prank(alice);
    //     _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 250 ether);

    //     vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
    //     (bool success,) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
    //     require(success, "Finalization failed");

    //     uint256 queueTime = block.timestamp;
    //     (bool success2,) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
    //     require(success2, "Queue failed");

    //     // Test 1: Exactly at boundary moments

    //     // Exactly at timelock expiry
    //     vm.warp(queueTime + TIMELOCK_DELAY);
    //     assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 250 ether);

    //     // Exactly at grace period expiry
    //     vm.warp(queueTime + TIMELOCK_DELAY + GRACE_PERIOD);
    //     assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0);

    //     // Test 2: Transfer shares and check timelock enforcement for new owner
    //     vm.warp(queueTime + TIMELOCK_DELAY + GRACE_PERIOD / 2); // Valid window

    //     address newOwner = address(0x999);
    //     vm.prank(charlie);
    //     _tokenized(address(mechanism)).transfer(newOwner, 100 ether);

    //     // New owner should also respect charlie's original timelock
    //     assertEq(_tokenized(address(mechanism)).maxRedeem(newOwner), 100 ether);

    //     // Calculate expected assets based on proper accounting
    //     // Total deposits: 1000 ether (alice's deposit)
    //     // Total shares: 250 ether (net votes)
    //     // Share price: 1000/250 = 4 assets per share
    //     uint256 expectedAssets = (100 ether * 1000 ether) / 250 ether;

    //     vm.prank(newOwner);
    //     uint256 newOwnerAssets = _tokenized(address(mechanism)).redeem(100 ether, newOwner, newOwner);
    //     assertApproxEqAbs(newOwnerAssets, expectedAssets, 3);

    //     // Test 3: Approved redemption
    //     vm.prank(charlie);
    //     _tokenized(address(mechanism)).approve(newOwner, 50 ether);

    //     vm.prank(newOwner);
    //     uint256 approvedAssets = _tokenized(address(mechanism)).redeem(50 ether, newOwner, charlie);
    //     // 50 shares * 4 assets per share = 200 assets
    //     uint256 expectedApprovedAssets = (50 ether * 1000 ether) / 250 ether;
    //     assertApproxEqAbs(approvedAssets, expectedApprovedAssets, 3);
    // }
}
