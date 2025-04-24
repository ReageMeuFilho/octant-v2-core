// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Vault, IVault } from "src/dragons/vaults/Vault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILockedVault } from "src/interfaces/ILockedVault.sol";
/**
 * @title LockedVault
 * @notice Vault with modified unlocking mechanism similar to DragonTokenizedStrategy
 * that consults strategies for minimum unlock times during rage quit
 */
contract LockedVault is Vault, ILockedVault {
    // Mapping of user address to their lockup info
    mapping(address => LockupInfo) public voluntaryLockups;

    // Cooldown period for rage quit
    uint256 public rageQuitCooldownPeriod;

    // Constants
    uint256 public constant RANGE_MINIMUM_LOCKUP_DURATION = 7 days;
    uint256 public constant RANGE_MAXIMUM_LOCKUP_DURATION = 365 days;
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
        uint256 _profitMaxUnlockTime,
        uint256 _rageQuitCooldownPeriod
    ) external {
        rageQuitCooldownPeriod = _rageQuitCooldownPeriod;
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
        if (block.timestamp <= lockup.unlockTime) revert SharesAlreadyUnlocked();

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

        if (block.timestamp < lockup.unlockTime) {
            revert SharesStillLocked();
        }
    }
}
