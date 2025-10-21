// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

/**
 * @title Octant Error Definitions
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Centralized custom errors for gas-efficient reverts across Octant contracts
 * @dev Using custom errors saves ~50 bytes per error vs require(condition, "string")
 */

// ============================================
// GENERAL ERRORS
// ============================================

/// @notice Thrown when caller lacks authorization for the operation
error Unauthorized();

/// @notice Thrown when a zero address is provided where not allowed
error ZeroAddress();

/// @notice Thrown when reentrancy is detected
error ReentrancyGuard__ReentrantCall();

/// @notice Thrown when attempting operation with zero shares
error ZeroShares();

/// @notice Thrown when attempting operation with zero assets
error ZeroAssets();

/// @notice Thrown when ERC20 balance is insufficient for operation
error ERC20InsufficientBalance();

/// @notice Thrown when attempting to initialize an already initialized contract
error AlreadyInitialized();

// ============================================
// ACCESS CONTROL ERRORS
// ============================================

/// @notice Thrown when user is not in required allowset
/// @param user Address that failed allowset check
error NotInAllowset(address user);

/// @notice Thrown when user is in forbidden blockset
/// @param user Address that failed blockset check
error InBlockset(address user);

// TokenizedStrategy specific errors
error TokenizedStrategy__NotEmergencyAuthorized();
error TokenizedStrategy__NotKeeperOrManagement();
error TokenizedStrategy__NotOperator();
error TokenizedStrategy__NotManagement();
error TokenizedStrategy__NotRegenGovernance();
error TokenizedStrategy__AlreadyInitialized();
error TokenizedStrategy__DepositMoreThanMax();
error TokenizedStrategy__MintMoreThanMax();
error TokenizedStrategy__InvalidMaxLoss();
error TokenizedStrategy__TransferFromZeroAddress();
error TokenizedStrategy__TransferToZeroAddress();
error TokenizedStrategy__TransferToStrategy();
error TokenizedStrategy__MintToZeroAddress();
error TokenizedStrategy__BurnFromZeroAddress();
error TokenizedStrategy__ApproveFromZeroAddress();
error TokenizedStrategy__ApproveToZeroAddress();
error TokenizedStrategy__InsufficientAllowance();
error TokenizedStrategy__PermitDeadlineExpired();
error TokenizedStrategy__InvalidSigner();
error TokenizedStrategy__TransferFailed();
error TokenizedStrategy__NotSelf();
error TokenizedStrategy__WithdrawMoreThanMax();
error TokenizedStrategy__RedeemMoreThanMax();
error TokenizedStrategy__NotPendingManagement();
error TokenizedStrategy__StrategyNotInShutdown();
error TokenizedStrategy__TooMuchLoss();
error TokenizedStrategy__HatsAlreadyInitialized();
error TokenizedStrategy__InvalidHatsAddress();
error DragonTokenizedStrategy__ReceiverHasExistingShares();

// DragonTokenizedStrategy specific errors
error DragonTokenizedStrategy__VaultSharesNotTransferable();
error DragonTokenizedStrategy__PerformanceFeeIsAlwaysZero();
error DragonTokenizedStrategy__PerformanceFeeDisabled();
error DragonTokenizedStrategy__ZeroLockupDuration();
error DragonTokenizedStrategy__InsufficientLockupDuration();
error DragonTokenizedStrategy__DepositMoreThanMax();
error DragonTokenizedStrategy__MintMoreThanMax();
error DragonTokenizedStrategy__WithdrawMoreThanMax();
error DragonTokenizedStrategy__RedeemMoreThanMax();
error DragonTokenizedStrategy__SharesStillLocked();
error DragonTokenizedStrategy__InvalidLockupDuration();
error DragonTokenizedStrategy__InvalidRageQuitCooldownPeriod();
error DragonTokenizedStrategy__RageQuitInProgress();
error DragonTokenizedStrategy__StrategyInShutdown();
error DragonTokenizedStrategy__NoSharesToRageQuit();
error DragonTokenizedStrategy__SharesAlreadyUnlocked();
error DragonTokenizedStrategy__LockupDurationTooShort();
error DragonTokenizedStrategy__MaxUnlockIsAlwaysZero();
error DragonTokenizedStrategy__NoOperation();
error DragonTokenizedStrategy__InvalidReceiver();
// BaseStrategy specific errors
error BaseStrategy__NotSelf();
