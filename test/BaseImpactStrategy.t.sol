// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Base.t.sol";
import {MockImpactStrategy} from "./mocks/MockImpactStrategy.sol";
import {MockProjectRegistry} from "./mocks/MockProjectRegistry.sol";
import {MockVeToken} from "./mocks/MockVeToken.sol";

import {IImpactStrategy} from "../src/interfaces/IImpactStrategy.sol";

contract BaseImpactStrategyTest is BaseTest {
    address keeper = makeAddr("keeper");
    address management = makeAddr("management");
    address voter = makeAddr("voter");
    address project = makeAddr("project");

    testTemps temps;
    MockImpactStrategy implementation;
    MockImpactStrategy strategy;
    MockProjectRegistry registry;
    MockVeToken veToken;

    string public name = "Test Impact Strategy";
    uint256 public constant INITIAL_DEPOSIT = 1 ether;
    uint256 public constant VOTE_AMOUNT = 0.5 ether;

    function setUp() public {
        _configure(true);

        // Deploy mocks
        implementation = new MockImpactStrategy();
        registry = new MockProjectRegistry();
        veToken = new MockVeToken("Vote Token", "veTKN");
        
        // Initialize strategy
        temps = _testTemps(
            address(implementation),
            abi.encode(
                address(veToken),
                address(registry),
                management,
                keeper,
                name
            )
        );
        strategy = MockImpactStrategy(payable(temps.module));

        // Register test project
        registry.addProject(project);
    }

    /// @dev tests if initial params are set correctly
    function testInitialize() public {
        assertEq(address(strategy.ASSET()), address(veToken));
        assertEq(strategy.management(), management);
        assertEq(strategy.keeper(), keeper);
        assertEq(strategy.projectRegistry(), address(registry));
    }

    /// @dev tests deposit and veToken minting
    function testDeposit() public {
        // Setup
        deal(address(veToken), voter, INITIAL_DEPOSIT);

        vm.startPrank(voter);
        veToken.approve(address(strategy), INITIAL_DEPOSIT);

        // Test deposit limits
        assertEq(strategy.availableDepositLimit(voter), type(uint256).max);

        // Test deposit
        uint256 veTokensBefore = strategy.balanceOf(voter);
        strategy.deposit(INITIAL_DEPOSIT, voter);
        uint256 veTokensAfter = strategy.balanceOf(voter);

        // Verify deposit results
        assertGt(veTokensAfter, veTokensBefore);
        assertEq(veToken.balanceOf(address(strategy)), INITIAL_DEPOSIT);

        vm.stopPrank();
    }

    /// @dev tests vote casting and processing
    function testVoting() public {
        // Setup - deposit and get veTokens
        _deposit(voter, INITIAL_DEPOSIT);

        vm.startPrank(voter);

        // Check sybil resistance
        (bool passed, uint256 score) = strategy.checkSybilResistance(voter);
        assertTrue(passed);
        assertGt(score, 0);

        // Cast vote
        strategy.vote(project, VOTE_AMOUNT);

        // Verify vote recording
        assertEq(strategy.getUserVotes(voter, project), VOTE_AMOUNT);
        assertEq(strategy.getProjectVotes(project), VOTE_AMOUNT);
        assertEq(strategy.getTotalVotes(), VOTE_AMOUNT);

        vm.stopPrank();
    }

    /// @dev tests vote tallying and adjustments
    function testVoteTallying() public {
        // Setup - deposit and vote
        _depositAndVote(voter, project, INITIAL_DEPOSIT, VOTE_AMOUNT);

        // Test raw tally
        uint256 rawTally = strategy.getProjectVotes(project);
        assertEq(rawTally, VOTE_AMOUNT);

        // Test adjusted tally
        uint256 adjustedTally = strategy.adjustVoteTally(project, rawTally);
        assertEq(adjustedTally, rawTally); // Default implementation returns raw tally
    }

    /// @dev tests share allocation
    function testShareAllocation() public {
        // Setup - deposit and vote
        _depositAndVote(voter, project, INITIAL_DEPOSIT, VOTE_AMOUNT);

        vm.prank(keeper);
        strategy.allocateShares();

        // Verify share allocation
        uint256 projectShares = strategy.balanceOf(project);
        assertGt(projectShares, 0);
        
        // Test share adjustment
        uint256 adjustedShares = strategy.adjustShareAllocation(
            project,
            projectShares,
            VOTE_AMOUNT,
            strategy.getTotalVotes()
        );
        assertEq(adjustedShares, projectShares); // Default implementation returns base shares
    }

    /// @dev tests emergency functions
    function testEmergencyFunctions() public {
        _deposit(voter, INITIAL_DEPOSIT);

        vm.startPrank(management);

        // Test shutdown
        strategy.shutdownStrategy();
        assertTrue(strategy.isShutdown());

        // Test emergency withdrawal
        uint256 emergencyAmount = INITIAL_DEPOSIT / 2;
        strategy.emergencyWithdraw(emergencyAmount);
        assertEq(veToken.balanceOf(management), emergencyAmount);

        vm.stopPrank();
    }

    /// @dev helper to deposit assets
    function _deposit(address _voter, uint256 _amount) internal {
        deal(address(veToken), _voter, _amount);
        vm.startPrank(_voter);
        veToken.approve(address(strategy), _amount);
        strategy.deposit(_amount, _voter);
        vm.stopPrank();
    }

    /// @dev helper to deposit and vote
    function _depositAndVote(
        address _voter,
        address _project,
        uint256 _depositAmount,
        uint256 _voteAmount
    ) internal {
        _deposit(_voter, _depositAmount);
        vm.prank(_voter);
        strategy.vote(_project, _voteAmount);
    }
}
