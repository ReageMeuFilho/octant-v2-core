// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { LockedVault } from "../../../src/dragons/vaults/LockedVault.sol";
import { VaultFactory } from "../../../src/dragons/vaults/VaultFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "../../../src/interfaces/IVault.sol";
import { ILockedVault } from "../../../src/interfaces/ILockedVault.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockYieldStrategy } from "../../mocks/MockYieldStrategy.sol";
import { MockFactory } from "../../mocks/MockFactory.sol";

contract LockedVaultTest is Test {
    LockedVault vaultImplementation;
    LockedVault vault;
    MockERC20 public asset;
    MockYieldStrategy public strategy;
    MockFactory public factory;
    VaultFactory vaultFactory;

    address public gov = address(0x1);
    address public fish = address(0x2);
    address public feeRecipient = address(0x3);
    address constant ZERO_ADDRESS = address(0);

    uint256 public fishAmount = 10_000e18;
    uint256 public defaultProfitMaxUnlockTime = 7 days;
    uint256 public defaultRageQuitCooldown = 7 days;
    uint256 constant MAX_INT = type(uint256).max;

    function setUp() public {
        // Setup asset
        asset = new MockERC20();
        asset.mint(gov, 1_000_000e18);
        asset.mint(fish, fishAmount);

        // Deploy factory
        vm.prank(gov);
        factory = new MockFactory(0, feeRecipient);

        // Deploy vault
        vm.startPrank(address(factory));
        vaultImplementation = new LockedVault();
        vaultFactory = new VaultFactory("Locked Test Vault", address(vaultImplementation), gov);
        vault = LockedVault(
            vaultFactory.deployNewVault(address(asset), "Locked Test Vault", "vLTST", gov, defaultProfitMaxUnlockTime)
        );

        // Initialize with rage quit cooldown period
        vm.expectRevert(); // Should revert since initialize was already called during deployment
        vault.initialize(address(asset), "Locked Test Vault", "vLTST", gov, defaultProfitMaxUnlockTime);
        vm.stopPrank();

        vm.startPrank(gov);
        // Add roles to gov
        vault.addRole(gov, IVault.Roles.ADD_STRATEGY_MANAGER);
        vault.addRole(gov, IVault.Roles.DEBT_MANAGER);
        vault.addRole(gov, IVault.Roles.MAX_DEBT_MANAGER);
        vault.addRole(gov, IVault.Roles.DEPOSIT_LIMIT_MANAGER);

        // Set max deposit limit
        vault.setDepositLimit(MAX_INT, false);
        vm.stopPrank();
    }

    function userDeposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function testRageQuitCooldownPeriodSetting() public {
        // Should be able to set rage quit cooldown period within valid range
        vm.startPrank(gov);
        vault.setRageQuitCooldownPeriod(3 days);
        assertEq(vault.rageQuitCooldownPeriod(), 3 days, "Rage quit cooldown period should be updated");

        // Should revert when setting below minimum
        vm.expectRevert(ILockedVault.InvalidRageQuitCooldownPeriod.selector);
        vault.setRageQuitCooldownPeriod(12 hours);

        // Should revert when setting above maximum
        vm.expectRevert(ILockedVault.InvalidRageQuitCooldownPeriod.selector);
        vault.setRageQuitCooldownPeriod(366 days);
        vm.stopPrank();
    }

    function testInitiateRageQuit() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // Initiate rage quit
        vm.prank(fish);
        vault.initiateRageQuit();

        // Verify lockup info
        (uint256 lockupTime, uint256 unlockTime) = vault.voluntaryLockups(fish);
        assertEq(
            unlockTime,
            block.timestamp + vault.rageQuitCooldownPeriod(),
            "Unlock time should be set to current time plus cooldown"
        );
        assertEq(lockupTime, block.timestamp, "Lockup time should be current time");
    }

    function testCannotInitiateRageQuitWithoutShares() public {
        vm.prank(fish);
        vm.expectRevert(ILockedVault.NoSharesToRageQuit.selector);
        vault.initiateRageQuit();
    }

    function testCanInitiateRageQuitWhenAlreadyUnlocked() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // Initiate rage quit
        vm.prank(fish);
        vault.initiateRageQuit();

        // Fast forward past unlock time
        vm.warp(block.timestamp + vault.rageQuitCooldownPeriod() + 1);

        // Should be able to initiate again
        vm.prank(fish);
        vault.initiateRageQuit();

        // Verify lockup info
        (uint256 lockupTime, uint256 unlockTime) = vault.voluntaryLockups(fish);
        assertEq(unlockTime, block.timestamp + vault.rageQuitCooldownPeriod(), "Unlock time should be updated");
        assertEq(lockupTime, block.timestamp, "Lockup time should be current time");
    }

    function testCannotInitiateRageQuitWhenAlreadyUnlockedAndCooldownPeriodHasNotPassed() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // Initiate rage quit
        vm.prank(fish);
        vault.initiateRageQuit();

        // Fast forward past unlock time
        vm.warp(block.timestamp + vault.rageQuitCooldownPeriod() - 1);

        // Should revert when trying to initiate again
        vm.prank(fish);
        vm.expectRevert(ILockedVault.RageQuitAlreadyInitiated.selector);
        vault.initiateRageQuit();
    }

    function testWithdrawAndRedeemWhenLocked() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // Initiate rage quit
        vm.prank(fish);
        vault.initiateRageQuit();

        // Try to withdraw during lock period (should fail)
        vm.prank(fish);
        vm.expectRevert(ILockedVault.SharesStillLocked.selector);
        vault.withdraw(fishAmount, fish, fish, 0, new address[](0));

        // Try to redeem during lock period (should fail)
        vm.prank(fish);
        vm.expectRevert(ILockedVault.SharesStillLocked.selector);
        vault.redeem(fishAmount, fish, fish, 0, new address[](0));
    }

    function testWithdrawAfterUnlock() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // Initiate rage quit
        vm.prank(fish);
        vault.initiateRageQuit();

        // Fast forward past unlock time
        vm.warp(block.timestamp + vault.rageQuitCooldownPeriod() + 1);

        // Should be able to withdraw now
        vm.startPrank(fish);
        uint256 withdrawnAmount = vault.withdraw(fishAmount, fish, fish, 0, new address[](0));
        assertEq(withdrawnAmount, fishAmount, "Should withdraw correct amount");

        // Verify balances
        assertEq(vault.balanceOf(fish), 0, "Fish should have no remaining shares");
        assertEq(asset.balanceOf(fish), fishAmount, "Fish should have received all assets back");
    }

    function testRedeemAfterUnlock() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // Initiate rage quit
        vm.prank(fish);
        vault.initiateRageQuit();

        // Fast forward past unlock time
        vm.warp(block.timestamp + vault.rageQuitCooldownPeriod() + 1);

        // redeem
        uint256 shares = vault.balanceOf(fish);

        // Should be able to withdraw now
        vm.startPrank(fish);
        uint256 redeemedAmount = vault.redeem(shares, fish, fish, 0, new address[](0));
        assertEq(redeemedAmount, fishAmount, "Should redeem correct amount");

        // Verify balances
        assertEq(vault.balanceOf(fish), 0, "Fish should have no remaining shares");
        assertEq(asset.balanceOf(fish), fishAmount, "Fish should have received all assets back");
    }

    function testNormalWithdrawWithoutLockupShouldRevert() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // Should be able to withdraw immediately (no lockup initiated)
        vm.expectRevert(ILockedVault.SharesStillLocked.selector);
        vm.prank(fish);
        vault.withdraw(fishAmount, fish, fish, 0, new address[](0));
    }

    function testReinitializeRageQuit() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // Initiate rage quit
        vm.prank(fish);
        vault.initiateRageQuit();

        (, uint256 originalUnlockTime) = vault.voluntaryLockups(fish);

        // Change cooldown period
        vm.prank(gov);
        vault.setRageQuitCooldownPeriod(14 days);

        // Fast forward halfway through cooldown
        vm.warp(block.timestamp + 4 days);

        // Mint more tokens for second deposit
        asset.mint(fish, fishAmount);

        // Redeposit some funds
        userDeposit(fish, fishAmount);

        // Original unlock time should not change despite re-deposit
        (, uint256 currentUnlockTime) = vault.voluntaryLockups(fish);
        assertEq(currentUnlockTime, originalUnlockTime, "Unlock time should not change on re-deposit");
    }

    function testCannotWithdrawAgainAfterFirstWithdrawalWithoutNewRageQuit() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // Initiate rage quit
        vm.prank(fish);
        vault.initiateRageQuit();

        // Fast forward past unlock time
        vm.warp(block.timestamp + vault.rageQuitCooldownPeriod() + 1);

        // First withdrawal should succeed
        vm.startPrank(fish);
        uint256 withdrawnAmount = vault.withdraw(fishAmount / 2, fish, fish, 0, new address[](0));
        assertEq(withdrawnAmount, fishAmount / 2, "Should withdraw correct amount");

        // Try to withdraw again without initiating new rage quit (should fail)
        vm.expectRevert(ILockedVault.SharesStillLocked.selector);
        vault.withdraw(fishAmount / 2, fish, fish, 0, new address[](0));
        vm.stopPrank();
    }

    function testCanWithdrawAgainAfterNewRageQuit() public {
        // Deposit first
        userDeposit(fish, fishAmount);

        // First rage quit
        vm.prank(fish);
        vault.initiateRageQuit();

        // Fast forward past unlock time
        vm.warp(block.timestamp + vault.rageQuitCooldownPeriod() + 1);

        // First withdrawal
        vm.startPrank(fish);
        uint256 withdrawnAmount = vault.withdraw(fishAmount / 2, fish, fish, 0, new address[](0));
        assertEq(withdrawnAmount, fishAmount / 2, "Should withdraw correct amount");

        // Initiate new rage quit
        vault.initiateRageQuit();

        // Fast forward past new unlock time
        vm.warp(block.timestamp + vault.rageQuitCooldownPeriod() + 1);

        // Should be able to withdraw again after new rage quit
        withdrawnAmount = vault.withdraw(fishAmount / 2, fish, fish, 0, new address[](0));
        assertEq(withdrawnAmount, fishAmount / 2, "Should withdraw correct amount");
        vm.stopPrank();
    }
}
