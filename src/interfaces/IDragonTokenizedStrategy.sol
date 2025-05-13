// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ITokenizedStrategy } from "./ITokenizedStrategy.sol";

interface IDragonTokenizedStrategy is ITokenizedStrategy {
    // DragonTokenizedStrategy storage slot
    struct DragonTokenizedStrategyStorage {
        bool isDragonOnly;
    }
    /**
     * @notice Emitted when a new lockup is set for a user
     * @param user The user whose lockup was set
     * @param unlockTime The timestamp when shares will be unlocked
     * @param lockedShares The amount of shares locked
     */
    event NewLockupSet(address indexed user, uint256 lockTime, uint256 unlockTime, uint256 lockedShares);

    event LockupDurationSet(uint256 lockupDuration);
    event RageQuitCooldownPeriodSet(uint256 rageQuitCooldownPeriod);

    /**
     * @notice Emitted when a user initiates rage quit
     * @param user The user who initiated rage quit
     * @param unlockTime The new unlock time after rage quit
     */
    event RageQuitInitiated(address indexed user, uint256 indexed unlockTime);

    /**
     * @notice Emitted when Dragon-only mode is toggled
     * @param enabled Whether Dragon-only mode is enabled or disabled
     */
    event DragonModeToggled(bool enabled);

    /**
     * @notice Deposits assets with a lockup period
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the shares
     * @param lockupDuration The duration of the lockup in seconds
     * @return shares The amount of shares minted
     */
    function depositWithLockup(
        uint256 assets,
        address receiver,
        uint256 lockupDuration
    ) external payable returns (uint256 shares);

    /**
     * @notice Mints shares with a lockup period
     * @param shares The amount of shares to mint
     * @param receiver The address to receive the shares
     * @param lockupDuration The duration of the lockup in seconds
     * @return assets The amount of assets used
     */
    function mintWithLockup(
        uint256 shares,
        address receiver,
        uint256 lockupDuration
    ) external payable returns (uint256 assets);

    /**
     * @notice Initiates a rage quit, allowing gradual withdrawal over the cooldown period
     * @dev Sets a cooldown period lockup and enables proportional withdrawals
     */
    function initiateRageQuit() external;

    /**
     * @notice Toggles the Dragon-only mode
     * @param enabled Whether to enable or disable Dragon-only mode
     */
    function toggleDragonMode(bool enabled) external;

    /**
     * @notice Sets the minimum lockup duration
     * @param newDuration The new minimum lockup duration in seconds
     */
    function setLockupDuration(uint256 newDuration) external;

    /**
     * @notice Sets the rage quit cooldown period
     * @param newPeriod The new rage quit cooldown period in seconds
     */
    function setRageQuitCooldownPeriod(uint256 newPeriod) external;

    /**
     * @notice Indicates if the strategy is in Dragon-only mode
     * @return True if only the operator can deposit/mint, false otherwise
     */
    function isDragonOnly() external view returns (bool);

    /**
     * @notice Returns the amount of unlocked shares for a user
     * @param user The user's address
     * @return The amount of shares that can be withdrawn/redeemed
     */
    function unlockedShares(address user) external view returns (uint256);

    /**
     * @notice Returns the unlock time for a user's locked shares
     * @param user The user's address
     * @return The unlock timestamp
     */
    function getUnlockTime(address user) external view returns (uint256);

    /**
     * @notice Returns detailed information about a user's lockup status
     * @param user The address to check
     * @return unlockTime The timestamp when shares unlock
     * @return lockedShares The amount of shares that are locked
     * @return isRageQuit Whether the user is in rage quit mode
     * @return totalShares Total shares owned by user
     * @return withdrawableShares Amount of shares that can be withdrawn now
     */
    function getUserLockupInfo(
        address user
    )
        external
        view
        returns (
            uint256 unlockTime,
            uint256 lockedShares,
            bool isRageQuit,
            uint256 totalShares,
            uint256 withdrawableShares
        );

    /**
     * @notice Returns the remaining cooldown time in seconds for a user's lock
     * @param user The address to check
     * @return remainingTime The time remaining in seconds until unlock (0 if already unlocked)
     */
    function getRemainingCooldown(address user) external view returns (uint256 remainingTime);

    /**
     * @notice Returns the minimum lockup duration
     * @return The minimum lockup duration in seconds
     */
    function minimumLockupDuration() external view returns (uint256);

    /**
     * @notice Returns the rage quit cooldown period
     * @return The rage quit cooldown period in seconds
     */
    function rageQuitCooldownPeriod() external view returns (uint256);

    /**
     * @notice Returns the regen governance address
     * @return The address of the regen governance
     */
    function regenGovernance() external view returns (address);
}
