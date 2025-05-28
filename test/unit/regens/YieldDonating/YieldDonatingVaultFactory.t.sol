// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SkyCompounder} from "src/regens/YieldDonating/strategy/SkyCompounder.sol";
import {IStaking} from "src/regens/interfaces/ISky.sol";
import {YieldDonatingVaultFactory} from "src/factories/YieldDonatingVaultFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {YieldDonatingTokenizedStrategy} from "src/regens/YieldDonating/YieldDonatingTokenizedStrategy.sol";

/// @title YieldDonatingVaultFactory Test
/// @author mil0x
/// @notice Unit tests for the YieldDonatingVaultFactory using a mainnet fork
contract YieldDonatingVaultFactoryTest is Test {
    using SafeERC20 for ERC20;

    // Factory for creating strategies
    YieldDonatingTokenizedStrategy tokenizedStrategy;
    YieldDonatingVaultFactory public factory;
    
    // Strategy parameters
    address public management;
    address public keeper;
    address public emergencyAdmin;
    address public donationAddress;
    
    // Mainnet addresses
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant STAKING = 0x0650CAF159C5A49f711e8169D4336ECB9b950275; // Sky Protocol Staking Contract
    address public constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;
    
    // Test constants
    uint256 public mainnetFork;
    uint256 public mainnetForkBlock = 19230000; // A recent Ethereum mainnet block
    
    function setUp() public {
        // Create a mainnet fork
        // NOTE: This relies on the RPC URL configured in foundry.toml under [rpc_endpoints] 
        // where mainnet = "${ETHEREUM_NODE_MAINNET}" environment variable
        mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);

        // Etch YieldDonatingTokenizedStrategy
        YieldDonatingTokenizedStrategy tempStrategy = new YieldDonatingTokenizedStrategy{ salt: keccak256("OCT_YIELD_DONATING_STRATEGY_V1") }();
        bytes memory tokenizedStrategyBytecode = address(tempStrategy).code;
        vm.etch(TOKENIZED_STRATEGY_ADDRESS, tokenizedStrategyBytecode);
        
        // Now use that address as our tokenizedStrategy
        tokenizedStrategy = YieldDonatingTokenizedStrategy(TOKENIZED_STRATEGY_ADDRESS);
        
        // Set up addresses
        management = address(0x1);
        keeper = address(0x2);
        emergencyAdmin = address(0x3);
        donationAddress = address(0x4);
        
        // Deploy factory
        factory = new YieldDonatingVaultFactory();
        
        // Label addresses for better trace outputs
        vm.label(address(factory), "YieldDonatingVaultFactory");
        vm.label(USDS, "USDS Token");
        vm.label(STAKING, "Sky Staking");
        vm.label(TOKENIZED_STRATEGY_ADDRESS, "TokenizedStrategy");
        vm.label(management, "Management");
        vm.label(keeper, "Keeper");
        vm.label(emergencyAdmin, "Emergency Admin");
        vm.label(donationAddress, "Donation Address");
    }
    
    /// @notice Test creating a strategy through the factory
    function testCreateStrategy() public {
        string memory vaultSharesName = "SkyCompounder Vault Shares";
        bytes32 strategySalt = keccak256("TEST_STRATEGY_SALT");
        
        // Create a strategy and check events
        vm.startPrank(management);
        vm.expectEmit(true, true, true, false); // Check first 3 indexed params, ignore the non-indexed timestamp
        emit StrategyDeploy(management, donationAddress, 0x68c8c8FdBc4A50a07cb407aa430d31566E1D2F31); // We can't predict the exact address
        
        address strategyAddress = factory.createStrategy(
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            strategySalt
        );
        vm.stopPrank();
        
        // Verify strategy is tracked in factory
        (address deployerAddress, uint256 timestamp, string memory name, address stratDonationAddress) = 
            factory.strategies(management, 0);
            
        assertEq(deployerAddress, management, "Deployer address incorrect in factory");
        assertEq(name, vaultSharesName, "Vault shares name incorrect in factory");
        assertEq(stratDonationAddress, donationAddress, "Donation address incorrect in factory");
        assertTrue(timestamp > 0, "Timestamp should be set");
        
        // Verify strategy was initialized correctly
        SkyCompounder strategy = SkyCompounder(strategyAddress);
        assertEq(strategy.staking(), STAKING, "Staking address incorrect");
        // assertEq(strategy.donationAddress(), donationAddress, "Donation address incorrect");
    }
    
    /// @notice Test creating multiple strategies for the same user
    function testMultipleStrategiesPerUser() public {
        // Create first strategy
        string memory firstVaultName = "First SkyCompounder Vault";
        bytes32 firstSalt = keccak256("FIRST_TEST_STRATEGY_SALT");
        
        vm.startPrank(management);
        address firstStrategyAddress = factory.createStrategy(
            firstVaultName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            firstSalt
        );
        
        // Create second strategy for same user
        string memory secondVaultName = "Second SkyCompounder Vault";
        bytes32 secondSalt = keccak256("SECOND_TEST_STRATEGY_SALT");
        
        address secondStrategyAddress = factory.createStrategy(
            secondVaultName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            secondSalt
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
    
    /// @notice Test creating strategies for different users
    function testMultipleUsers() public {
        string memory firstVaultName = "First User's Vault";
        bytes32 firstSalt = keccak256("FIRST_USER_SALT");
        
        address firstUser = address(0x5678);
        address secondUser = address(0x9876);
        
        // Create strategy for first user
        vm.startPrank(firstUser);
        address firstStrategyAddress = factory.createStrategy(
            firstVaultName,
            firstUser,
            keeper,
            emergencyAdmin,
            donationAddress,
            firstSalt
        );
        vm.stopPrank();
        
        // Create strategy for second user
        string memory secondVaultName = "Second User's Vault";
        bytes32 secondSalt = keccak256("SECOND_USER_SALT");
        
        vm.startPrank(secondUser);
        address secondStrategyAddress = factory.createStrategy(
            secondVaultName,
            secondUser,
            keeper,
            emergencyAdmin,
            donationAddress,
            secondSalt
        );
        vm.stopPrank();
        
        // Verify strategies are properly tracked for each user
        (address deployerAddress, , string memory name, ) = factory.strategies(firstUser, 0);
        assertEq(deployerAddress, firstUser, "First user's deployer address incorrect");
        assertEq(name, firstVaultName, "First user's vault name incorrect");
        
        (deployerAddress, , name, ) = factory.strategies(secondUser, 0);
        assertEq(deployerAddress, secondUser, "Second user's deployer address incorrect");
        assertEq(name, secondVaultName, "Second user's vault name incorrect");
        
        // Verify strategies are different
        assertTrue(firstStrategyAddress != secondStrategyAddress, "Strategies should have different addresses");
    }
    
    /// @notice Test creating a strategy with deterministic addressing via salt
    function testDeterministicAddressing() public {
        string memory vaultSharesName = "Deterministic Vault";
        bytes32 strategySalt = keccak256("DETERMINISTIC_SALT");
        
        // Create a strategy
        vm.startPrank(management);
        address firstAddress = factory.createStrategy(
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            strategySalt
        );
        vm.stopPrank();
        
        // Create a new factory
        YieldDonatingVaultFactory newFactory = new YieldDonatingVaultFactory();
        
        // Create a strategy with the same salt but from a different factory
        vm.startPrank(management);
        address secondAddress = newFactory.createStrategy(
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            strategySalt
        );
        vm.stopPrank();
        
        // Addresses should be different because factory addresses are different
        // but they should be deterministic based on the salt and other parameters
        assertTrue(firstAddress != secondAddress, "Addresses should be different with different factories");
        
        // Re-create with a different salt but same factory and parameters
        bytes32 differentSalt = keccak256("DIFFERENT_SALT");
        
        vm.startPrank(management);
        address thirdAddress = factory.createStrategy(
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            differentSalt
        );
        vm.stopPrank();
        
        assertTrue(firstAddress != thirdAddress, "Addresses should be different with different salts");
    }
}

// Event to match the factory's event signature
event StrategyDeploy(address deployer, address donationAddress, address strategyAddress); 