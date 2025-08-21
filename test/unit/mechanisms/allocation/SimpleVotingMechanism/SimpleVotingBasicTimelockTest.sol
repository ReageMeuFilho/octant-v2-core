// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { SimpleVotingMechanism } from "test/mocks/SimpleVotingMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract SimpleVotingBasicTimelockTest is Test {
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
            name: "Basic Test",
            symbol: "BASIC",
            votingDelay: 10,
            votingPeriod: 100,
            quorumShares: 200 ether,
            timelockDelay: 1000, // 1000 seconds
            gracePeriod: 5000, // 5000 seconds
            owner: address(0)
        });

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }

    function testBasicTimelock() public {
        // Capture deployment time (when mechanism was deployed and startTime was set)
        uint256 deploymentTime = block.timestamp;

        // Fetch timeline configuration from the deployed mechanism using available getters
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 timelockDelay = _tokenized(address(mechanism)).timelockDelay();
        uint256 gracePeriod = _tokenized(address(mechanism)).gracePeriod();

        // Calculate absolute timestamps based on deployment time
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Setup - register and create proposal (before voting starts)
        vm.startPrank(alice);
        token.approve(address(mechanism), 1000 ether);
        _tokenized(address(mechanism)).signup(1000 ether);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Test");
        vm.stopPrank();

        // Vote - warp to voting period and cast vote
        vm.warp(votingStartTime + 1); // Use absolute warp to voting start + 1 second
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether);

        // Finalize - warp to after voting ends and finalize
        vm.warp(votingEndTime + 1); // Use absolute warp to voting end + 1 second
        uint256 finalizeTime = block.timestamp;
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Check that global redemption start was set during finalization
        assertEq(
            _tokenized(address(mechanism)).globalRedemptionStart(),
            finalizeTime + timelockDelay,
            "Should have globalRedemptionStart set after finalize"
        );
        assertEq(_tokenized(address(mechanism)).balanceOf(charlie), 0, "Should have no shares before queue");

        // Queue proposal
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");

        // Verify shares were minted
        assertGt(_tokenized(address(mechanism)).balanceOf(charlie), 0, "Should have shares after queue");
        // Global redemption start remains the same (set during finalize)
        assertEq(
            _tokenized(address(mechanism)).globalRedemptionStart(),
            finalizeTime + timelockDelay,
            "globalRedemptionStart should not change after queue"
        );

        // Should be blocked immediately at queue time
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be blocked at queue time");

        // Should be blocked during timelock period (1 second before expiry)
        vm.warp(finalizeTime + timelockDelay - 1);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be blocked 1 second before expiry");

        // Should be allowed at timelock expiry
        vm.warp(finalizeTime + timelockDelay);
        assertGt(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be allowed at timelock expiry");

        // Should still be allowed after timelock expiry
        vm.warp(finalizeTime + timelockDelay + 1);
        assertGt(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be allowed after timelock expiry");

        // Should be blocked after grace period expires
        vm.warp(finalizeTime + timelockDelay + gracePeriod + 1);
        assertEq(_tokenized(address(mechanism)).maxRedeem(charlie), 0, "Should be blocked after grace period");
    }
}
