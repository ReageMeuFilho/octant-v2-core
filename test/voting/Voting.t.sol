// // SPDX-License-Identifier: AGPL-3.0
// pragma solidity >=0.8.25;

// import {Setup} from "./Setup.sol";
// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// contract VotingTest is Setup {
//     function setUp() public override {
//         super.setUp();
//     }

//     function test_initial_voting_state() public {
//         assertEq(strategy.getTotalVotes(), 0);
//         assertEq(strategy.getProjectVotes(project1), 0);
//         assertEq(strategy.getUserVotes(alice, project1), 0);
//     }

//     function testFuzz_single_vote(uint256 _amount) public {
//         _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        
//         depositAndVote(alice, _amount, project1);
        
//         checkVoteTotals(project1, _amount, _amount);
//         checkUserVotes(alice, project1, _amount);
//     }

//     function test_multiple_votes_same_project() public {
//         uint256 amount1 = 1000e18;
//         uint256 amount2 = 2000e18;
        
//         depositAndVote(alice, amount1, project1);
//         depositAndVote(bob, amount2, project1);
        
//         checkVoteTotals(project1, amount1 + amount2, amount1 + amount2);
//         checkUserVotes(alice, project1, amount1);
//         checkUserVotes(bob, project1, amount2);
//     }

//     function test_vote_distribution_multiple_projects() public {
//         uint256 amount = 1000e18;
        
//         depositAndVote(alice, amount, project1);
//         depositAndVote(bob, amount, project2);
//         depositAndVote(user, amount, project3);
        
//         checkVoteTotals(project1, amount, amount * 3);
//         checkVoteTotals(project2, amount, amount * 3);
//         checkVoteTotals(project3, amount, amount * 3);
//     }

//     function test_vote_decay_over_time() public {
//         uint256 amount = 1000e18;
        
//         depositAndVote(alice, amount, project1);
        
//         // Initial vote weight
//         uint256 initialVotes = strategy.getProjectVotes(project1);
//         assertEq(initialVotes, amount);
        
//         // Skip time and check decay
//         skip(30 days);
        
//         uint256 decayedVotes = strategy.getProjectVotes(project1);
//         assertLe(decayedVotes, initialVotes, "Votes should decay");
//     }

//     function test_vote_reverts_invalid_project() public {
//         uint256 amount = 1000e18;
//         address invalidProject = address(0x123);
        
//         // Mint and approve
//         asset.mint(alice, amount);
//         vm.prank(alice);
//         asset.approve(address(strategy), amount);
        
//         // Deposit
//         vm.prank(alice);
//         strategy.deposit(amount, alice);
        
//         // Try to vote for invalid project
//         vm.prank(alice);
//         vm.expectRevert("INVALID_PROJECT");
//         strategy.vote(invalidProject, amount);
//     }

//     function test_vote_exceeds_balance_reverts() public {
//         uint256 deposit = 1000e18;
//         uint256 voteAmount = deposit + 1;
        
//         // Deposit
//         asset.mint(alice, deposit);
//         vm.prank(alice);
//         asset.approve(address(strategy), deposit);
//         vm.prank(alice);
//         strategy.deposit(deposit, alice);
        
//         // Try to vote more than balance
//         vm.prank(alice);
//         vm.expectRevert("INSUFFICIENT_BALANCE");
//         strategy.vote(project1, voteAmount);
//     }

//     function test_vote_updates_share_allocation() public {
//         uint256 amount = 1000e18;
        
//         depositAndVote(alice, amount, project1);
        
//         // Check share allocation
//         uint256 projectShares = strategy.balanceOf(project1);
//         assertGt(projectShares, 0, "Project should receive shares");
//         assertEq(projectShares, amount, "Shares should match vote weight");
//     }
// } 