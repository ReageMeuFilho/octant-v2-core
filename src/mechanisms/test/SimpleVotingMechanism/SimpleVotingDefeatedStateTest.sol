// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { SimpleVotingMechanism } from "src/mechanisms/mechanism/SimpleVotingMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract SimpleVotingDefeatedStateTest is Test {
    AllocationMechanismFactory factory;
    ERC20Mock token;
    SimpleVotingMechanism mechanism;

    address alice = address(0x1);
    address frank = address(0x6);

    uint256 constant LARGE_DEPOSIT = 1000 ether;
    uint256 constant QUORUM_REQUIREMENT = 200 ether;
    uint256 constant VOTING_DELAY = 100;
    uint256 constant VOTING_PERIOD = 1000;

    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
    }

    function setUp() public {
        factory = new AllocationMechanismFactory();
        token = new ERC20Mock();
        token.mint(alice, 2000 ether);

        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Debug Defeated",
            symbol: "DEBUG",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_REQUIREMENT,
            timelockDelay: 1 days,
            gracePeriod: 7 days,
            startBlock: block.number + 50,
            owner: address(0)
        });

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        mechanism = SimpleVotingMechanism(payable(mechanismAddr));
    }

    function testDebugDefeatedState() public {
        uint256 startBlock = _tokenized(address(mechanism)).startBlock();
        vm.roll(startBlock - 1);

        // Setup voter
        vm.startPrank(alice);
        token.approve(address(mechanism), LARGE_DEPOSIT);
        _tokenized(address(mechanism)).signup(LARGE_DEPOSIT);
        vm.stopPrank();

        console.log("Alice voting power:", _tokenized(address(mechanism)).votingPower(alice));
        console.log("Quorum requirement:", _tokenized(address(mechanism)).quorumShares());

        // Create proposal that should be defeated
        vm.prank(alice);
        uint256 pid = _tokenized(address(mechanism)).propose(frank, "Frank's Low Vote Proposal");

        vm.roll(startBlock + VOTING_DELAY + 1);

        // Vote with insufficient amount (150 ether < 200 ether quorum)
        vm.prank(alice);
        _tokenized(address(mechanism)).castVote(pid, TokenizedAllocationMechanism.VoteType.For, 150 ether);

        console.log("Votes cast: 150 ether");

        // Check vote tally before finalization
        (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) = _tokenized(address(mechanism)).getVoteTally(
            pid
        );
        console.log("For votes:", forVotes / 1e18);
        console.log("Against votes:", againstVotes / 1e18);
        console.log("Abstain votes:", abstainVotes / 1e18);

        // Finalize voting
        vm.roll(startBlock + VOTING_DELAY + VOTING_PERIOD + 1);
        (bool success, ) = address(mechanism).call(abi.encodeWithSignature("finalizeVoteTally()"));
        require(success, "Finalization failed");

        // Check if proposal has quorum
        (bool success2, ) = address(mechanism).call(abi.encodeWithSignature("hasQuorumHook(uint256)", pid));
        console.log("hasQuorumHook call success:", success2);

        // Check net votes
        uint256 netVotes = forVotes > againstVotes ? forVotes - againstVotes : 0;
        console.log("Net votes:", netVotes / 1e18);
        console.log("Quorum requirement:", QUORUM_REQUIREMENT / 1e18);
        console.log("Has quorum:", netVotes >= QUORUM_REQUIREMENT);

        // Check actual state
        uint256 actualState = uint(_tokenized(address(mechanism)).state(pid));
        console.log("Actual state:", actualState);
        console.log("Expected Defeated state:", uint(TokenizedAllocationMechanism.ProposalState.Defeated));

        if (actualState == uint(TokenizedAllocationMechanism.ProposalState.Defeated)) {
            console.log("SUCCESS: Proposal is correctly DEFEATED");
        } else {
            console.log("FAILURE: Proposal should be DEFEATED but has different state");

            if (actualState == uint(TokenizedAllocationMechanism.ProposalState.Active)) {
                console.log("State is ACTIVE");
            } else if (actualState == uint(TokenizedAllocationMechanism.ProposalState.Succeeded)) {
                console.log("State is SUCCEEDED");
            } else if (actualState == uint(TokenizedAllocationMechanism.ProposalState.Pending)) {
                console.log("State is PENDING");
            }
        }
    }
}
