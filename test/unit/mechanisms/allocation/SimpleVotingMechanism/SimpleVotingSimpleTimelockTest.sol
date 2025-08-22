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

contract SimpleVotingSimpleTimelockTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;

    address alice = address(0x1);
    address charlie = address(0x3);

    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
    }

    function setUp() public {
        factory = new AllocationMechanismFactory();
        token = new ERC20Mock();
        token.mint(alice, 2000 ether);

        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Simple Test",
            symbol: "SIMPLE",
            votingDelay: 10,
            votingPeriod: 100,
            quorumShares: 200 ether,
            timelockDelay: 1000, // 1000 seconds for easier testing
            gracePeriod: 5000, // 5000 seconds
            owner: address(0)
        });

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }

    function testSimpleTimelock() public {
        // Get absolute timeline from contract
        uint256 deploymentTime = block.timestamp;
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Stay before voting starts for registration
        vm.warp(votingStartTime - 1);

        // Setup
        vm.startPrank(alice);
        token.approve(address(mechanism), 1000 ether);
        _tokenized(address(mechanism)).signup(1000 ether);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Test");
        vm.stopPrank();

        // Move to voting period
        vm.warp(votingStartTime + 1);
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether, charlie);

        // Move to finalization period
        vm.warp(votingEndTime + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        console.log("=== BEFORE QUEUING ===");
        console.log("Current timestamp:", block.timestamp);
        console.log("Charlie redeemableAfter:", _tokenized(address(mechanism)).globalRedemptionStart());
        console.log("Charlie balance:", _tokenized(address(mechanism)).balanceOf(charlie));
        console.log("Charlie maxRedeem:", _tokenized(address(mechanism)).maxRedeem(charlie));

        uint256 queueTime = block.timestamp;
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");

        console.log("=== AFTER QUEUING ===");
        console.log("Queue time:", queueTime);
        console.log("Current timestamp:", block.timestamp);
        console.log("Timelock delay:", _tokenized(address(mechanism)).timelockDelay());
        console.log("Expected redeemable time:", queueTime + 1000);
        console.log("Charlie redeemableAfter:", _tokenized(address(mechanism)).globalRedemptionStart());
        console.log("Charlie balance:", _tokenized(address(mechanism)).balanceOf(charlie));
        console.log("Charlie maxRedeem:", _tokenized(address(mechanism)).maxRedeem(charlie));

        // Verify shares were minted and timelock set correctly
        assertGt(_tokenized(address(mechanism)).balanceOf(charlie), 0, "Should have shares after queue");
        assertEq(
            _tokenized(address(mechanism)).globalRedemptionStart(),
            queueTime + 1000,
            "Should have correct redeemableAfter"
        );

        // Test 1: Should be blocked immediately after queuing
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be blocked at queue time");

        // Test 2: Should be blocked during timelock period (1 second before expiry)
        vm.warp(queueTime + 999);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be blocked 1 second before expiry");

        // Test 3: Should be allowed at timelock expiry
        vm.warp(queueTime + 1000);
        assertGt(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be allowed at timelock expiry");

        // Test 4: Should still be allowed after timelock expiry
        vm.warp(queueTime + 1001);
        assertGt(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be allowed after timelock expiry");
    }
}
