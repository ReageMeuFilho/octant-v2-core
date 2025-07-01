// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { RocketPoolStrategy } from "src/strategies/yieldSkimming/RocketPoolStrategy.sol";
import { RocketPoolStrategyFactory } from "src/factories/yieldSkimming/RocketPoolStrategyFactory.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

/// @title RocketPoolFactory Test
/// @author Octant
/// @notice Integration tests for the RocketPoolVaultFactory using a mainnet fork
contract RocketPoolStrategyFactoryTest is Test {
    using SafeERC20 for ERC20;

    // Factory for creating strategies
    YieldSkimmingTokenizedStrategy public tokenizedStrategy;
    RocketPoolStrategyFactory public factory;

    // Strategy parameters
    address public management;
    address public keeper;
    address public emergencyAdmin;
    address public donationAddress;

    // Mainnet addresses
    address public constant R_ETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    // Test constants
    uint256 public mainnetFork;
    uint256 public mainnetForkBlock = 22508883 - 6500 * 90; // latest alchemy block - 90 days
    YieldSkimmingTokenizedStrategy public implementation;

    // Fuzzing bounds
    uint256 constant MIN_NAME_LENGTH = 1;
    uint256 constant MAX_NAME_LENGTH = 50;
    uint256 constant MAX_USERS = 10;

    function setUp() public {
        // Create a mainnet fork
        mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);

        // Etch YieldSkimmingTokenizedStrategy
        implementation = new YieldSkimmingTokenizedStrategy{ salt: keccak256("OCT_YIELD_SKIMMING_STRATEGY_V1") }();

        // Now use that address as our tokenizedStrategy
        tokenizedStrategy = YieldSkimmingTokenizedStrategy(address(implementation));

        // Set up addresses
        management = address(0x1);
        keeper = address(0x2);
        emergencyAdmin = address(0x3);
        donationAddress = address(0x4);

        // Deploy factory
        factory = new RocketPoolStrategyFactory();

        // Label addresses for better trace outputs
        vm.label(address(factory), "RocketPoolVaultFactory");
        vm.label(R_ETH, "rETH");
        vm.label(address(implementation), "TokenizedStrategy");
        vm.label(management, "Management");
        vm.label(keeper, "Keeper");
        vm.label(emergencyAdmin, "Emergency Admin");
        vm.label(donationAddress, "Donation Address");
    }

    /// @notice Fuzz test for creating a strategy through the factory
    function testFuzzCreateStrategy(string memory vaultSharesName, uint256 saltSeed) public {
        // Bound the inputs
        vm.assume(bytes(vaultSharesName).length >= MIN_NAME_LENGTH && bytes(vaultSharesName).length <= MAX_NAME_LENGTH);
        bytes32 strategySalt = keccak256(abi.encodePacked("FUZZ_SALT", saltSeed));

        // Calculate expected address using Create2
        bytes memory bytecode = abi.encodePacked(
            type(RocketPoolStrategy).creationCode,
            abi.encode(
                R_ETH,
                vaultSharesName,
                management,
                keeper,
                emergencyAdmin,
                donationAddress,
                false, // enableBurning
                address(implementation)
            )
        );
        address expectedStrategyAddress = Create2.computeAddress(strategySalt, keccak256(bytecode), address(factory));

        // Create a strategy and check events
        vm.startPrank(management);
        vm.expectEmit(true, true, true, false); // Check first 3 indexed params, ignore the non-indexed timestamp
        emit RocketPoolStrategyFactory.StrategyDeploy(
            management,
            donationAddress,
            expectedStrategyAddress,
            vaultSharesName
        );

        address strategyAddress = factory.createStrategy(
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            strategySalt,
            address(implementation)
        );
        vm.stopPrank();

        // Verify strategy is tracked in factory
        (address deployerAddress, uint256 timestamp, string memory name, address stratDonationAddress) = factory
            .strategies(management, 0);

        assertEq(deployerAddress, management, "Deployer address incorrect in factory");
        assertEq(name, vaultSharesName, "Vault shares name incorrect in factory");
        assertEq(stratDonationAddress, donationAddress, "Donation address incorrect in factory");
        assertTrue(timestamp > 0, "Timestamp should be set");

        // Verify strategy was initialized correctly
        RocketPoolStrategy strategy = RocketPoolStrategy(strategyAddress);
        assertEq(IERC4626(address(strategy)).asset(), R_ETH, "Yield vault address incorrect");
    }

    /// @notice Fuzz test for creating multiple strategies for the same user
    function testFuzzMultipleStrategiesPerUser(
        string memory firstVaultName,
        string memory secondVaultName,
        uint256 saltSeed1,
        uint256 saltSeed2
    ) public {
        // Bound the inputs
        vm.assume(bytes(firstVaultName).length >= MIN_NAME_LENGTH && bytes(firstVaultName).length <= MAX_NAME_LENGTH);
        vm.assume(bytes(secondVaultName).length >= MIN_NAME_LENGTH && bytes(secondVaultName).length <= MAX_NAME_LENGTH);
        vm.assume(saltSeed1 != saltSeed2); // Ensure different salts

        bytes32 firstSalt = keccak256(abi.encodePacked("FIRST_FUZZ_SALT", saltSeed1));
        bytes32 secondSalt = keccak256(abi.encodePacked("SECOND_FUZZ_SALT", saltSeed2));

        vm.startPrank(management);
        address firstStrategyAddress = factory.createStrategy(
            firstVaultName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            firstSalt,
            address(implementation)
        );

        // Create second strategy for same user
        address secondStrategyAddress = factory.createStrategy(
            secondVaultName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            secondSalt,
            address(implementation)
        );
        vm.stopPrank();

        // Verify both strategies exist
        (address deployerAddress, , string memory name, ) = factory.strategies(management, 0);
        assertEq(deployerAddress, management, "First deployer address incorrect");
        assertEq(name, firstVaultName, "First vault name incorrect");

        (deployerAddress, , name, ) = factory.strategies(management, 1);
        assertEq(deployerAddress, management, "Second deployer address incorrect");
        assertEq(name, secondVaultName, "Second vault name incorrect");

        // Verify strategies are different
        assertTrue(firstStrategyAddress != secondStrategyAddress, "Strategies should have different addresses");
    }

    /// @notice Fuzz test for creating strategies for different users
    function testFuzzMultipleUsers(
        address[2] memory users,
        string[2] memory vaultNames,
        uint256[2] memory saltSeeds
    ) public {
        // Bound the inputs and validate
        for (uint i = 0; i < 2; i++) {
            vm.assume(users[i] != address(0));
            vm.assume(bytes(vaultNames[i]).length >= MIN_NAME_LENGTH && bytes(vaultNames[i]).length <= MAX_NAME_LENGTH);
        }
        vm.assume(users[0] != users[1]); // Different users
        vm.assume(saltSeeds[0] != saltSeeds[1]); // Different salts

        address[] memory strategyAddresses = new address[](2);

        // Create strategies for each user
        for (uint i = 0; i < 2; i++) {
            bytes32 salt = keccak256(abi.encodePacked("USER_SALT", i, saltSeeds[i]));

            vm.startPrank(users[i]);
            strategyAddresses[i] = factory.createStrategy(
                vaultNames[i],
                users[i],
                keeper,
                emergencyAdmin,
                donationAddress,
                false, // enableBurning
                salt,
                address(implementation)
            );
            vm.stopPrank();
        }

        // Verify strategies are properly tracked for each user
        for (uint i = 0; i < 2; i++) {
            (address deployerAddress, , string memory name, ) = factory.strategies(users[i], 0);
            assertEq(deployerAddress, users[i], string(abi.encodePacked("User ", i, "'s deployer address incorrect")));
            assertEq(name, vaultNames[i], string(abi.encodePacked("User ", i, "'s vault name incorrect")));
        }

        // Verify strategies are different
        assertTrue(strategyAddresses[0] != strategyAddresses[1], "Strategies should have different addresses");
    }

    /// @notice Fuzz test for deterministic addressing via salt
    function testFuzzDeterministicAddressing(
        string memory vaultSharesName,
        bytes32 strategySalt,
        uint8 factoryIndex
    ) public {
        // Bound the inputs
        vm.assume(bytes(vaultSharesName).length >= MIN_NAME_LENGTH && bytes(vaultSharesName).length <= MAX_NAME_LENGTH);
        vm.assume(factoryIndex < 3); // Test with up to 3 different factories

        address[] memory factories = new address[](3);
        address[] memory strategyAddresses = new address[](3);

        // Deploy multiple factories
        for (uint i = 0; i < 3; i++) {
            factories[i] = address(new RocketPoolStrategyFactory());
        }

        // Create strategies with same salt from different factories
        for (uint i = 0; i <= factoryIndex; i++) {
            vm.startPrank(management);
            strategyAddresses[i] = RocketPoolStrategyFactory(factories[i]).createStrategy(
                vaultSharesName,
                management,
                keeper,
                emergencyAdmin,
                donationAddress,
                false, // enableBurning
                strategySalt,
                address(implementation)
            );
            vm.stopPrank();
        }

        // Verify addresses are different when deployed from different factories
        for (uint i = 0; i < factoryIndex; i++) {
            assertTrue(
                strategyAddresses[i] != strategyAddresses[i + 1],
                "Addresses should be different with different factories"
            );
        }

        // Now test with different salt on the first factory
        bytes32 differentSalt = keccak256(abi.encodePacked(strategySalt, "DIFFERENT"));

        vm.startPrank(management);
        address differentSaltAddress = RocketPoolStrategyFactory(factories[0]).createStrategy(
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            differentSalt,
            address(implementation)
        );
        vm.stopPrank();

        assertTrue(strategyAddresses[0] != differentSaltAddress, "Addresses should be different with different salts");
    }

    /// @notice Fuzz test for strategy deployment with various parameter combinations
    function testFuzzStrategyDeploymentParameters(
        address fuzzManagement,
        address fuzzKeeper,
        address fuzzEmergencyAdmin,
        address fuzzDonationAddress,
        string memory vaultName
    ) public {
        // Bound and validate inputs
        vm.assume(fuzzManagement != address(0));
        vm.assume(fuzzKeeper != address(0));
        vm.assume(fuzzEmergencyAdmin != address(0));
        vm.assume(fuzzDonationAddress != address(0));
        vm.assume(bytes(vaultName).length >= MIN_NAME_LENGTH && bytes(vaultName).length <= MAX_NAME_LENGTH);

        // Ensure addresses are different (optional, depending on requirements)
        vm.assume(fuzzManagement != fuzzKeeper);
        vm.assume(fuzzManagement != fuzzEmergencyAdmin);
        vm.assume(fuzzManagement != fuzzDonationAddress);

        bytes32 salt = keccak256(abi.encodePacked("PARAM_TEST", fuzzManagement, block.timestamp));

        // Deploy strategy with fuzzed parameters
        vm.startPrank(fuzzManagement);
        factory.createStrategy(
            vaultName,
            fuzzManagement,
            fuzzKeeper,
            fuzzEmergencyAdmin,
            fuzzDonationAddress,
            false, // enableBurning
            salt,
            address(implementation)
        );
        vm.stopPrank();

        // Verify stored information in factory
        (address deployerAddress, uint256 timestamp, string memory name, address stratDonationAddress) = factory
            .strategies(fuzzManagement, 0);

        assertEq(deployerAddress, fuzzManagement, "Deployer address mismatch");
        assertEq(name, vaultName, "Vault name mismatch");
        assertEq(stratDonationAddress, fuzzDonationAddress, "Donation address mismatch");
        assertTrue(timestamp > 0 && timestamp <= block.timestamp, "Invalid timestamp");
    }

    /// @notice Fuzz test for creating many strategies and checking array bounds
    function testFuzzManyStrategiesPerUser(uint8 numStrategies) public {
        // Bound to a reasonable number
        numStrategies = uint8(bound(numStrategies, 1, 20));

        address testUser = address(0x1234);

        // Create multiple strategies
        for (uint i = 0; i < numStrategies; i++) {
            string memory vaultName = string(abi.encodePacked("Vault_", i));
            bytes32 salt = keccak256(abi.encodePacked("MANY_STRATEGIES", i, block.timestamp));

            vm.startPrank(testUser);
            factory.createStrategy(
                vaultName,
                testUser,
                keeper,
                emergencyAdmin,
                donationAddress,
                false, // enableBurning
                salt,
                address(implementation)
            );
            vm.stopPrank();
        }

        // Verify all strategies are tracked correctly
        for (uint i = 0; i < numStrategies; i++) {
            (address deployerAddress, , string memory name, ) = factory.strategies(testUser, i);
            assertEq(deployerAddress, testUser, "Deployer address incorrect");
            assertEq(name, string(abi.encodePacked("Vault_", i)), "Vault name incorrect");
        }
    }
}
