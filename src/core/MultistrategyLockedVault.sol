// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { MultistrategyVault } from "src/core/MultistrategyVault.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";
import { IMultistrategyLockedVault } from "src/core/interfaces/IMultistrategyLockedVault.sol";

/**
 * @title LockedMultistrategyVault
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
contract MultistrategyLockedVault is MultistrategyVault, IMultistrategyLockedVault {
    // Mapping of user address to their custody info
    mapping(address => CustodyInfo) public custodyInfo;

    // Regen governance address
    address public regenGovernance;

    // Cooldown period for rage quit
    uint256 public rageQuitCooldownPeriod;

    // Constants
    uint256 public constant INITIAL_RAGE_QUIT_COOLDOWN_PERIOD = 7 days;
    uint256 public constant RANGE_MINIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 1 days;
    uint256 public constant RANGE_MAXIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 30 days;

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
     * @notice Initiate rage quit process to unlock specific amount of shares
     * @param shares Amount of shares to lock for rage quit
     */
    function initiateRageQuit(uint256 shares) external {
        if (shares == 0) revert InvalidShareAmount();
        uint256 userBalance = balanceOf(msg.sender);
        if (userBalance < shares) revert InsufficientBalance();

        CustodyInfo storage custody = custodyInfo[msg.sender];

        // Check if user already has shares in custody
        if (custody.lockedShares > 0) {
            revert RageQuitAlreadyInitiated();
        }

        // Available shares = total balance - already locked shares
        uint256 availableShares = userBalance - custody.lockedShares;
        if (availableShares < shares) revert InsufficientAvailableShares();

        // Lock the shares in custody
        custody.lockedShares = shares;
        custody.unlockTime = block.timestamp + rageQuitCooldownPeriod;

        emit RageQuitInitiated(msg.sender, shares, custody.unlockTime);
    }

    /**
     * @notice Override withdrawal functions to handle custodied shares
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) public override(MultistrategyVault, IMultistrategyVault) nonReentrant returns (uint256) {
        uint256 shares = _convertToShares(assets, Rounding.ROUND_UP);
        _processCustodyWithdrawal(owner, shares);
        _redeem(msg.sender, receiver, owner, assets, shares, maxLoss, strategiesArray);
        return shares;
    }

    /**
     * @notice Override redeem function to handle custodied shares
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) public override(MultistrategyVault, IMultistrategyVault) nonReentrant returns (uint256) {
        _processCustodyWithdrawal(owner, shares);
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
     * @notice Process withdrawal of custodied shares
     * @param owner Owner of the shares
     * @param shares Amount of shares to withdraw
     */
    function _processCustodyWithdrawal(address owner, uint256 shares) internal {
        CustodyInfo storage custody = custodyInfo[owner];

        // Check if there are custodied shares
        if (custody.lockedShares == 0) {
            revert NoCustodiedShares();
        }

        // Ensure cooldown period has passed
        if (block.timestamp < custody.unlockTime) {
            revert SharesStillLocked();
        }

        // Ensure user has sufficient balance
        uint256 userBalance = balanceOf(owner);
        if (userBalance < shares) {
            revert InsufficientBalance();
        }

        // Can only withdraw up to locked amount
        if (shares > custody.lockedShares) {
            revert ExceedsCustodiedAmount();
        }

        // Reduce locked shares by withdrawn amount
        custody.lockedShares -= shares;

        // If all custodied shares withdrawn, reset custody info
        if (custody.lockedShares == 0) {
            delete custodyInfo[owner];
        }
    }

    /**
     * @notice Override internal transfer to prevent locked shares from being transferred
     * @param sender_ Address sending shares
     * @param receiver_ Address receiving shares  
     * @param amount_ Amount of shares to transfer
     */
    function _transfer(address sender_, address receiver_, uint256 amount_) internal override {
        // Check if sender has locked shares that would prevent this transfer
        CustodyInfo memory custody = custodyInfo[sender_];
        
        if (custody.lockedShares > 0) {
            uint256 senderBalance = balanceOf(sender_);
            uint256 availableShares = senderBalance - custody.lockedShares;
            
            // Revert if trying to transfer more than available shares
            if (amount_ > availableShares) {
                revert TransferExceedsAvailableShares();
            }
        }
        
        // Call parent implementation
        super._transfer(sender_, receiver_, amount_);
    }

    /**
     * @notice Get custody info for a user
     * @param user Address to check
     * @return lockedShares Amount of shares locked
     * @return unlockTime When shares can be withdrawn
     */
    function getCustodyInfo(
        address user
    ) external view returns (uint256 lockedShares, uint256 unlockTime) {
        CustodyInfo memory custody = custodyInfo[user];
        return (custody.lockedShares, custody.unlockTime);
    }

    /**
     * @notice Cancel rage quit and unlock custodied shares
     */
    function cancelRageQuit() external {
        CustodyInfo storage custody = custodyInfo[msg.sender];

        if (custody.lockedShares == 0) {
            revert NoActiveRageQuit();
        }

        // Clear custody info
        uint256 freedShares = custody.lockedShares;
        delete custodyInfo[msg.sender];

        emit RageQuitCancelled(msg.sender, freedShares);
    }
}
