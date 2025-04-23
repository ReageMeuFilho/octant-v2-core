// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Vault, IVault } from "src/dragons/vaults/Vault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IRageQuitHook
 * @notice Interface for strategies that implement rage quit hooks
 */
interface IRageQuitHook {
    /**
     * @notice Hook called when a user initiates rage quit
     * @param user Address of the user initiating rage quit
     * @return minimumUnlockTime Minimum time required by the strategy
     */
    function onRageQuitInitiated(address user) external returns (uint256 minimumUnlockTime);
}

/**
 * @title LockedVault
 * @notice Vault with modified unlocking mechanism similar to DragonTokenizedStrategy
 * that consults strategies for minimum unlock times during rage quit
 */
contract LockedVault is Vault {
    // Add necessary error definitions
    error InvalidLockupDuration();
    error InvalidRageQuitCooldownPeriod();
    error InsufficientLockupDuration();
    error SharesStillLocked();
    error RageQuitInProgress();
    error SharesAlreadyUnlocked();
    error NoSharesToRageQuit();
    error ZeroLockupDuration();
    error ExceedsUnlockedAmount();
    error DepositNotAllowed();
    error MintNotAllowed();

    // Storage for lockup information per user
    struct LockupInfo {
        uint256 lockupTime; // When the lockup started
        uint256 unlockTime; // When shares become fully unlocked
        uint256 lockedShares; // Amount of locked shares
        bool isRageQuit; // Whether user initiated rage quit
    }

    // Mapping of user address to their lockup info
    mapping(address => LockupInfo) public voluntaryLockups;

    // Minimum required lockup duration
    uint256 public minimumLockupDuration;

    // Cooldown period for rage quit
    uint256 public rageQuitCooldownPeriod;

    // Constants
    uint256 public constant RANGE_MINIMUM_LOCKUP_DURATION = 7 days;
    uint256 public constant RANGE_MAXIMUM_LOCKUP_DURATION = 365 days;
    uint256 public constant RANGE_MINIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 1 days;
    uint256 public constant RANGE_MAXIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 30 days;

    event NewLockupSet(address indexed user, uint256 lockupTime, uint256 unlockTime, uint256 lockedShares);
    event RageQuitInitiated(address indexed user, uint256 unlockTime);
    event LockupDurationSet(uint256 lockupDuration);
    event RageQuitCooldownPeriodSet(uint256 cooldownPeriod);
    event StrategyRageQuitHookCalled(address indexed strategy, uint256 minimumUnlockTime, bool success);

    // Define onlyRegenGovernance modifier
    modifier onlyRegenGovernance() {
        // Implement access control logic
        _;
    }

    /**
     * @notice Set the lockup duration
     * @param _lockupDuration New minimum lockup duration
     */
    function setLockupDuration(uint256 _lockupDuration) external onlyRegenGovernance {
        if (_lockupDuration < RANGE_MINIMUM_LOCKUP_DURATION || _lockupDuration > RANGE_MAXIMUM_LOCKUP_DURATION) {
            revert InvalidLockupDuration();
        }
        minimumLockupDuration = _lockupDuration;
        emit LockupDurationSet(_lockupDuration);
    }

    /**
     * @notice Set the rage quit cooldown period
     * @param _rageQuitCooldownPeriod New rage quit cooldown period
     */
    function setRageQuitCooldownPeriod(uint256 _rageQuitCooldownPeriod) external onlyRegenGovernance {
        if (
            _rageQuitCooldownPeriod < RANGE_MINIMUM_RAGE_QUIT_COOLDOWN_PERIOD ||
            _rageQuitCooldownPeriod > RANGE_MAXIMUM_RAGE_QUIT_COOLDOWN_PERIOD
        ) {
            revert InvalidRageQuitCooldownPeriod();
        }
        rageQuitCooldownPeriod = _rageQuitCooldownPeriod;
        emit RageQuitCooldownPeriodSet(_rageQuitCooldownPeriod);
    }

    /**
     * @notice Initiate rage quit process to unlock shares earlier
     * Consults all strategies via hooks to determine the appropriate unlock time
     */
    function initiateRageQuit() external {
        if (balanceOf(msg.sender) == 0) revert NoSharesToRageQuit();

        LockupInfo storage lockup = voluntaryLockups[msg.sender];
        if (block.timestamp >= lockup.unlockTime) revert SharesAlreadyUnlocked();
        if (lockup.isRageQuit) revert RageQuitInProgress();

        // Default unlock time based on vault's rage quit cooldown
        uint256 defaultUnlockTime = block.timestamp + rageQuitCooldownPeriod;

        // Get all strategies from default queue
        address[] memory strategies = defaultQueue;
        uint256 maxStrategyUnlockTime = 0;

        // Call each strategy's hook to get minimum unlock times
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];

            // Skip inactive strategies
            if (_strategies[strategy].activation == 0) continue;

            // Try to call the hook, but don't revert if it fails
            try IRageQuitHook(strategy).onRageQuitInitiated(msg.sender) returns (uint256 minimumUnlockTime) {
                // If strategy returned a valid future timestamp
                if (minimumUnlockTime > block.timestamp) {
                    // Track the maximum unlock time required by any strategy
                    if (minimumUnlockTime > maxStrategyUnlockTime) {
                        maxStrategyUnlockTime = minimumUnlockTime;
                    }
                }
                emit StrategyRageQuitHookCalled(strategy, minimumUnlockTime, true);
            } catch {
                // Strategy doesn't implement the hook or execution failed
                emit StrategyRageQuitHookCalled(strategy, 0, false);
            }
        }

        // Set unlock time to the longer of:
        // 1. Default unlock time (current time + cooldown)
        // 2. Maximum strategy-required unlock time
        // 3. But never longer than the original unlock time
        uint256 newUnlockTime;
        if (maxStrategyUnlockTime > defaultUnlockTime) {
            newUnlockTime = maxStrategyUnlockTime;
        } else {
            newUnlockTime = defaultUnlockTime;
        }

        // Don't extend beyond original unlock time
        if (newUnlockTime > lockup.unlockTime) {
            newUnlockTime = lockup.unlockTime;
        }

        // Update the lockup information
        lockup.unlockTime = newUnlockTime;
        lockup.lockupTime = block.timestamp; // Set starting point for gradual unlocking
        lockup.isRageQuit = true;

        emit RageQuitInitiated(msg.sender, lockup.unlockTime);
    }

    /**
     * @notice Deposit with lockup to earn yield
     * @param assets Amount of assets to deposit
     * @param receiver Address receiving the shares
     * @param lockupDuration Duration to lock the shares
     * @return shares Shares issued
     */
    function depositWithLockup(
        uint256 assets,
        address receiver,
        uint256 lockupDuration
    ) external returns (uint256 shares) {
        uint256 amount = assets;
        // Deposit all if sent with max uint
        if (amount == type(uint256).max) {
            amount = IERC20(asset).balanceOf(msg.sender);
        }

        shares = _convertToShares(amount, Rounding.ROUND_DOWN);
        _deposit(receiver, amount, shares);

        // Set or extend lockup
        _setOrExtendLockup(receiver, lockupDuration, shares);

        return shares;
    }

    function deposit(uint256, address) external override returns (uint256) {
        revert DepositNotAllowed();
    }

    function mint(uint256, address) external override returns (uint256) {
        revert MintNotAllowed();
    }

    function mintWithLockup(
        uint256 shares,
        address receiver,
        uint256 lockupDuration
    ) external nonReentrant returns (uint256) {
        uint256 assets = _convertToAssets(shares, Rounding.ROUND_UP);
        _deposit(receiver, assets, shares);
        _setOrExtendLockup(receiver, lockupDuration, shares);
        return assets;
    }

    /**
     * @notice Override withdrawal functions to check if shares are unlocked
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) public override nonReentrant returns (uint256) {
        _checkUnlocked(owner);
        return super.withdraw(assets, receiver, owner, maxLoss, strategiesArray);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) public override nonReentrant returns (uint256) {
        _checkUnlocked(owner);
        return super.redeem(shares, receiver, owner, maxLoss, strategiesArray);
    }

    /**
     * @notice Check if shares can be withdrawn based on lockup
     * @param owner Owner of the shares
     */
    function _checkUnlocked(address owner) internal view {
        LockupInfo memory lockup = voluntaryLockups[owner];

        if (block.timestamp < lockup.unlockTime) {
            revert SharesStillLocked();
        }
    }

    /**
     * @notice Utility function to set or extend a user's lockup
     * @param user User address
     * @param lockupDuration Duration to lock shares
     * @param totalSharesLocked Total shares to lock
     */
    function _setOrExtendLockup(address user, uint256 lockupDuration, uint256 totalSharesLocked) internal {
        LockupInfo storage lockup = voluntaryLockups[user];
        uint256 currentTime = block.timestamp;

        if (lockup.unlockTime <= currentTime) {
            // New lockup
            if (lockupDuration < minimumLockupDuration) {
                revert InsufficientLockupDuration();
            }
            lockup.lockupTime = currentTime;
            lockup.unlockTime = currentTime + lockupDuration;
            lockup.lockedShares = totalSharesLocked;
        } else {
            // Update existing lockup
            lockup.lockedShares = totalSharesLocked;

            if (lockupDuration > 0) {
                // Extend existing lockup
                uint256 newUnlockTime = lockup.unlockTime + lockupDuration;
                if (newUnlockTime < currentTime + minimumLockupDuration) {
                    revert InsufficientLockupDuration();
                }
                lockup.unlockTime = newUnlockTime;
            }
        }

        emit NewLockupSet(user, lockup.lockupTime, lockup.unlockTime, lockup.lockedShares);
    }
}
