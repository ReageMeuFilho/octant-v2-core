// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMultistrategyVault } from "./IMultistrategyVault.sol";

/**
 * @title Octant Multistrategy Locked Vault Interface
 * @author Golem Foundation
 * @custom:security-contact security@golem.foundation
 * @notice Extends the base multistrategy vault with share lockups and a user-driven rage-quit flow.
 * @dev Enables users to initiate a rage quit that locks their shares for a cooldown period before
 *      withdrawal. Governance (regen governance) can update the cooldown via a two-step change with
 *      a time delay. Integrations should account for custodied (locked) shares versus available shares.
 */
interface IMultistrategyLockedVault is IMultistrategyVault {
    /**
     * @notice Storage for lockup information per user
     */
    struct LockupInfo {
        uint256 lockupTime; // When the lockup started
        uint256 unlockTime; // When shares become fully unlocked
    }

    /**
     * @notice Custody struct to track locked shares during rage quit
     */
    struct CustodyInfo {
        uint256 lockedShares; // Amount of shares locked for rage quit
        uint256 unlockTime; // When the shares can be withdrawn
    }

    // Events
    event RageQuitInitiated(address indexed user, uint256 shares, uint256 unlockTime);
    event RageQuitCooldownPeriodChanged(uint256 oldPeriod, uint256 newPeriod);
    event PendingRageQuitCooldownPeriodChange(uint256 newPeriod, uint256 effectiveTimestamp);
    event RageQuitCooldownPeriodChangeCancelled(uint256 pendingPeriod, uint256 proposedAt, uint256 cancelledAt);
    event RageQuitCancelled(address indexed user, uint256 freedShares);
    event RegenGovernanceChanged(address indexed previousGovernance, address indexed newGovernance);

    // Add necessary error definitions
    error InvalidRageQuitCooldownPeriod();
    error SharesStillLocked();
    error RageQuitAlreadyInitiated();
    error NoSharesToRageQuit();
    error NotRegenGovernance();
    error InvalidShareAmount();
    error InsufficientBalance();
    error InsufficientAvailableShares();
    error ExceedsCustodiedAmount();
    error NoCustodiedShares();
    error NoActiveRageQuit();
    error TransferExceedsAvailableShares();
    error NoPendingRageQuitCooldownPeriodChange();
    error RageQuitCooldownPeriodChangeDelayNotElapsed();
    error RageQuitCooldownPeriodChangeDelayElapsed();
    error InvalidGovernanceAddress();

    /**
     * @notice Initiates a rage quit by locking `shares` until the unlock time is reached.
     * @param shares The amount of vault shares to lock for rage quit.
     */
    function initiateRageQuit(uint256 shares) external;

    /**
     * @notice Proposes a new rage quit cooldown period.
     * @dev Starts a pending change which must later be finalized after the delay elapses.
     * @param _rageQuitCooldownPeriod The new cooldown period in seconds.
     */
    function proposeRageQuitCooldownPeriodChange(uint256 _rageQuitCooldownPeriod) external;

    /**
     * @notice Finalizes a previously proposed rage quit cooldown period change after the delay.
     */
    function finalizeRageQuitCooldownPeriodChange() external;

    /**
     * @notice Cancels a pending rage quit cooldown period change.
     */
    function cancelRageQuitCooldownPeriodChange() external;

    /**
     * @notice Sets the regen governance address authorized to manage rage quit parameters.
     * @param _regenGovernance The new regen governance address.
     */
    function setRegenGovernance(address _regenGovernance) external;

    /**
     * @notice Cancels an active rage quit for the caller and frees any locked shares.
     */
    function cancelRageQuit() external;

    /**
     * @notice Get the amount of shares that can be transferred by a user
     * @param user The address to check transferable shares for
     * @return The amount of shares available for transfer (not locked in custody)
     */
    function getTransferableShares(address user) external view returns (uint256);

    /**
     * @notice Get the amount of shares available for rage quit initiation
     * @param user The address to check rage quitable shares for
     * @return The amount of shares available for initiating rage quit
     */
    function getRageQuitableShares(address user) external view returns (uint256);
}
