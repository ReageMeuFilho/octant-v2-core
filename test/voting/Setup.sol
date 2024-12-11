// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.25;

import "forge-std/console.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import { ExtendedTest } from "../vaults/ExtendedTest.sol";
// import { MockImpactStrategy } from "../mocks/MockImpactStrategy.sol";
// import { ImpactStrategy } from "src/impact-strategy/ImpactStrategy.sol";
import { MockProjectRegistry } from "../mocks/MockProjectRegistry.sol";
import { IProjectRegistry } from "src/interfaces/IProjectRegistry.sol";

contract Setup is ExtendedTest {
    // Contract instances
    ERC20Mock public asset;
    ERC20Mock public veToken;
    // MockImpactStrategy public strategy;
    // ImpactStrategy public impactStrategyImplementation;
    IProjectRegistry public projectRegistry;

    string public name = "Test Impact Strategy";
    
    // Role addresses
    address public user;
    address public alice = address(1);
    address public bob = address(2);
    address public keeper = address(3);
    address public management = address(4);
    address public emergencyAdmin = address(5);
    
    // Test projects
    address public project1 = address(10);
    address public project2 = address(11);
    address public project3 = address(12);

    // Constants
    uint256 public decimals = 18;
    uint256 public MAX_BPS = 10_000;
    uint256 public wad = 10 ** decimals;
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;

    function setUp() public virtual {
        // Deploy implementation
        // impactStrategyImplementation = new ImpactStrategy(address(this));
        
        // Deploy mock contracts
        asset = new ERC20Mock();
        veToken = new ERC20Mock();
        projectRegistry = new MockProjectRegistry();
        
        // Register test projects
        projectRegistry.addProject(project1);
        projectRegistry.addProject(project2);
        projectRegistry.addProject(project3);

        // Deploy strategy
        // strategy = MockImpactStrategy(setUpStrategy());

        // Set emergency admin
        vm.prank(management);
        // strategy.setEmergencyAdmin(emergencyAdmin);

        // Label addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(address(veToken), "veToken");
        vm.label(management, "management");
        // vm.label(address(strategy), "strategy");
        vm.label(emergencyAdmin, "emergency admin");
        vm.label(project1, "project1");
        vm.label(project2, "project2");
        vm.label(project3, "project3");
    }

    // function setUpStrategy() public returns (address) {
    //     // Encode initialization parameters
    //     bytes memory initParams = abi.encode(
    //         address(impactStrategyImplementation),
    //         address(asset),
    //         address(veToken),
    //         address(projectRegistry),
    //         management,
    //         keeper,
    //         name
    //     );

    //     // Deploy proxy
    //     testTemps memory temps = _testTemps(
    //         address(strategy),
    //         initParams
    //     );
    //     user = temps.safe;
    //     return address(temps.module);
    // }

    // function depositAndVote(
    //     address _user,
    //     uint256 _amount,
    //     address _project
    // ) public {
    //     // Mint and approve assets
    //     asset.mint(_user, _amount);
    //     vm.prank(_user);
    //     asset.approve(address(strategy), _amount);

    //     // Deposit assets
    //     vm.prank(_user);
    //     strategy.deposit(_amount, _user);

    //     // Cast vote
    //     vm.prank(_user);
    //     strategy.vote(_project, _amount);
    // }

    // function checkVoteTotals(
    //     address _project,
    //     uint256 _expectedVotes,
    //     uint256 _expectedTotalVotes
    // ) public {
    //     assertEq(strategy.getProjectVotes(_project), _expectedVotes, "!projectVotes");
    //     assertEq(strategy.getTotalVotes(), _expectedTotalVotes, "!totalVotes");
    // }

    // function checkUserVotes(
    //     address _user,
    //     address _project,
    //     uint256 _expectedVotes
    // ) public {
    //     assertEq(strategy.getUserVotes(_user, _project), _expectedVotes, "!userVotes");
    // }
}
