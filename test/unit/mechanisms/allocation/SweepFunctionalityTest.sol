// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { SimpleVotingMechanism } from "test/mocks/SimpleVotingMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract SweepFunctionalityTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    ERC20Mock randomToken;
    SimpleVotingMechanism mechanism;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address sweepReceiver = address(0x999);

    uint256 constant TIMELOCK_DELAY = 1000;
    uint256 constant GRACE_PERIOD = 5000;
    uint256 constant VOTING_DELAY = 10;
    uint256 constant VOTING_PERIOD = 100;

    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
    }

    function setUp() public {
        factory = new AllocationMechanismFactory();
        token = new ERC20Mock();
        randomToken = new ERC20Mock();

        // Mint tokens
        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
        randomToken.mint(address(this), 500 ether); // Will be sent to mechanism later

        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Sweep Test",
            symbol: "SWEEP",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: 200 ether,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: GRACE_PERIOD,
            owner: address(this) // Factory will override this to be msg.sender
        });

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));

        // Send some ETH to the mechanism
        vm.deal(address(mechanism), 10 ether);
    }

    function testSweepAfterGracePeriod() public {
        // ✅ CORRECT: Fetch absolute timeline from contract
        uint256 deploymentTime = block.timestamp; // When mechanism was deployed
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingStartTime = deploymentTime + votingDelay;
        uint256 votingEndTime = votingStartTime + votingPeriod;

        // Setup allocation
        vm.startPrank(alice);
        token.approve(address(mechanism), 1000 ether);
        _tokenized(address(mechanism)).signup(1000 ether);
        uint256 pid = _tokenized(address(mechanism)).propose(charlie, "Test");
        vm.stopPrank();

        // Vote and finalize
        vm.warp(votingStartTime + 1);
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 500 ether, charlie);

        vm.warp(votingEndTime + 1);

        _tokenized(address(mechanism)).finalizeVoteTally();

        // Queue proposal

        _tokenized(address(mechanism)).queueProposal(pid);

        // Charlie partially redeems during grace period
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        vm.prank(charlie);
        _tokenized(address(mechanism)).redeem(200 ether, charlie, charlie);

        // Send random token to mechanism
        randomToken.transfer(address(mechanism), 100 ether);

        // Try to sweep before grace period ends - should fail
        vm.warp(block.timestamp + GRACE_PERIOD - 100);

        vm.expectRevert("Grace period not expired");
        _tokenized(address(mechanism)).sweep(address(token), sweepReceiver);

        // Fast forward past grace period
        vm.warp(block.timestamp + 101);

        // Non-owner cannot sweep
        vm.prank(alice);
        vm.expectRevert(TokenizedAllocationMechanism.Unauthorized.selector);
        _tokenized(address(mechanism)).sweep(address(token), sweepReceiver);

        // Owner can sweep allocation tokens
        uint256 remainingTokens = token.balanceOf(address(mechanism));
        assertTrue(remainingTokens > 0, "Should have remaining tokens");

        _tokenized(address(mechanism)).sweep(address(token), sweepReceiver);

        assertEq(token.balanceOf(sweepReceiver), remainingTokens);
        assertEq(token.balanceOf(address(mechanism)), 0);

        // Owner can sweep random tokens

        _tokenized(address(mechanism)).sweep(address(randomToken), sweepReceiver);

        assertEq(randomToken.balanceOf(sweepReceiver), 100 ether);
        assertEq(randomToken.balanceOf(address(mechanism)), 0);

        // Owner can sweep ETH
        uint256 ethBalance = address(mechanism).balance;
        assertTrue(ethBalance > 0, "Should have ETH balance");

        _tokenized(address(mechanism)).sweep(address(0), sweepReceiver);

        assertEq(sweepReceiver.balance, ethBalance);
        assertEq(address(mechanism).balance, 0);
    }

    function testSweepRequiresRedemptionStarted() public {
        // Try to sweep before any finalization
        vm.expectRevert("Redemption period not started");
        _tokenized(address(mechanism)).sweep(address(token), sweepReceiver);
    }

    function testSweepRequiresGracePeriodExpired() public {
        // ✅ CORRECT: Fetch absolute timeline from contract
        uint256 deploymentTime = block.timestamp; // When mechanism was deployed
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingEndTime = deploymentTime + votingDelay + votingPeriod;

        // Setup and finalize to set globalRedemptionStart
        vm.warp(votingEndTime + 1);
        _tokenized(address(mechanism)).finalizeVoteTally();

        // Try to sweep before grace period expires
        vm.warp(block.timestamp + TIMELOCK_DELAY + GRACE_PERIOD - 1);
        vm.expectRevert("Grace period not expired");
        _tokenized(address(mechanism)).sweep(address(token), sweepReceiver);
    }

    function testSweepInvalidReceiver() public {
        // ✅ CORRECT: Fetch absolute timeline from contract
        uint256 deploymentTime = block.timestamp; // When mechanism was deployed
        uint256 votingDelay = _tokenized(address(mechanism)).votingDelay();
        uint256 votingPeriod = _tokenized(address(mechanism)).votingPeriod();
        uint256 votingEndTime = deploymentTime + votingDelay + votingPeriod;

        // Setup and finalize
        vm.startPrank(alice);
        token.approve(address(mechanism), 1000 ether);
        _tokenized(address(mechanism)).signup(1000 ether);
        vm.stopPrank();

        vm.warp(votingEndTime + 1);

        _tokenized(address(mechanism)).finalizeVoteTally();

        // Fast forward past grace period
        vm.warp(block.timestamp + TIMELOCK_DELAY + GRACE_PERIOD + 1);

        // Try to sweep to zero address

        vm.expectRevert("Invalid receiver");
        _tokenized(address(mechanism)).sweep(address(token), address(0));
    }

    function testSweepNoTokensToSweep() public {
        // Deploy a new mechanism without any ETH
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Empty Sweep Test",
            symbol: "EMPTY",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: 200 ether,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: GRACE_PERIOD,
            owner: address(this)
        });

        address emptyMechanism = factory.deploySimpleVotingMechanism(config);

        // ✅ CORRECT: Fetch absolute timeline from contract
        uint256 deploymentTime = block.timestamp; // When mechanism was deployed
        uint256 votingDelay = _tokenized(emptyMechanism).votingDelay();
        uint256 votingPeriod = _tokenized(emptyMechanism).votingPeriod();
        uint256 votingEndTime = deploymentTime + votingDelay + votingPeriod;

        // Setup and finalize without any deposits
        vm.warp(votingEndTime + 1);

        _tokenized(emptyMechanism).finalizeVoteTally();

        // Fast forward past grace period
        vm.warp(block.timestamp + TIMELOCK_DELAY + GRACE_PERIOD + 1);

        // Try to sweep non-existent tokens
        vm.expectRevert("No tokens to sweep");
        _tokenized(emptyMechanism).sweep(address(token), sweepReceiver);

        // Try to sweep non-existent random tokens
        vm.expectRevert("No tokens to sweep");
        _tokenized(emptyMechanism).sweep(address(randomToken), sweepReceiver);

        // Try to sweep non-existent ETH
        vm.expectRevert("No ETH to sweep");
        _tokenized(emptyMechanism).sweep(address(0), sweepReceiver);
    }

    receive() external payable {}
}
