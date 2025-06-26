// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { QuadraticVotingMechanism } from "src/mechanisms/mechanism/QuadraticVotingMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract QuadraticVotingBasicTimelockTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    QuadraticVotingMechanism mechanism;

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
            name: "Basic Test",
            symbol: "BASIC",
            votingDelay: 10,
            votingPeriod: 100,
            quorumShares: 500, // Adjusted for quadratic funding
            timelockDelay: 1000, // 1000 seconds
            gracePeriod: 5000, // 5000 seconds
            startBlock: block.number + 5,
            owner: address(0)
        });

        address mechanismAddr = factory.deployQuadraticVotingMechanism(config, 50, 100); // 50% alpha
        mechanism = QuadraticVotingMechanism(payable(mechanismAddr));
    }

    function testBasicTimelock() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup - register and create proposal
        vm.startPrank(alice);
        token.approve(address(mechanism), 1000 ether);
        _tokenized(address(mechanism)).signup(1000 ether);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Test");
        vm.stopPrank();

        // Vote
        vm.roll(startBlock + 11);
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 31); // 31^2 = 961 > 500 quorum

        // Finalize
        vm.roll(startBlock + 111);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Check initial state before queuing
        assertEq(
            _tokenized(address(mechanism)).redeemableAfter(charlie),
            0,
            "Should have no redeemableAfter before queue"
        );
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0, "Should have no shares before queue");

        // Queue at timestamp 1 (default)
        assertEq(block.timestamp, 1, "Should be at timestamp 1");
        uint256 queueTime = block.timestamp;
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");

        // Verify shares were minted and timelock set
        assertGt(_tokenized(address(mechanism)).balanceOf(charlie), 0, "Should have shares after queue");
        assertEq(
            _tokenized(address(mechanism)).redeemableAfter(charlie),
            queueTime + 1000,
            "Should have correct redeemableAfter"
        );

        // Should be blocked immediately at queue time
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be blocked at queue time");

        // Should be blocked during timelock period (1 second before expiry)
        vm.warp(queueTime + 999);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be blocked 1 second before expiry");

        // Should be allowed at timelock expiry
        vm.warp(queueTime + 1000);
        assertGt(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be allowed at timelock expiry");

        // Should still be allowed after timelock expiry
        vm.warp(queueTime + 1001);
        assertGt(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be allowed after timelock expiry");

        // Should be blocked after grace period expires
        vm.warp(queueTime + 1000 + 5000 + 1);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be blocked after grace period");
    }
}
