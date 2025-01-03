// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

error ZeroAddress();
error Unauthorized();

error VaultSharesNotTransferable();
error PerformanceFeeIsAlwaysZero();
error PerformanceFeeDisabled();
error MaxUnlockIsAlwaysZero();
error CantWithdrawLockedShares();
error ZeroLockupDuration();
error InsufficientLockupDuration();
error ZeroShares();
error ZeroAssets();
error DepositMoreThanMax();
error MintMoreThanMax();
error WithdrawMoreThanMax();
error RedeemMoreThanMax();
error SharesStillLocked();
error InvalidLockupDuration();
error InvalidRageQuitCooldownPeriod();
error RageQuitInProgress();
error StrategyInShutdown();
