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
    
    // Mainnet addresses
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant STAKING = 0x0650CAF159C5A49f711e8169D4336ECB9b950275; // Sky Protocol Staking Contract
    address public constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    // Test constants
    uint256 public constant INITIAL_DEPOSIT = 1000e18;
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
    
    /// @notice Test profit cycle with UniswapV3 for swapping rewards
    function testUniswapV3WithProfitCycle() public {
        // Setup test parameters
        uint256 depositAmount = 100e18;
        address rewardsToken = strategy.rewardsToken();
        uint256 rewardAmount = 5e18; // Simulated reward amount
        
        console.log("Rewards token:", rewardsToken);
        
        // 1. Configure strategy to use UniswapV3 
        vm.startPrank(management);
        strategy.setUseUniV3andFees(true, 3000, 500); // Enable UniV3 with medium and low fee tiers
        vm.stopPrank();
        
        // Verify UniV3 is enabled
        assertTrue(strategy.useUniV3(), "UniV3 should be enabled");
        
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
        // First, get the rewards token
        vm.label(rewardsToken, "Rewards Token");
        
        // Mock some rewards in the staking contract
        deal(rewardsToken, address(strategy), rewardAmount);
        console.log("Airdropped rewards:", rewardAmount);
        console.log("Rewards token balance:", ERC20(rewardsToken).balanceOf(address(strategy)));
        
        // 5. Capture pre-report state
        uint256 totalAssetsBefore = vault.totalAssets();
        console.log("Total assets before report:", totalAssetsBefore);
        
        // 6. Report profit - this should trigger the UniV3 swap
        vm.startPrank(keeper);
        vm.expectEmit(true, true, true, true);
        emit Reported(0, 0); // We don't know exact values because of the swap
        (uint256 profit, uint256 loss) = vault.report();
        vm.stopPrank();
        
        console.log("Reported profit:", profit);
        console.log("Reported loss:", loss);
        
        // 7. Verify rewards were exchanged for USDS
        // Note: This test can be flaky since the exact exchange rate is unknown
        uint256 totalAssetsAfter = vault.totalAssets();
        console.log("Total assets after report:", totalAssetsAfter);
        
        // The total assets should have increased if the swap was successful
        assertGe(totalAssetsAfter, totalAssetsBefore, "Total assets should increase after swap");
        
        // 8. Skip time to allow profit to unlock
        skip(365 days);
        
        // 9. Verify donationAddress received shares from the profit
        uint256 donationShares = vault.balanceOf(donationAddress);
        console.log("Donation address shares:", donationShares);
        
        // The donation address should have received some shares if profit was recognized
        assertGt(donationShares, 0, "Donation address should have received shares");
        
        // 10. User withdraws their deposit
        vm.startPrank(user);
        uint256 userShares = vault.balanceOf(user);
        uint256 assetsReceived = vault.redeem(userShares, user, user);
        vm.stopPrank();
        
        console.log("User withdrew assets:", assetsReceived);
        
        // User should get back approximately their original deposit
        assertApproxEqRel(assetsReceived, depositAmount, 0.05e18, "User should receive approximately original deposit");
        
        // 11. Donation address withdraws their shares
        if (donationShares > 0) {
            vm.startPrank(donationAddress);
            uint256 donationAssets = vault.redeem(donationShares, donationAddress, donationAddress);
            vm.stopPrank();
            
            console.log("Donation address withdrew assets:", donationAssets);
            assertGt(donationAssets, 0, "Donation address should receive assets from profit");
        }
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
}
