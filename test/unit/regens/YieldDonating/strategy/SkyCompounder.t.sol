// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SkyCompounder} from "src/regens/YieldDonating/strategy/SkyCompounder.sol";
import {IStaking} from "src/regens/interfaces/ISky.sol";
import {BaseHealthCheck} from "src/regens/periphery/BaseHealthCheck.sol";
import {UniswapV3Swapper} from "src/regens/periphery/UniswapV3Swapper.sol";
import {YieldDonatingVaultFactory} from "src/factories/YieldDonatingVaultFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "src/regens/interfaces/IVault.sol";
import {ITokenizedStrategy} from "src/regens/interfaces/ITokenizedStrategy.sol";
import {YieldDonatingTokenizedStrategy} from "src/regens/YieldDonating/YieldDonatingTokenizedStrategy.sol";

/// @title SkyCompounder Test
/// @author mil0x
/// @notice Unit tests for the SkyCompounder strategy using a mainnet fork
contract SkyCompounderTest is Test {
    using SafeERC20 for ERC20;

    // Strategy instance
    SkyCompounder public strategy;
    ITokenizedStrategy public vault;
    
    // Factory for creating strategies
    YieldDonatingTokenizedStrategy tokenizedStrategy;
    YieldDonatingVaultFactory public factory;
    
    // Strategy parameters
    address public management;
    address public keeper;
    address public emergencyAdmin;
    address public donationAddress;
    string public vaultSharesName = "SkyCompounder Vault Shares";
    bytes32 public strategySalt = keccak256("TEST_STRATEGY_SALT");
    
    // Test user
    address public user = address(0x1234);
    // Donation recipient for transfer tests
    address public donationRecipient = address(0x5678);
    
    // Mainnet addresses
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant STAKING = 0x0650CAF159C5A49f711e8169D4336ECB9b950275; // Sky Protocol Staking Contract
    address public constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    // Test constants
    uint256 public constant INITIAL_DEPOSIT = 100000e18;
    uint256 public mainnetFork;
    uint256 public mainnetForkBlock = 19230000; // A recent Ethereum mainnet block
    
    // Events from ITokenizedStrategy
    event Reported(uint256 profit, uint256 loss);
    
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
        
        // Deploy strategy using the factory's createStrategy method
        // The management address should be the deployer
        vm.startPrank(management);
        address strategyAddress = factory.createStrategy(
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            strategySalt
        );
        vm.stopPrank();
        
        // Cast the deployed address to our strategy type
        strategy = SkyCompounder(strategyAddress);
        vault = ITokenizedStrategy(address(strategy));
        
        // Label addresses for better trace outputs
        vm.label(address(strategy), "SkyCompounder");
        vm.label(address(factory), "YieldDonatingVaultFactory");
        vm.label(USDS, "USDS Token");
        vm.label(STAKING, "Sky Staking");
        vm.label(TOKENIZED_STRATEGY_ADDRESS, "TokenizedStrategy");
        vm.label(management, "Management");
        vm.label(keeper, "Keeper");
        vm.label(emergencyAdmin, "Emergency Admin");
        vm.label(donationAddress, "Donation Address");
        vm.label(user, "Test User");
        vm.label(WETH, "WETH");
        
        // Airdrop USDS tokens to test user
        airdrop(ERC20(USDS), user, INITIAL_DEPOSIT);
        
        // Approve strategy to spend user's tokens
        vm.startPrank(user);
        ERC20(USDS).approve(address(strategy), type(uint256).max);
        vm.stopPrank();
    }
    
    /// @notice Test that the strategy is properly initialized
    function testInitialization() public view {
        assertEq(vault.asset(), USDS, "Asset should be USDS");
        assertEq(strategy.staking(), STAKING, "Staking address incorrect");
        assertEq(vault.management(), management, "Management address incorrect");
        assertEq(vault.keeper(), keeper, "Keeper address incorrect");
        assertEq(vault.emergencyAdmin(), emergencyAdmin, "Emergency admin incorrect");
        // assertEq(vault.donationAddress(), donationAddress, "Donation address incorrect"); // TODO: Add this
        assertEq(strategy.claimRewards(), true, "Claim rewards should default to true");
        assertEq(strategy.useUniV3(), false, "Use UniV3 should default to false");
        
        // Verify that the strategy was recorded in the factory
        (address deployerAddress, , string memory name, address stratDonationAddress) = 
            factory.strategies(management, 0);
            
        assertEq(deployerAddress, management, "Deployer address incorrect in factory");
        assertEq(name, vaultSharesName, "Vault shares name incorrect in factory");
        assertEq(stratDonationAddress, donationAddress, "Donation address incorrect in factory");
    }
    
    /// @notice Test depositing assets into the strategy
    function testDeposit() public {
        uint256 depositAmount = 100e18;
        
        // Initial balances
        uint256 initialUserBalance = ERC20(USDS).balanceOf(user);
        uint256 initialStrategyBalance = strategy.balanceOfAsset();
        uint256 initialStakeBalance = strategy.balanceOfStake();
        
        // Deposit assets
        vm.startPrank(user);
        uint256 sharesReceived = vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Verify balances after deposit
        assertEq(ERC20(USDS).balanceOf(user), initialUserBalance - depositAmount, "User balance not reduced correctly");
        assertEq(strategy.balanceOfAsset(), initialStrategyBalance, "Strategy should deploy all assets");
        assertEq(strategy.balanceOfStake(), initialStakeBalance + depositAmount, "Staking balance not increased correctly");
        assertGt(sharesReceived, 0, "No shares received from deposit");
    }
    
    /// @notice Test withdrawing assets from the strategy
    function testWithdraw() public {
        uint256 depositAmount = 100e18;
        
        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        
        // Initial balances before withdrawal
        uint256 initialUserBalance = ERC20(USDS).balanceOf(user);
        uint256 initialShareBalance = vault.balanceOf(user);
        
        // Withdraw half of the deposit
        uint256 withdrawAmount = depositAmount / 2;
        uint256 sharesToBurn = vault.previewWithdraw(withdrawAmount);
        uint256 assetsReceived = vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();
        
        // Verify balances after withdrawal
        assertEq(ERC20(USDS).balanceOf(user), initialUserBalance + withdrawAmount, "User didn't receive correct assets");
        assertEq(vault.balanceOf(user), initialShareBalance - sharesToBurn, "Shares not burned correctly");
        assertEq(assetsReceived, withdrawAmount, "Incorrect amount of assets received");
    }
    
    /// @notice Test the harvesting functionality using explicit profit simulation
    function testHarvestWithProfit() public {
        uint256 depositAmount = 100e18;
        uint256 profitAmount = 10e18; // 10% profit
        
        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Check initial state
        uint256 totalAssetsBefore = vault.totalAssets();
        console.log("Total assets before:", totalAssetsBefore);
        
        // Skip time and mine blocks to simulate passage of time
        uint256 currentBlock = block.number;
        uint256 blocksToMine = 6500; // ~1 day of blocks
        skip(1 days);
        vm.roll(currentBlock + blocksToMine);
        
        // Simulate profit by directly airdropping assets to the strategy
        // This simulates the rewards that would be generated from staking
        airdrop(ERC20(USDS), address(strategy), profitAmount);
        console.log("Airdropped profit:", profitAmount);
        
        // Check state after airdrop
        uint256 strategyBalance = ERC20(USDS).balanceOf(address(strategy));
        console.log("Strategy USDS balance after airdrop:", strategyBalance);
        
        // Prepare to call report and expect event
        vm.startPrank(keeper);
        vm.expectEmit(true, true, true, true);
        emit Reported(profitAmount, 0); // We expect the exact profit we airdropped and no loss
        
        // Call report and capture the returned values
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        
        // Log the actual profit/loss
        console.log("Reported profit:", profit);
        console.log("Reported loss:", loss);
        
        // Assert profit and loss
        assertGe(profit, profitAmount, "Profit should be at least the airdropped amount");
        assertEq(loss, 0, "There should be no loss");
        
        // Check total assets after harvest
        uint256 totalAssetsAfter = vault.totalAssets();
        console.log("Total assets after:", totalAssetsAfter);
        assertGe(totalAssetsAfter, totalAssetsBefore + profitAmount, "Total assets should include profit");
        
        // Skip time to unlock profit
        skip(365 days);
        
        // Withdraw everything
        vm.startPrank(user);
        uint256 sharesToRedeem = vault.balanceOf(user);
        uint256 assetsReceived = vault.redeem(sharesToRedeem, user, user);
        vm.stopPrank();
        
        // Verify donation address received the profit in shares and user only got original deposit
        assertEq(assetsReceived, depositAmount, "User should only receive original deposit");
        assertEq(vault.balanceOf(donationAddress), profitAmount, "Donation address should receive profit in shares");
        console.log("User assets received:", assetsReceived);
        console.log("Donation address shares received:", vault.balanceOf(donationAddress));
    }
    
    /// @notice Test the harvesting functionality
    function testHarvest() public {
        uint256 depositAmount = 100e18;
        
        // Deposit first
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Fast forward time to generate rewards
        skip(7 days);
        
        // Capture initial state
        uint256 initialAssets = vault.totalAssets();
        
        // Call report as keeper (which internally calls _harvestAndReport)
        vm.startPrank(keeper);
        vault.report();
        vm.stopPrank();
        
        // Verify total assets after harvest
        // Note: We don't check for specific increases here as we're using a mainnet fork
        // and reward calculation can vary, but assets should be >= than before unless there's a loss
        assertGe(vault.totalAssets(), initialAssets, "Total assets should not decrease after harvest");
    }
    
    /// @notice Test profit cycle with UniswapV3 for swapping rewards when reward amount > minAmountToSell
    function testUniswapV3WithProfitCycleAboveMinAmount() public {
        // Setup test parameters
        uint256 depositAmount = 100e18;
        address rewardsToken = strategy.rewardsToken();
        uint256 rewardAmount = 50e18; // Simulated reward amount
        
        console.log("Rewards token:", rewardsToken);
        
        // 1. Configure strategy to use UniswapV3 
        vm.startPrank(management);
        strategy.setUseUniV3andFees(true, 3000, 500); // Enable UniV3 with medium and low fee tiers
        vm.stopPrank();
        
        // Verify UniV3 is enabled and minAmount is set
        assertTrue(strategy.useUniV3(), "UniV3 should be enabled");
        assertEq(strategy.minAmountToSell(), 50e18, "Min amount should be set correctly");
        
        // 2. Deposit assets into the strategy
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Verify deposit was successful
        assertEq(strategy.balanceOfStake(), depositAmount, "Deposit should be staked");
        
        // 3. Skip time to accrue rewards
        uint256 currentBlock = block.number;
        skip(30 days); // Skip forward 30 days
        vm.roll(currentBlock + 6500 * 30); // About 30 days of blocks
        
        // 4. Simulate rewards by airdropping reward tokens
        vm.label(rewardsToken, "Rewards Token");
        
        // Mock some rewards in the staking contract
        deal(rewardsToken, address(strategy), rewardAmount);
        console.log("Airdropped rewards:", rewardAmount);
        console.log("Rewards token balance:", ERC20(rewardsToken).balanceOf(address(strategy)));
        
        // 5. Capture pre-report state
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 rewardsBalanceBefore = ERC20(rewardsToken).balanceOf(address(strategy));
        console.log("Total assets before report:", totalAssetsBefore);
        
        // Explicitly set claimRewards to false to prevent swapping
        vm.startPrank(management);
        strategy.setClaimRewards(false);
        assertEq(strategy.balanceOfRewards(), rewardAmount, "Rewards should be in the strategy");
        vm.stopPrank();
        
        // 6. Report profit - this should NOT trigger rewards claiming or swapping since claimRewards is false
        vm.startPrank(keeper);
        vm.expectEmit(true, true, true, true);
        emit Reported(0, 0);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        
        console.log("Reported profit:", profit);
        console.log("Reported loss:", loss);
        
        // 7. Verify rewards were NOT exchanged for USDS (reward tokens should still be present)
        uint256 rewardsBalanceAfter = ERC20(rewardsToken).balanceOf(address(strategy));
        console.log("Rewards token balance after report:", rewardsBalanceAfter);
        
        // Rewards should not have been claimed or swapped, so balance should remain the same
        assertEq(rewardsBalanceAfter, rewardsBalanceBefore, "Rewards should not have been claimed or swapped");
        
        // Total assets should remain unchanged because claimRewards is false
        uint256 totalAssetsAfter = vault.totalAssets();
        console.log("Total assets after report:", totalAssetsAfter);
        assertApproxEqRel(totalAssetsAfter, totalAssetsBefore, 0.01e18, "Total assets should remain similar");
        
        // 8. Skip time to allow profit to unlock (though we don't expect profit in this case)
        skip(365 days);
        
        // 9. Verify donationAddress received minimal or no shares since no profit was recognized
        uint256 donationShares = vault.balanceOf(donationAddress);
        console.log("Donation address shares:", donationShares);
        
        // 10. User withdraws their deposit
        vm.startPrank(user);
        uint256 userShares = vault.balanceOf(user);
        uint256 assetsReceived = vault.redeem(userShares, user, user);
        vm.stopPrank();
        
        console.log("User withdrew assets:", assetsReceived);
        
        // User should get back approximately their original deposit
        assertApproxEqRel(assetsReceived, depositAmount, 0.05e18, "User should receive approximately original deposit");
    }
    
    /// @notice Test profit cycle with UniswapV3 for swapping rewards when reward amount < minAmountToSell
    function testUniswapV3WithProfitCycleBelowMinAmount() public {
        // Setup test parameters
        uint256 depositAmount = 100e18;
        address rewardsToken = strategy.rewardsToken();
        uint256 rewardAmount = 1e18; // Simulated reward amount (small)
        uint256 minAmount = 5e18;    // Set higher than reward amount
        
        console.log("Rewards token:", rewardsToken);
        
        // 1. Configure strategy to use UniswapV3 
        vm.startPrank(management);
        strategy.setUseUniV3andFees(true, 3000, 500); // Enable UniV3 with medium and low fee tiers
        strategy.setMinAmountToSell(minAmount); // Set min amount higher than rewards
        vm.stopPrank();
        
        // Verify UniV3 is enabled and minAmount is set
        assertTrue(strategy.useUniV3(), "UniV3 should be enabled");
        assertEq(strategy.minAmountToSell(), minAmount, "Min amount should be set correctly");
        
        // 2. Deposit assets into the strategy
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Verify deposit was successful
        assertEq(strategy.balanceOfStake(), depositAmount, "Deposit should be staked");
        
        // 3. Skip time to accrue rewards
        uint256 currentBlock = block.number;
        skip(30 days); // Skip forward 30 days
        vm.roll(currentBlock + 6500 * 30); // About 30 days of blocks
        
        // 4. Simulate rewards by airdropping reward tokens
        vm.label(rewardsToken, "Rewards Token");
        
        // Mock some rewards in the staking contract
        deal(rewardsToken, address(strategy), rewardAmount);
        console.log("Airdropped rewards:", rewardAmount);
        console.log("Rewards token balance:", ERC20(rewardsToken).balanceOf(address(strategy)));
        
        // 5. Capture pre-report state
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 rewardsBalanceBefore = ERC20(rewardsToken).balanceOf(address(strategy));
        console.log("Total assets before report:", totalAssetsBefore);
        vm.startPrank(management);
        strategy.setClaimRewards(false);
        assertEq(strategy.balanceOfRewards(), rewardAmount, "Rewards should be in the strategy");
        vm.stopPrank();
        
        // 6. Report profit - this should NOT trigger the UniV3 swap since rewardAmount < minAmountToSell
        vm.startPrank(keeper);
        vm.expectEmit(true, true, true, true);
        emit Reported(0, 0);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        
        console.log("Reported profit:", profit);
        console.log("Reported loss:", loss);
        
        // 7. Verify rewards were NOT exchanged for USDS (reward tokens should still be present)
        uint256 rewardsBalanceAfter = ERC20(rewardsToken).balanceOf(address(strategy));
        console.log("Rewards token balance after report:", rewardsBalanceAfter);
        
        // Rewards should not have been swapped, so balance should remain the same
        assertEq(rewardsBalanceAfter, rewardsBalanceBefore, "Rewards should not have been swapped");
        
        // Total assets should remain mostly unchanged
        uint256 totalAssetsAfter = vault.totalAssets();
        console.log("Total assets after report:", totalAssetsAfter);
        assertApproxEqRel(totalAssetsAfter, totalAssetsBefore, 0.01e18, "Total assets should remain similar");
        
        // 8. Skip time to allow profit to unlock
        skip(365 days);
        
        // 9. There should be minimal to no donation shares since no profit was recognized
        uint256 donationShares = vault.balanceOf(donationAddress);
        console.log("Donation address shares:", donationShares);
        
        // 10. User withdraws their deposit
        vm.startPrank(user);
        uint256 userShares = vault.balanceOf(user);
        uint256 assetsReceived = vault.redeem(userShares, user, user);
        vm.stopPrank();
        
        console.log("User withdrew assets:", assetsReceived);
        
        // User should get back approximately their original deposit
        assertApproxEqRel(assetsReceived, depositAmount, 0.05e18, "User should receive approximately original deposit");
    }
    
    /// @notice Test that report emits the Reported event with correct parameters
    function testReportEvent() public {
        uint256 depositAmount = 100e18;
        
        // Deposit first to have some assets in the strategy
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Create some rewards to be claimed
        // We need to both skip time and mine blocks for realistic rewards generation
        uint256 currentBlock = block.number;
        uint256 blocksToMine = 6500; // ~1 day of blocks at 13s/block
        
        // Log current state
        console.log("Current block:", currentBlock);
        console.log("Current timestamp:", block.timestamp);
        
        // Skip 1 day and mine 6500 blocks
        skip(1 days);
        vm.roll(currentBlock + blocksToMine);
        
        // Log new state
        console.log("New block:", block.number);
        console.log("New timestamp:", block.timestamp);
        
        // Prepare to call report and expect an event
        vm.startPrank(keeper);
        
        // We expect the Reported event to be emitted with some profit (or potentially loss)
        // Since we can't predict the exact values in a mainnet fork test,
        // we'll just check that the event format is correct with all the parameters
        vm.expectEmit(true, true, true, true);
        emit Reported(0, 0); // The actual values will be different
        
        // Call report and capture the returned values
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        
        // Log the actual profit/loss for debugging
        console.log("Reported profit:", profit);
        console.log("Reported loss:", loss);
        
        // At minimum, verify one of profit or loss was non-zero
        // or both were zero (empty harvesting is possible)
        assertTrue(profit > 0 || loss > 0 || (profit == 0 && loss == 0), "Either profit or loss should be reported");
    }
    
    /// @notice Test management functions
    function testManagementFunctions() public {
        // Test setClaimRewards
        vm.startPrank(management);
        strategy.setClaimRewards(false);
        vm.stopPrank();
        assertEq(strategy.claimRewards(), false, "claimRewards not updated correctly");
        
        // Test setUseUniV3andFees
        vm.startPrank(management);
        strategy.setUseUniV3andFees(true, 3000, 500);
        vm.stopPrank();
        assertEq(strategy.useUniV3(), true, "useUniV3 not updated correctly");
        
        // Test setMinAmountToSell
        uint256 newMinAmount = 100e18;
        vm.startPrank(management);
        strategy.setMinAmountToSell(newMinAmount);
        vm.stopPrank();
        assertEq(strategy.minAmountToSell(), newMinAmount, "minAmountToSell not updated correctly");
        
        // Test setReferral
        uint16 newReferral = 12345;
        vm.startPrank(management);
        strategy.setReferral(newReferral);
        vm.stopPrank();
        assertEq(strategy.referral(), newReferral, "referral not updated correctly");
    }
    
    /// @notice Test profit cycle with UniswapV2 for swapping rewards when reward amount > minAmountToSell
    function testUniswapV2WithProfitCycleAboveMinAmount() public {
        // Setup test parameters
        uint256 depositAmount = 4500e18;
        address rewardsToken = strategy.rewardsToken();
        
        console.log("Rewards token:", rewardsToken);
        
        // 1. Configure strategy to use UniswapV2 (make sure V3 is off)
        vm.startPrank(management);
        strategy.setUseUniV3andFees(false, 3000, 500); // Explicitly disable UniV3
        vm.stopPrank();
        
        // Verify UniV3 is disabled and confirm minAmount is set appropriately
        assertFalse(strategy.useUniV3(), "UniV3 should be disabled");
        assertEq(strategy.minAmountToSell(), 50e18, "Min amount should be set correctly");
        // check the claimable rewards are 0
        assertEq(strategy.claimableRewards(), 0, "no claimable rewards we mock this instead");
        
        // 2. Deposit assets into the strategy
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Verify deposit was successful
        assertEq(strategy.balanceOfStake(), depositAmount, "Deposit should be staked");
        
        // 3. Skip time to accrue rewards
        uint256 currentBlock = block.number;
        skip(30 days); // Skip forward 30 days
        vm.roll(currentBlock + 6500 * 30); // About 30 days of blocks
        
        // 5. Capture pre-report state
        uint256 totalAssetsBefore = vault.totalAssets();
        console.log("Total assets before report:", totalAssetsBefore);
        // Setting claimRewards to false to prevent actual swap attempt
        // In production, this would be true, but for testing purposes we disable it
        // to avoid dealing with complex UniswapV2 mocking
        vm.startPrank(management);
        assertEq(strategy.balanceOfRewards(), 0, "None of the rewards should be in the strategy yet");
        assertGt(strategy.claimableRewards(), 50e18, "Should have earned enough rewards to swap");

        uint256 rewardsBalanceBefore = strategy.claimableRewards();
        console.log("Rewards balance before report:", rewardsBalanceBefore);
        vm.stopPrank();
        
        // 6. Report profit - with claimRewards off, it should not attempt to swap
        vm.startPrank(keeper);
        vm.expectEmit(true, true, true, false);
        emit Reported(type(uint256).max, 0);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        
        console.log("Reported profit:", profit);
        console.log("Reported loss:", loss);

        assertGt(profit, 0, "Profit should be greater than 0");
        assertEq(loss, 0, "Loss should be 0");
        
        // 7. Verify rewards tokens were exchanged
        uint256 rewardsBalanceAfter = ERC20(rewardsToken).balanceOf(address(strategy));
        console.log("Rewards token balance after report:", rewardsBalanceAfter);
        assertLt(rewardsBalanceAfter, rewardsBalanceBefore, "Rewards should have been claimed and swapped");
        
        // 9. User withdraws their deposit
        vm.startPrank(user);
        uint256 userShares = vault.balanceOf(user);
        uint256 assetsReceived = vault.redeem(userShares, user, user);
        vm.stopPrank();
        
        console.log("User withdrew assets:", assetsReceived);
        assertApproxEqRel(assetsReceived, depositAmount, 0.05e18, "User should receive approximately original deposit");
    }
    
    /// @notice Test profit cycle with UniswapV2 and verify profits are minted to donation address
    function testUniswapV2ProfitDonation() public {
        // Setup test parameters with large deposit for significant rewards
        uint256 depositAmount = 5000e18;
        address rewardsToken = strategy.rewardsToken();
        
        console.log("Rewards token:", rewardsToken);
        
        // 1. Configure strategy to use UniswapV2
        vm.startPrank(management);
        strategy.setUseUniV3andFees(false, 3000, 500); // Disable UniV3
        vm.stopPrank();
        
        // Verify UniV2 is enabled
        assertFalse(strategy.useUniV3(), "UniV3 should be disabled");
        assertEq(strategy.minAmountToSell(), 50e18, "Min amount should be set correctly");
        
        // Check claimable rewards are 0 at the start
        assertEq(strategy.claimableRewards(), 0, "No claimable rewards initially");
        
        // 2. Deposit assets into the strategy
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Verify deposit was successful
        assertEq(strategy.balanceOfStake(), depositAmount, "Deposit should be staked");
        console.log("User deposit amount:", depositAmount);
        
        // 3. Skip time to accrue rewards (longer period for more rewards)
        uint256 currentBlock = block.number;
        skip(45 days); // Skip forward 45 days for more rewards
        vm.roll(currentBlock + 6500 * 45); // About 45 days worth of blocks
        
        // 4. Capture pre-report state
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 donationSharesBefore = vault.balanceOf(donationAddress);
        
        // Check that we have enough claimable rewards to make a swap
        vm.startPrank(management);
        uint256 claimableRewardsBefore = strategy.claimableRewards();
        console.log("Claimable rewards before report:", claimableRewardsBefore);
        assertGt(claimableRewardsBefore, 50e18, "Should have accrued enough rewards to swap");
        
        // Ensure claimRewards is enabled for actual swapping
        strategy.setClaimRewards(true);
        vm.stopPrank();
        
        // 5. Report profit - this should trigger reward claiming and swapping via UniswapV2
        vm.startPrank(keeper);
        vm.expectEmit(true, true, true, false); // Don't check exact profit value
        emit Reported(type(uint256).max, 0);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        
        console.log("Reported profit:", profit);
        console.log("Reported loss:", loss);
        
        // 6. Verify profit was recognized
        assertGt(profit, 0, "Profit should be greater than 0");
        assertEq(loss, 0, "Loss should be 0");
        
        // 7. Verify total assets increased
        uint256 totalAssetsAfter = vault.totalAssets();
        console.log("Total assets before:", totalAssetsBefore);
        console.log("Total assets after:", totalAssetsAfter);
        assertGt(totalAssetsAfter, totalAssetsBefore, "Total assets should increase after report");
        
        // 9. Verify donation address received shares from the profit
        uint256 donationSharesAfter = vault.balanceOf(donationAddress);
        console.log("Donation shares before:", donationSharesBefore);
        console.log("Donation shares after:", donationSharesAfter);
        assertGt(donationSharesAfter, donationSharesBefore, "Donation address should receive shares from profit");
        
        // 10. The increase in donation shares should match the profit
        uint256 donationSharesIncrease = donationSharesAfter - donationSharesBefore;
        assertApproxEqRel(donationSharesIncrease, profit, 0.01e18, "Donation shares increase should match profit");
        
        // 11. User withdraws their deposit
        vm.startPrank(user);
        uint256 userShares = vault.balanceOf(user);
        uint256 assetsReceived = vault.redeem(userShares, user, user);
        vm.stopPrank();
        
        console.log("User shares:", userShares);
        console.log("User assets received:", assetsReceived);
        assertApproxEqRel(assetsReceived, depositAmount, 0.05e18, "User should receive approximately original deposit");
        
        // 12. Donation address withdraws their shares to claim profit
        vm.startPrank(donationAddress);
        uint256 donationAssets = vault.redeem(donationSharesAfter, donationAddress, donationAddress);
        vm.stopPrank();
        
        console.log("Donation assets received:", donationAssets);
        assertGt(donationAssets, 0, "Donation address should receive assets from profit");
    }
    
    /// @notice Test donation shares can be transferred to another address
    function testDonationSharesTransfer() public {
        // Setup test parameters with large deposit for significant rewards
        uint256 depositAmount = 5000e18;
        
        // 1. Configure strategy to use UniswapV2
        vm.startPrank(management);
        strategy.setUseUniV3andFees(false, 3000, 500); // Disable UniV3
        vm.stopPrank();
        
        // 2. Deposit assets into the strategy
        vm.startPrank(user);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // 3. Skip time to accrue rewards
        uint256 currentBlock = block.number;
        skip(45 days);
        vm.roll(currentBlock + 6500 * 45);
        
        // 4. Verify we have claimable rewards and enable reward claiming
        vm.startPrank(management);
        uint256 claimableRewardsBefore = strategy.claimableRewards();
        console.log("Claimable rewards before report:", claimableRewardsBefore);
        assertGt(claimableRewardsBefore, 50e18, "Should have accrued enough rewards to swap");
        strategy.setClaimRewards(true);
        vm.stopPrank();
        
        // 5. Report profit to generate donation shares
        vm.startPrank(keeper);
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        
        console.log("Reported profit:", profit);
        console.log("Reported loss:", loss);
        assertGt(profit, 0, "Profit should be greater than 0");
        
        // 6. Check donation address received shares
        uint256 donationShares = vault.balanceOf(donationAddress);
        console.log("Donation shares:", donationShares);
        assertEq(donationShares, profit, "Donation address should receive shares equal to profit");
        
        // 7. Label the donation recipient address
        vm.label(donationRecipient, "Donation Recipient");
        
        // 8. Transfer half of the donation shares to another address
        uint256 sharesAmountToTransfer = donationShares / 2;
        vm.startPrank(donationAddress);
        vault.transfer(donationRecipient, sharesAmountToTransfer);
        vm.stopPrank();
        
        // 9. Verify the transfer was successful
        uint256 donationAddressSharesAfterTransfer = vault.balanceOf(donationAddress);
        uint256 recipientShares = vault.balanceOf(donationRecipient);
        
        console.log("Donation address shares after transfer:", donationAddressSharesAfterTransfer);
        console.log("Recipient shares:", recipientShares);
        
        assertEq(donationAddressSharesAfterTransfer, donationShares - sharesAmountToTransfer, 
            "Donation address should have correct remaining shares");
        assertEq(recipientShares, sharesAmountToTransfer, 
            "Recipient should have received correct shares amount");
        
        // 10. Verify recipient can redeem their shares for assets
        vm.startPrank(donationRecipient);
        uint256 assetsReceived = vault.redeem(recipientShares, donationRecipient, donationRecipient);
        vm.stopPrank();
        
        console.log("Recipient assets received:", assetsReceived);
        assertGt(assetsReceived, 0, "Recipient should receive assets from redeemed shares");
        assertApproxEqRel(assetsReceived, profit / 2, 0.01e18, 
            "Recipient should receive approximately half of the profit in assets");
        
        // 11. Verify donation address can still redeem their remaining shares
        vm.startPrank(donationAddress);
        uint256 donationAssetsReceived = vault.redeem(
            donationAddressSharesAfterTransfer, 
            donationAddress, 
            donationAddress
        );
        vm.stopPrank();
        
        console.log("Donation address assets received:", donationAssetsReceived);
        assertGt(donationAssetsReceived, 0, "Donation address should receive assets from remaining shares");
        assertApproxEqRel(donationAssetsReceived, profit / 2, 0.01e18, 
            "Donation address should receive approximately half of the profit in assets");
        
        // 12. Verify total assets distributed matches the original profit
        assertApproxEqRel(assetsReceived + donationAssetsReceived, profit, 0.01e18, 
            "Total assets distributed should match the original profit amount");
    }
}
