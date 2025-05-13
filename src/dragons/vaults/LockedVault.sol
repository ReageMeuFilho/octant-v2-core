// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Vault, IVault } from "src/dragons/vaults/Vault.sol";
import { ILockedVault } from "src/interfaces/ILockedVault.sol";

/**
 * @title LockedVault
 * @notice Vault with modified unlocking mechanism similar to DragonTokenizedStrategy
 * that consults strategies for minimum unlock times during rage quit
 *
 * @dev Important Behavior Notes:
 *
 * 1. Rage Quit Scope:
 *    - When a rage quit is initiated, it applies to ALL shares owned by the user at the time of initiation
 *    - Any new deposits made AFTER initiating rage quit will also be included in the unlock
 *    - The unlock applies to the user's total share balance, not individual deposits
 *
 * 2. One-Time Withdrawal Window:
 *    - A rage quit process grants exactly ONE opportunity to withdraw/redeem shares
 *    - This window opens after the cooldown period and remains open until the first withdrawal/redeem
 *    - After the first withdrawal/redeem (even partial), the window closes
 *    - Any remaining shares will require a new rage quit process to be unlocked
 *
 * 3. Partial Withdrawals:
 *    - Users can withdraw/redeem any amount up to their total balance during the unlock window
 *    - If a user only withdraws/redeems a portion of their shares:
 *      * The remaining shares become locked again
 *      * A new rage quit process must be initiated to unlock the remaining shares
 *      * The new rage quit will have its own cooldown period
 *
 * 4. Example Scenarios:
 *    a) User has 100 shares, initiates rage quit, waits cooldown:
 *       - Can withdraw/redeem any amount (1-100) in one transaction
 *       - After first withdrawal/redeem, remaining shares are locked
 *       - New rage quit needed for remaining shares
 *
 *    b) User has 100 shares, initiates rage quit, deposits 50 more during cooldown:
 *       - Can withdraw/redeem up to 150 shares after cooldown
 *       - Same one-time window rules apply to total balance
 *
 */
contract LockedVault is Vault, ILockedVault {
    // Mapping of user address to their lockup info
    mapping(address => LockupInfo) public voluntaryLockups;

    // Cooldown period for rage quit
    uint256 public rageQuitCooldownPeriod;

    // Constants
    uint256 public constant INITIAL_RAGE_QUIT_COOLDOWN_PERIOD = 7 days;
    uint256 public constant RANGE_MINIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 1 days;
    uint256 public constant RANGE_MAXIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 30 days;

    // Define onlyRegenGovernance modifier
    modifier onlyRegenGovernance() {
        // Implement access control logic
        _;
    }

    function initialize(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime
    ) public override(Vault, IVault) {
        rageQuitCooldownPeriod = INITIAL_RAGE_QUIT_COOLDOWN_PERIOD;
        super.initialize(_asset, _name, _symbol, _roleManager, _profitMaxUnlockTime);
    }

    /**
     * @notice Set the lockup duration
     * @param _rageQuitCooldownPeriod New cooldown period for rage quit
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
        if (block.timestamp <= lockup.unlockTime) revert RageQuitAlreadyInitiated();

        // Default unlock time based on vault's rage quit cooldown
        uint256 defaultUnlockTime = block.timestamp + rageQuitCooldownPeriod;

        lockup.unlockTime = defaultUnlockTime;

        lockup.lockupTime = block.timestamp; // Set starting point for gradual unlocking

        emit RageQuitInitiated(msg.sender, lockup.lockupTime, defaultUnlockTime);
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
    ) public override(IVault, Vault) nonReentrant returns (uint256) {
        _checkUnlocked(owner);
        voluntaryLockups[owner].lockupTime = 0;
        uint256 shares = _convertToShares(assets, Rounding.ROUND_UP);
        _redeem(msg.sender, receiver, owner, assets, shares, maxLoss, strategiesArray);
        return shares;
    }

    /**
     * @notice Override redeem function to check if shares are unlocked
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) public override(IVault, Vault) nonReentrant returns (uint256) {
        _checkUnlocked(owner);
        voluntaryLockups[owner].lockupTime = 0;
        uint256 assets = _convertToAssets(shares, Rounding.ROUND_DOWN);
        // Always return the actual amount of assets withdrawn.
        return _redeem(msg.sender, receiver, owner, assets, shares, maxLoss, strategiesArray);
    }

    /**
     * @notice Check if shares can be withdrawn based on lockup
     * @param owner Owner of the shares
     */
    function _checkUnlocked(address owner) internal view {
        LockupInfo memory lockup = voluntaryLockups[owner];

        if (block.timestamp <= lockup.unlockTime || lockup.lockupTime == 0) {
            revert SharesStillLocked();
        }
    }
}
