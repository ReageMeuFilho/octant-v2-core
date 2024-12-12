// // SPDX-License-Identifier: AGPL-3.0
// pragma solidity >=0.8.25;

// import {Setup} from "./Setup.sol";
// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// contract AccountingTest is Setup {
//     function setUp() public override {
//         super.setUp();
//     }

//     function test_initial_state() public {
//         assertEq(strategy.totalAssets(), 0);
//         assertEq(strategy.totalSupply(), 0);
//         assertEq(strategy.getTotalVotes(), 0);
//     }

//     function testFuzz_deposit_and_vote(uint256 _amount) public {
//         _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        
//         // Initial deposit
//         depositAndVote(alice, _amount, project1);

//         // Check vote accounting
//         checkVoteTotals(project1, _amount, _amount);
//         checkUserVotes(alice, project1, _amount);
        
//         // Check asset accounting
//         assertEq(strategy.totalAssets(), _amount);
//         assertEq(asset.balanceOf(address(strategy)), _amount);
//     }

//     function test_multiple_voters() public {
//         uint256 amount1 = 1000e18;
//         uint256 amount2 = 2000e18;
        
//         // Two users vote for same project
//         depositAndVote(alice, amount1, project1);
//         depositAndVote(bob, amount2, project1);

//         // Check vote totals
//         checkVoteTotals(project1, amount1 + amount2, amount1 + amount2);
//         checkUserVotes(alice, project1, amount1);
//         checkUserVotes(bob, project1, amount2);
//     }

//     function test_vote_distribution() public {
//         uint256 amount = 1000e18;
        
//         // Split votes between projects
//         depositAndVote(alice, amount, project1);
//         depositAndVote(bob, amount, project2);
        
//         // Verify distribution
//         checkVoteTotals(project1, amount, amount * 2);
//         checkVoteTotals(project2, amount, amount * 2);
        
//         // Check share allocation
//         assertEq(strategy.balanceOf(project1), amount);
//         assertEq(strategy.balanceOf(project2), amount);
//     }

//     function test_airdrop_handling(uint256 _amount, uint16 _profitFactor) public {
//         _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
//         _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

//         // Initial deposit and vote
//         depositAndVote(alice, _amount, project1);
        
//         // Simulate airdrop
//         uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
//         asset.mint(address(strategy), toAirdrop);

//         // Check that airdrop doesn't affect vote weights
//         checkVoteTotals(project1, _amount, _amount);
        
//         // Process report to handle airdrop
//         vm.prank(keeper);
//         strategy.report();
        
//         // Verify airdrop was properly accounted
//         assertEq(strategy.totalAssets(), _amount + toAirdrop);
//         checkStrategyTotals(strategy, _amount + toAirdrop, _amount + toAirdrop, 0);
//     }

//     function test_maxUint_deposit(uint256 _amount) public {
//         _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        
//         // Setup
//         asset.mint(alice, _amount);
//         vm.prank(alice);
//         asset.approve(address(strategy), type(uint256).max);
        
//         // Deposit max uint
//         vm.prank(alice);
//         strategy.deposit(type(uint256).max, alice);
        
//         // Should deposit available balance
//         assertEq(strategy.totalAssets(), _amount);
//         assertEq(strategy.balanceOf(alice), _amount);
//         assertEq(asset.balanceOf(alice), 0);
//     }

//     function test_zero_asset_deposit_reverts() public {
//         vm.expectRevert("ZERO_ASSETS");
//         strategy.deposit(0, alice);
//     }
// } 