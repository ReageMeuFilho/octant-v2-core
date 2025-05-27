// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IVault } from "src/dragons/vaults/Vault.sol";

interface ILockedVault is IVault {
    // Add necessary error definitions
    error InvalidRageQuitCooldownPeriod();
    error SharesStillLocked();
    error RageQuitAlreadyInitiated();
    error NoSharesToRageQuit();

    // Events
    event RageQuitInitiated(address indexed user, uint256 lockupTime, uint256 unlockTime);
    event RageQuitCooldownPeriodSet(uint256 rageQuitCooldownPeriod);

    // Storage for lockup information per user
    struct LockupInfo {
        uint256 lockupTime; // When the lockup started
        uint256 unlockTime; // When shares become fully unlocked
    }

    function initiateRageQuit() external;
    function setRageQuitCooldownPeriod(uint256 _rageQuitCooldownPeriod) external;
}
