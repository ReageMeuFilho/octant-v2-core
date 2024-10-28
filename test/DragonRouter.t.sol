// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {DragonRouter} from "src/dragons/DragonRouter.sol";
import {SplitChecker} from "src/dragons/SplitChecker.sol";
import {ITokenizedStrategy} from "src/interfaces/ITokenizedStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DragonRouterTest is Test {
    DragonRouter public router;
    SplitChecker public splitChecker;
    address public owner;
    address public governance;
    address public opexVault;
    address public metapool;
    address[] public strategies;
    address[] public assets;

    function setUp() public {
        owner = makeAddr("owner");
        governance = makeAddr("governance"); 
        opexVault = makeAddr("opexVault");
        metapool = makeAddr("metapool");

        // Deploy SplitChecker
        splitChecker = new SplitChecker();
        splitChecker.initialize(governance, 0.5e18, 0.05e18); // 50% max opex, 5% min metapool

        // Setup mock strategies and assets
        for(uint i = 0; i < 3; i++) {
            strategies.push(makeAddr(string.concat("strategy", vm.toString(i))));
            assets.push(makeAddr(string.concat("asset", vm.toString(i))));
        }

        // Deploy DragonRouter
        router = new DragonRouter();
        bytes memory initParams = abi.encode(
            owner,
            abi.encode(
                strategies,
                assets,
                governance,
                address(splitChecker),
                opexVault,
                metapool
            )
        );
        router.setUp(initParams);
    }

    function _setupStrategies(uint256 numStrategies) internal returns (address[] memory _strategies, address[] memory _assets) {
        // Initialize arrays
        _strategies = new address[](numStrategies);
        _assets = new address[](numStrategies);

        // Deploy mock strategies and assets
        for(uint256 i = 0; i < numStrategies; i++) {
            // Create mock asset
            _assets[i] = makeAddr(string.concat("asset", vm.toString(i)));
            
            // Deploy mock strategy
            MockStrategy strategy = new MockStrategy();
            strategy.initialize(
                _assets[i],
                string.concat("Strategy ", vm.toString(i)),
                owner,
                owner, // management
                owner, // keeper
                address(router)
            );
            _strategies[i] = address(strategy);
        }

        // Deploy new router with mock strategies
        router = new DragonRouter();
        bytes memory initParams = abi.encode(
            owner,
            abi.encode(
                _strategies,
                _assets,
                governance,
                address(splitChecker),
                opexVault,
                metapool
            )
        );
        router.setUp(initParams);

        // Update state variables
        strategies = _strategies;
        assets = _assets;

        // Setup initial split configuration
        address[] memory recipients = new address[](2);
        recipients[0] = opexVault;
        recipients[1] = metapool;
        
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 40; // 40% to opex
        allocations[1] = 60; // 60% to metapool
        
        vm.startPrank(governance);
        router.setSplit(DragonRouter.Split({
            recipients: recipients,
            allocations: allocations,
            totalAllocations: 100
        }));
        vm.stopPrank();
    }
}
