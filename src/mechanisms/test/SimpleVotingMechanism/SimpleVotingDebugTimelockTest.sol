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

contract SimpleVotingDebugTimelockTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;
    
    address alice = address(0x1);
    address charlie = address(0x3);
    
    uint256 constant LARGE_DEPOSIT = 1000 ether;
    uint256 constant TIMELOCK_DELAY = 1 days;
    
    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
    }
    
    function setUp() public {
        factory = new AllocationMechanismFactory();
        token = new ERC20Mock();
        token.mint(alice, 2000 ether);
        
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Debug Test",
            symbol: "DEBUG", 
            votingDelay: 100,
            votingPeriod: 1000,
            quorumShares: 200 ether,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: 7 days,
            startBlock: block.number + 50,
            owner: address(0)
        });
        
        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }
    
    function testDebugTimelock() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);
        
        // Start with clean timestamp
        vm.warp(100000);
        console.log("Initial timestamp:", block.timestamp);
        
        // Setup successful proposal
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Charlie's Project");
        vm.stopPrank();
        
        vm.roll(startBlock + 101);
        
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether);
        
        vm.roll(startBlock + 1101);
        (bool success,) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");
        
        console.log("=== BEFORE QUEUING ===");
        console.log("Current timestamp:", block.timestamp);
        console.log("Charlie redeemableAfter BEFORE:", _tokenized(address(mechanism)).redeemableAfter(charlie));
        console.log("Charlie balance BEFORE:", _tokenized(address(mechanism)).balanceOf(charlie));
        console.log("Charlie maxRedeem BEFORE:", _tokenized(address(mechanism)).maxRedeem(charlie));
        
        uint256 queueTime = block.timestamp;
        console.log("Queue time:", queueTime);
        console.log("Timelock delay:", _tokenized(address(mechanism)).timelockDelay());
        console.log("Expected redeemable time:", queueTime + TIMELOCK_DELAY);
        
        (bool success2,) = address(mechanism).call(abi.encodeWithSignature("queueProposal(uint256)", pid));
        require(success2, "Queue failed");
        
        console.log("=== AFTER QUEUING ===");
        console.log("Current timestamp:", block.timestamp);
        console.log("Charlie redeemableAfter AFTER:", _tokenized(address(mechanism)).redeemableAfter(charlie));
        console.log("Charlie balance AFTER:", _tokenized(address(mechanism)).balanceOf(charlie));
        console.log("Charlie maxRedeem AFTER:", _tokenized(address(mechanism)).maxRedeem(charlie));
        
        // Check if timelock is working
        uint256 maxRedeem = _tokenized(address(mechanism)).maxRedeem(charlie);
        console.log("Max redeem immediately after queue:", maxRedeem);
        
        if (maxRedeem == 0) {
            console.log("SUCCESS: Timelock is blocking redemption");
        } else {
            console.log("FAILURE: Timelock is NOT blocking redemption");
            console.log("Expected: 0, Got:", maxRedeem);
        }
        
        // Debug the _availableWithdrawLimit logic step by step
        uint256 redeemableTime = _tokenized(address(mechanism)).redeemableAfter(charlie);
        console.log("Debug - redeemableTime:", redeemableTime);
        console.log("Debug - block.timestamp:", block.timestamp);
        console.log("Debug - block.timestamp < redeemableTime:", block.timestamp < redeemableTime);
        
        if (redeemableTime == 0) {
            console.log("DEBUG: redeemableTime is 0 - this should not happen after queuing");
        } else if (block.timestamp < redeemableTime) {
            console.log("DEBUG: We are in timelock period - should return 0");
        } else {
            console.log("DEBUG: We are past timelock - should allow redemption");
        }
    }
}