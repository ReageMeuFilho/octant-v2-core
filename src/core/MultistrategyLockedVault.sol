// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { MultistrategyVault } from "src/core/MultistrategyVault.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";
import { IMultistrategyLockedVault } from "src/core/interfaces/IMultistrategyLockedVault.sol";

/**
 * @title MultistrategyLockedVault
 * @notice A locked vault with custody-based rage quit mechanism and two-step cooldown period changes
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
 * ## Two-Step Cooldown Period Changes:
 * 1. **Grace Period Protection:**
 *    - Governance proposes cooldown period changes with 14-day delay
 *    - Users can rage quit under current terms during grace period
 *    - Protects users from unfavorable governance decisions
 *
 * 2. **Change Process:**
 *    - **Propose**: Governance proposes new period, starts grace period
 *    - **Grace Period**: 14 days for users to exit under current terms
 *    - **Finalize**: Anyone can finalize change after grace period
 *    - **Cancel**: Governance can cancel during grace period
 *
 * 3. **User Protection:**
 *    - Users who rage quit before finalization use old cooldown period
 *    - Users who rage quit after finalization use new cooldown period
 *    - No retroactive application of cooldown changes
 *
 */
contract MultistrategyLockedVault is MultistrategyVault, IMultistrategyLockedVault {
    // Mapping of user address to their lockup info
    mapping(address => LockupInfo) public voluntaryLockups;

    // Regen governance address
    address public regenGovernance;

    // Cooldown period for rage quit
    uint256 public rageQuitCooldownPeriod;

    // Two-step rage quit cooldown period change variables
    uint256 public pendingRageQuitCooldownPeriod;
    uint256 public rageQuitCooldownPeriodChangeTimestamp;
    // Constants
    uint256 public constant INITIAL_RAGE_QUIT_COOLDOWN_PERIOD = 7 days;
    uint256 public constant RANGE_MINIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 1 days;
    uint256 public constant RANGE_MAXIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 30 days;
    uint256 public constant RAGE_QUIT_COOLDOWN_CHANGE_DELAY = 14 days;

    // Define onlyRegenGovernance modifier
    modifier onlyRegenGovernance() {
        if (msg.sender != regenGovernance) revert NotRegenGovernance();
        _;
    }

    function initialize(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager, // role manager is also the regen governance address
        uint256 _profitMaxUnlockTime
    ) public override(MultistrategyVault, IMultistrategyVault) {
        rageQuitCooldownPeriod = INITIAL_RAGE_QUIT_COOLDOWN_PERIOD;
        super.initialize(_asset, _name, _symbol, _roleManager, _profitMaxUnlockTime);
        regenGovernance = _roleManager;
    }

    /**
     * @notice Propose a new rage quit cooldown period
     * @param _rageQuitCooldownPeriod New cooldown period for rage quit
     * @dev Starts a grace period allowing users to rage quit under current terms
     */
    function proposeRageQuitCooldownPeriodChange(uint256 _rageQuitCooldownPeriod) external onlyRegenGovernance {
        if (
            _rageQuitCooldownPeriod < RANGE_MINIMUM_RAGE_QUIT_COOLDOWN_PERIOD ||
            _rageQuitCooldownPeriod > RANGE_MAXIMUM_RAGE_QUIT_COOLDOWN_PERIOD
        ) {
            revert InvalidRageQuitCooldownPeriod();
        }

        if (_rageQuitCooldownPeriod == rageQuitCooldownPeriod) {
            revert InvalidRageQuitCooldownPeriod();
        }

        pendingRageQuitCooldownPeriod = _rageQuitCooldownPeriod;
        rageQuitCooldownPeriodChangeTimestamp = block.timestamp;

        uint256 effectiveTimestamp = block.timestamp + RAGE_QUIT_COOLDOWN_CHANGE_DELAY;
        emit PendingRageQuitCooldownPeriodChange(_rageQuitCooldownPeriod, effectiveTimestamp);
    }

    /**
     * @notice Finalize the rage quit cooldown period change after the grace period
     * @dev Can only be called after the grace period has elapsed
     */
    function finalizeRageQuitCooldownPeriodChange() external onlyRegenGovernance {
        if (pendingRageQuitCooldownPeriod == 0) {
            revert NoPendingRageQuitCooldownPeriodChange();
        }

        if (block.timestamp < rageQuitCooldownPeriodChangeTimestamp + RAGE_QUIT_COOLDOWN_CHANGE_DELAY) {
            revert RageQuitCooldownPeriodChangeDelayNotElapsed();
        }

        uint256 oldPeriod = rageQuitCooldownPeriod;
        rageQuitCooldownPeriod = pendingRageQuitCooldownPeriod;
        pendingRageQuitCooldownPeriod = 0;
        rageQuitCooldownPeriodChangeTimestamp = 0;

        emit RageQuitCooldownPeriodChanged(oldPeriod, rageQuitCooldownPeriod);
    }

    /**
     * @notice Cancel a pending rage quit cooldown period change
     * @dev Can only be called by governance during the grace period
     */
    function cancelRageQuitCooldownPeriodChange() external onlyRegenGovernance {
        if (pendingRageQuitCooldownPeriod == 0) {
            revert NoPendingRageQuitCooldownPeriodChange();
        }

        pendingRageQuitCooldownPeriod = 0;
        rageQuitCooldownPeriodChangeTimestamp = 0;

        emit PendingRageQuitCooldownPeriodChange(0, 0);
    }

    /**
     * @notice Get the pending rage quit cooldown period if any
     * @return The pending cooldown period (0 if none)
     */
    function getPendingRageQuitCooldownPeriod() external view returns (uint256) {
        return pendingRageQuitCooldownPeriod;
    }

    /**
     * @notice Get the timestamp when rage quit cooldown period change was initiated
     * @return Timestamp of the change initiation (0 if none)
     */
    function getRageQuitCooldownPeriodChangeTimestamp() external view returns (uint256) {
        return rageQuitCooldownPeriodChangeTimestamp;
    }
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) public override(MultistrategyVault, IMultistrategyVault) nonReentrant returns (uint256) {
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
    ) public override(MultistrategyVault, IMultistrategyVault) nonReentrant returns (uint256) {
        _checkUnlocked(owner);
        voluntaryLockups[owner].lockupTime = 0;
        uint256 assets = _convertToAssets(shares, Rounding.ROUND_DOWN);
        // Always return the actual amount of assets withdrawn.
        return _redeem(msg.sender, receiver, owner, assets, shares, maxLoss, strategiesArray);
    }

    /**
     * @notice Set the regen governance address
     * @param _regenGovernance New regen governance address
     */
    function setRegenGovernance(address _regenGovernance) external onlyRegenGovernance {
        regenGovernance = _regenGovernance;
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
