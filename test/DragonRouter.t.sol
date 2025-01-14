// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {DragonRouter} from "src/dragons/DragonRouter.sol";
import "src/dragons/SplitChecker.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITokenizedStrategy} from "src/interfaces/ITokenizedStrategy.sol";

contract DragonRouterTest is Test {
    DragonRouter public router;
    SplitChecker public splitChecker;
    address public owner;
    address public governance;
    address public regenGovernance;
    address public opexVault;
    address public metapool;
    address[] public strategies;
    address[] public assets;

    function setUp() public {
        owner = makeAddr("owner");
        governance = makeAddr("governance");
        regenGovernance = makeAddr("regenGovernance");
        opexVault = makeAddr("opexVault");
        metapool = makeAddr("metapool");

        // Deploy SplitChecker
        splitChecker = new SplitChecker();
        splitChecker.initialize(governance, 0.5e18, 0.05e18); // 50% max opex, 5% min metapool

        // Setup mock strategies and assets
        for (uint256 i = 0; i < 3; i++) {
            strategies.push(makeAddr(string.concat("strategy", vm.toString(i))));
            assets.push(makeAddr(string.concat("asset", vm.toString(i))));
        }

        // Deploy DragonRouter
        router = new DragonRouter();
        bytes memory initParams =
            abi.encode(owner, abi.encode(strategies, assets, governance, regenGovernance, address(splitChecker), opexVault, metapool));
        router.setUp(initParams);
    }

    function _setupStrategies(uint256 numStrategies)
        internal
        returns (address[] memory _strategies, address[] memory _assets)
    {
        // Initialize arrays
        _strategies = new address[](numStrategies);
        _assets = new address[](numStrategies);

        // Deploy mock strategies and assets
        for (uint256 i = 0; i < numStrategies; i++) {
            // Create mock asset
            _assets[i] = makeAddr(string.concat("asset", vm.toString(i)));

            // Deploy mock strategy
            MockStrategy strategy = new MockStrategy();

            _strategies[i] = address(strategy);
        }

        // Deploy new router with mock strategies
        router = new DragonRouter();
        bytes memory initParams =
            abi.encode(owner, abi.encode(_strategies, _assets, governance, address(splitChecker), opexVault, metapool));
        router.setUp(initParams);

        // Update state variables
        strategies = _strategies;
        assets = _assets;

        vm.startPrank(governance);
        _setSplits();
        vm.stopPrank();
    }

    function _setSplits() public {
        // Setup initial split configuration
        address[] memory recipients = new address[](2);
        recipients[0] = opexVault;
        recipients[1] = metapool;

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 40; // 40% to opex
        allocations[1] = 60; // 60% to metapool

        router.setSplit(Split({recipients: recipients, allocations: allocations, totalAllocations: 100}));
    }

    function test_setCooldownPeriod() public {
        uint256 newPeriod = 180 days;

        vm.prank(regenGovernance);
        router.setCooldownPeriod(newPeriod);

        // Test successful change
        assertEq(router.DRAGON_SPLIT_COOLDOWN_PERIOD(), newPeriod);
    }

    function test_setCooldownPeriod_reverts() public {
        uint256 newPeriod = 180 days;

        vm.startPrank(address(0));
        vm.expectRevert(); // FIXME
        router.setCooldownPeriod(newPeriod);

        vm.stopPrank();
    }
}
