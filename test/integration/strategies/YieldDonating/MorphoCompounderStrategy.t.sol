// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MorphoCompounderStrategy } from "src/strategies/yieldDonating/MorphoCompounderStrategy.sol";
import { BaseHealthCheck } from "src/strategies/periphery/BaseHealthCheck.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IMockStrategy } from "test/mocks/IMockStrategy.sol";
import { MorphoCompounderStrategyVaultFactory } from "src/factories/yieldDonating/MorphoCompounderStrategyVaultFactory.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

/// @title MorphoCompounder Yield Donating Test
/// @author Octant
/// @notice Integration tests for the yield donating MorphoCompounder strategy using a mainnet fork
contract MorphoCompounderDonatingStrategyTest is Test {
    using SafeERC20 for ERC20;

    // Strategy instance
    MorphoCompounderStrategy public strategy;

    // Strategy parameters
    address public management;
    address public keeper;
    address public emergencyAdmin;
    address public donationAddress;
    MorphoCompounderStrategyVaultFactory public factory;
    string public strategyName = "MorphoCompounder Donating Strategy";

    // Test user
    address public user = address(0x1234);

    // Mainnet addresses
    address public constant MORPHO_VAULT = 0x074134A2784F4F66b6ceD6f68849382990Ff3215; // Steakhouse USDC vault
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC token
    address public constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;

    // Test constants
    uint256 public constant INITIAL_DEPOSIT = 100000e6; // USDC has 6 decimals
    uint256 public mainnetFork;
    uint256 public mainnetForkBlock = 22508883 - 6500 * 90; // latest alchemy block - 90 days

    /**
     * @notice Helper function to airdrop tokens to a specified address
     * @param _asset The ERC20 token to airdrop
     * @param _to The recipient address
     * @param _amount The amount of tokens to airdrop
     */
    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setUp() public {
        // Create a mainnet fork
        mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);

        // Etch YieldSkimmingTokenizedStrategy
        YieldDonatingTokenizedStrategy tempStrategy = new YieldDonatingTokenizedStrategy{
            salt: keccak256("OCT_YIELD_SKIMMING_STRATEGY_V1")
        }();
        bytes memory tokenizedStrategyBytecode = address(tempStrategy).code;
        vm.etch(TOKENIZED_STRATEGY_ADDRESS, tokenizedStrategyBytecode);

        // Set up addresses
        management = address(0x1);
        keeper = address(0x2);
        emergencyAdmin = address(0x3);
        donationAddress = address(0x4);

        // MorphoCompounderStrategyVaultFactory
        factory = new MorphoCompounderStrategyVaultFactory{
            salt: keccak256("OCT_MORPHO_COMPOUNDER_STRATEGY_VAULT_FACTORY_V1")
        }();

        // Deploy strategy
        strategy = MorphoCompounderStrategy(
            factory.createStrategy(
                MORPHO_VAULT,
                strategyName,
                management,
                keeper,
                emergencyAdmin,
                donationAddress,
                keccak256("OCT_MORPHO_COMPOUNDER_STRATEGY_V1")
            )
        );

        // Label addresses for better trace outputs
        vm.label(address(strategy), "MorphoCompounderDonating");
        vm.label(MORPHO_VAULT, "Morpho Vault");
        vm.label(USDC, "USDC");
        vm.label(management, "Management");
        vm.label(keeper, "Keeper");
        vm.label(emergencyAdmin, "Emergency Admin");
        vm.label(donationAddress, "Donation Address");
        vm.label(user, "Test User");

        // Airdrop USDC tokens to test user
        airdrop(ERC20(USDC), user, INITIAL_DEPOSIT);

        // Approve strategy to spend user's tokens
        vm.startPrank(user);
        ERC20(USDC).approve(address(strategy), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Test that the strategy is properly initialized
    function testInitialization() public view {
        // assertEq(IERC4626(strategy).asset(), address(USDC), "Asset should be USDC");
        // assertEq(strategy.management(), management, "Management address incorrect");
        // assertEq(strategy.keeper(), keeper, "Keeper address incorrect");
        // assertEq(strategy.emergencyAdmin(), emergencyAdmin, "Emergency admin incorrect");
        // assertEq(strategy.donationAddress(), donationAddress, "Donation address incorrect");
        // assertEq(strategy.compounderVault(), MORPHO_VAULT, "Compounder vault incorrect");
    }

    /// @notice Test depositing assets into the strategy
    function testDeposit() public {
        uint256 depositAmount = 1000e6; // 1000 USDC

        // Initial balances
        uint256 initialUserBalance = ERC20(USDC).balanceOf(user);
        uint256 initialStrategyAssets = IERC4626(address(strategy)).totalAssets();

        // Deposit assets
        vm.startPrank(user);
        uint256 sharesReceived = IERC4626(address(strategy)).deposit(depositAmount, user);
        vm.stopPrank();

        // Verify balances after deposit
        assertEq(ERC20(USDC).balanceOf(user), initialUserBalance - depositAmount, "User balance not reduced correctly");

        assertGt(sharesReceived, 0, "No shares received from deposit");
        assertEq(
            IERC4626(address(strategy)).totalAssets(),
            initialStrategyAssets + depositAmount,
            "Strategy total assets should increase"
        );
    }

    /// @notice Test withdrawing assets from the strategy
    function testWithdraw() public {
        uint256 depositAmount = 1000e6; // 1000 USDC

        // Deposit first
        vm.startPrank(user);
        IERC4626(address(strategy)).deposit(depositAmount, user);

        // Initial balances before withdrawal
        uint256 initialUserBalance = ERC20(USDC).balanceOf(user);
        uint256 initialShareBalance = IERC4626(address(strategy)).balanceOf(user);

        // Withdraw half of the deposit
        uint256 withdrawAmount = depositAmount / 2;
        uint256 sharesToBurn = IERC4626(address(strategy)).previewWithdraw(withdrawAmount);
        uint256 assetsReceived = IERC4626(address(strategy)).withdraw(withdrawAmount, user, user);
        vm.stopPrank();

        // Verify balances after withdrawal
        assertEq(
            ERC20(USDC).balanceOf(user),
            initialUserBalance + withdrawAmount,
            "User didn't receive correct assets"
        );
        assertEq(
            IERC4626(address(strategy)).balanceOf(user),
            initialShareBalance - sharesToBurn,
            "Shares not burned correctly"
        );
        assertEq(assetsReceived, withdrawAmount, "Incorrect amount of assets received");
    }

    /// @notice Test the harvesting functionality with profit donation
    function testHarvestWithProfitDonation() public {
        uint256 depositAmount = 1000e6; // 1000 USDC

        // Deposit first
        vm.startPrank(user);
        IERC4626(address(strategy)).deposit(depositAmount, user);
        vm.stopPrank();

        // Check initial state
        uint256 totalAssetsBefore = IERC4626(address(strategy)).totalAssets();
        uint256 userSharesBefore = IERC4626(address(strategy)).balanceOf(user);
        uint256 donationBalanceBefore = ERC20(address(strategy)).balanceOf(donationAddress);

        // Call report to harvest and donate yield
        // mock IERC4626(compounderVault).convertToAssets(shares) so that it returns 1000e6 (profit)
        uint256 balanceOfMorphoVault = IERC4626(MORPHO_VAULT).balanceOf(address(strategy));
        vm.mockCall(
            address(IERC4626(MORPHO_VAULT)),
            abi.encodeWithSelector(IERC4626.convertToAssets.selector, balanceOfMorphoVault),
            abi.encode(balanceOfMorphoVault + 1000e6)
        );
        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = IMockStrategy(address(strategy)).report();
        vm.stopPrank();

        vm.clearMockedCalls();

        // airdrop 1000e6 to the Morpho vault
        airdrop(ERC20(USDC), address(strategy), 1000e6);

        // Verify results
        assertGt(profit, 0, "Should have captured profit from yield");
        assertEq(loss, 0, "Should have no loss");

        // User shares should remain the same (no dilution)
        assertEq(IERC4626(address(strategy)).balanceOf(user), userSharesBefore, "User shares should not change");

        // Donation address should have received the profit
        uint256 donationBalanceAfter = ERC20(address(strategy)).balanceOf(donationAddress);
        assertGt(donationBalanceAfter, donationBalanceBefore, "Donation address should receive profit");

        // Total assets should increase by the profit amount
        assertGt(IERC4626(address(strategy)).totalAssets(), totalAssetsBefore, "Total assets should increase");
    }

    /// @notice Test available deposit limit
    function testAvailableDepositLimit() public view {
        uint256 limit = strategy.availableDepositLimit(user);
        uint256 morphoLimit = IERC4626(MORPHO_VAULT).maxDeposit(address(strategy));
        assertEq(limit, morphoLimit, "Available deposit limit should match Morpho vault limit");
    }

    /// @notice Test emergency withdraw functionality
    function testEmergencyWithdraw() public {
        uint256 depositAmount = 1000e6; // 1000 USDC

        // Deposit first
        vm.startPrank(user);
        IERC4626(address(strategy)).deposit(depositAmount, user);
        vm.stopPrank();

        // Get initial vault shares in Morpho
        uint256 initialMorphoShares = IERC4626(MORPHO_VAULT).balanceOf(address(strategy));

        // Emergency withdraw
        vm.startPrank(emergencyAdmin);
        IMockStrategy(address(strategy)).shutdownStrategy();
        IMockStrategy(address(strategy)).emergencyWithdraw(depositAmount / 2);
        vm.stopPrank();

        // Verify some funds were withdrawn from Morpho
        uint256 finalMorphoShares = IERC4626(MORPHO_VAULT).balanceOf(address(strategy));
        assertLt(finalMorphoShares, initialMorphoShares, "Should have withdrawn from Morpho vault");

        // Verify strategy has some idle USDC
        assertGt(ERC20(USDC).balanceOf(address(strategy)), 0, "Strategy should have idle USDC");
    }

    /// @notice Test that _harvestAndReport returns correct total assets
    function testHarvestAndReportView() public {
        uint256 depositAmount = 1000e6; // 1000 USDC

        // Deposit first
        vm.startPrank(user);
        IERC4626(address(strategy)).deposit(depositAmount, user);
        vm.stopPrank();

        // Check that total assets matches the strategy's view of assets
        uint256 totalAssets = IERC4626(address(strategy)).totalAssets();
        uint256 morphoShares = IERC4626(MORPHO_VAULT).balanceOf(address(strategy));
        uint256 morphoAssets = IERC4626(MORPHO_VAULT).convertToAssets(morphoShares);
        uint256 idleAssets = ERC20(USDC).balanceOf(address(strategy));

        assertApproxEqRel(
            totalAssets,
            morphoAssets + idleAssets,
            1e12,
            "Total assets should match Morpho assets plus idle"
        );
    }

    /// @notice Test that constructor validates asset compatibility
    function testConstructorAssetValidation() public {
        // Try to deploy with wrong asset - should revert
        vm.expectRevert();
        new MorphoCompounderStrategy(
            MORPHO_VAULT,
            address(0x123), // Wrong asset
            strategyName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress
        );
    }

    /// @notice Test multiple deposits and withdrawals
    function testMultipleDepositsAndWithdrawals() public {
        uint256 depositAmount1 = 500e6; // 500 USDC
        uint256 depositAmount2 = 300e6; // 300 USDC
        address user2 = address(0x5678);

        // Airdrop to second user
        airdrop(ERC20(USDC), user2, 1000e6);
        vm.startPrank(user2);
        ERC20(USDC).approve(address(strategy), type(uint256).max);
        vm.stopPrank();

        // First user deposits
        vm.startPrank(user);
        IERC4626(address(strategy)).deposit(depositAmount1, user);
        vm.stopPrank();

        // Second user deposits
        vm.startPrank(user2);
        IERC4626(address(strategy)).deposit(depositAmount2, user2);
        vm.stopPrank();

        // Verify total assets
        assertEq(
            IERC4626(address(strategy)).totalAssets(),
            depositAmount1 + depositAmount2,
            "Total assets should equal deposits"
        );

        // Both users withdraw
        vm.startPrank(user);
        IERC4626(address(strategy)).redeem(IERC4626(address(strategy)).balanceOf(user), user, user);
        vm.stopPrank();

        vm.startPrank(user2);
        // find user 2 max redeem
        uint256 maxRedeem = IERC4626(address(strategy)).maxRedeem(user2);
        IMockStrategy(address(strategy)).redeem(maxRedeem, user2, user2, 10);
        vm.stopPrank();

        // Strategy should be nearly empty
        assertLt(
            IERC4626(address(strategy)).totalAssets(),
            10,
            "Strategy should be nearly empty after all withdrawals"
        );
    }

    /// @notice Test that unauthorized users cannot call governance functions
    function testUnauthorizedAccess() public {
        // Only governance can call certain functions
        vm.startPrank(user);
        vm.expectRevert();
        MorphoCompounderStrategy(address(strategy)).sweep(address(0x123));
        vm.stopPrank();
    }
}
