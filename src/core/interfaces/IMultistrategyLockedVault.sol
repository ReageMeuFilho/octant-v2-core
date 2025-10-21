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
    /// @notice Emitted when a user initiates rage quit
    /// @param user User who initiated rage quit
    /// @param shares Amount of shares locked for rage quit
    /// @param unlockTime Timestamp when shares can be withdrawn
    event RageQuitInitiated(address indexed user, uint256 shares, uint256 unlockTime);
    /// @notice Emitted when rage quit cooldown period is changed
    /// @param oldPeriod Previous cooldown period in seconds
    /// @param newPeriod New cooldown period in seconds
    event RageQuitCooldownPeriodChanged(uint256 oldPeriod, uint256 newPeriod);
    /// @notice Emitted when a cooldown period change is proposed
    /// @param newPeriod Proposed cooldown period in seconds
    /// @param effectiveTimestamp Timestamp when change can be finalized
    event PendingRageQuitCooldownPeriodChange(uint256 newPeriod, uint256 effectiveTimestamp);
    /// @notice Emitted when a pending cooldown period change is cancelled
    /// @param pendingPeriod Period that was pending in seconds
    /// @param proposedAt Timestamp when change was proposed
    /// @param cancelledAt Timestamp when change was cancelled
    event RageQuitCooldownPeriodChangeCancelled(uint256 pendingPeriod, uint256 proposedAt, uint256 cancelledAt);
    /// @notice Emitted when user cancels their active rage quit
    /// @param user User who cancelled rage quit
    /// @param freedShares Amount of shares unlocked
    event RageQuitCancelled(address indexed user, uint256 freedShares);
    /// @notice Emitted when regen governance address is changed
    /// @param previousGovernance Previous governance address
    /// @param newGovernance New governance address
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
     * @notice Initiates a rage quit by locking shares until the unlock time is reached
     * @param shares Amount of vault shares to lock for rage quit
     */
    function initiateRageQuit(uint256 shares) external;

    /**
     * @notice Proposes a new rage quit cooldown period
     * @dev Starts a pending change which must later be finalized after the delay elapses
     * @param _rageQuitCooldownPeriod Cooldown period in seconds
     */
    function proposeRageQuitCooldownPeriodChange(uint256 _rageQuitCooldownPeriod) external;

    /**
     * @notice Finalizes a previously proposed rage quit cooldown period change after the delay
     */
    function finalizeRageQuitCooldownPeriodChange() external;

    /**
     * @notice Cancels a pending rage quit cooldown period change
     */
    function cancelRageQuitCooldownPeriodChange() external;

    /**
     * @notice Sets the regen governance address authorized to manage rage quit parameters
     * @param _regenGovernance Regen governance address
     */
    function setRegenGovernance(address _regenGovernance) external;

    /**
     * @notice Cancels an active rage quit for the caller and frees any locked shares
     */
    function cancelRageQuit() external;

    /**
     * @notice Get the amount of shares that can be transferred by a user
     * @param user User address to check
     * @return Amount of shares available for transfer (not locked in custody)
     */
    function getTransferableShares(address user) external view returns (uint256);

    /**
     * @notice Get the amount of shares available for rage quit initiation
     * @param user User address to check
     * @return Amount of shares available for initiating rage quit
     */
    function getRageQuitableShares(address user) external view returns (uint256);
}
