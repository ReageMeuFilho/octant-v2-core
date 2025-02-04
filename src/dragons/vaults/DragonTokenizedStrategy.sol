// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { TokenizedStrategy, IBaseStrategy, Math } from "./TokenizedStrategy.sol";
import { Unauthorized, TokenizedStrategy__NotOperator, DragonTokenizedStrategy__VaultSharesNotTransferable, DragonTokenizedStrategy__ZeroLockupDuration, DragonTokenizedStrategy__InsufficientLockupDuration, DragonTokenizedStrategy__SharesStillLocked, DragonTokenizedStrategy__InvalidLockupDuration, DragonTokenizedStrategy__InvalidRageQuitCooldownPeriod, DragonTokenizedStrategy__RageQuitInProgress, DragonTokenizedStrategy__StrategyInShutdown, DragonTokenizedStrategy__NoSharesToRageQuit, DragonTokenizedStrategy__SharesAlreadyUnlocked, DragonTokenizedStrategy__DepositMoreThanMax, DragonTokenizedStrategy__MintMoreThanMax, DragonTokenizedStrategy__WithdrawMoreThanMax, DragonTokenizedStrategy__RedeemMoreThanMax, ZeroShares, ZeroAssets, DragonTokenizedStrategy__ReceiverHasExistingShares } from "src/errors.sol";

contract DragonTokenizedStrategy is TokenizedStrategy {
    event NewLockupSet(address indexed user, uint256 indexed unlockTime, uint256 indexed lockedShares);
    event RageQuitInitiated(address indexed user, uint256 indexed unlockTime);
    event DragonModeToggled(bool enabled);
    
    bool public isDragonOnly = true;

    function toggleDragonMode(bool enabled) external onlyOperator {
        isDragonOnly = enabled;
        emit DragonModeToggled(enabled);
    }

    modifier onlyOperatorIfDragonMode() {
        if (isDragonOnly && msg.sender != _strategyStorage().operator) revert TokenizedStrategy__NotOperator();
        _;
    }

    function initialize(
        address _asset,
        string memory _name,
        address _operator,
        address _management,
        address _keeper,
        address _dragonRouter,
        address _regenGovernance
    ) external {
        __TokenizedStrategy_init(_asset, _name, _operator, _management, _keeper, _dragonRouter, _regenGovernance);
    }

    function setLockupDuration(uint256 _lockupDuration) external onlyRegenGovernance {
        if (_lockupDuration < RANGE_MINIMUM_LOCKUP_DURATION || _lockupDuration > RANGE_MAXIMUM_LOCKUP_DURATION) {
            revert DragonTokenizedStrategy__InvalidLockupDuration();
        }
        _strategyStorage().MINIMUM_LOCKUP_DURATION = _lockupDuration;
    }

    function setRageQuitCooldownPeriod(uint256 _rageQuitCooldownPeriod) external onlyRegenGovernance {
        if (
            _rageQuitCooldownPeriod < RANGE_MINIMUM_RAGE_QUIT_COOLDOWN_PERIOD ||
            _rageQuitCooldownPeriod > RANGE_MAXIMUM_RAGE_QUIT_COOLDOWN_PERIOD
        ) revert DragonTokenizedStrategy__InvalidRageQuitCooldownPeriod();
        _strategyStorage().RAGE_QUIT_COOLDOWN_PERIOD = _rageQuitCooldownPeriod;
    }

    function minimumLockupDuration() external view returns (uint256) {
        return _strategyStorage().MINIMUM_LOCKUP_DURATION;
    }

    function rageQuitCooldownPeriod() external view returns (uint256) {
        return _strategyStorage().RAGE_QUIT_COOLDOWN_PERIOD;
    }

    function regenGovernance() external view returns (address) {
        return _strategyStorage().REGEN_GOVERNANCE;
    }

    /**
     * @dev Internal function to set or extend a user's lockup.
     * @param user The user's address.
     * @param lockupDuration The amount of time to set or extend a user's lockup.
     * @param totalSharesLocked The amount of shares to lock.
     */
    function _setOrExtendLockup(
        StrategyData storage S,
        address user,
        uint256 lockupDuration,
        uint256 totalSharesLocked
    ) internal returns (uint256) {
        LockupInfo storage lockup = S.voluntaryLockups[user];
        uint256 currentTime = block.timestamp;

        // NOTE: if there is no lockup, and the lockup duration not 0 then set a new lockup
        if (lockup.unlockTime <= currentTime) {
            if (lockupDuration == 0) return 0;
            // NOTE: enforce minimum lockup duration for new lockups
            if (lockupDuration < _strategyStorage().MINIMUM_LOCKUP_DURATION) {
                revert DragonTokenizedStrategy__InsufficientLockupDuration();
            }
            lockup.lockupTime = currentTime;
            lockup.unlockTime = currentTime + lockupDuration;

            lockup.lockedShares = totalSharesLocked;
        } else {
            // NOTE: update the locked shares
            lockup.lockedShares = totalSharesLocked;
            // NOTE: if there is a lock up and the lockUpDuration is greater than 0 then extend the lockup ensuring it's more than minimum lockup duration
            if (lockupDuration > 0) {
                // Extend existing lockup
                uint256 newUnlockTime = lockup.unlockTime + lockupDuration;
                // Ensure the new unlock time is at least 3 months in the future
                if (newUnlockTime < currentTime + _strategyStorage().MINIMUM_LOCKUP_DURATION) {
                    revert DragonTokenizedStrategy__InsufficientLockupDuration();
                }

                lockup.unlockTime = newUnlockTime;
            }
        }

        emit NewLockupSet(user, lockup.unlockTime, lockup.lockedShares);
        return lockup.lockedShares;
    }

    /**
     * @dev Returns the amount of unlocked shares for a user.
     * @param user The user's address.
     * @return The amount of unlocked shares.
     */
    function _userUnlockedShares(StrategyData storage S, address user) internal view returns (uint256) {
        LockupInfo memory lockup = _strategyStorage().voluntaryLockups[user];
        uint256 balance = _balanceOf(S, user);

        if (block.timestamp >= lockup.unlockTime) {
            return balance;
        } else if (lockup.isRageQuit) {
            // Calculate unlocked portion based on time elapsed
            uint256 timeElapsed = block.timestamp - lockup.lockupTime;
            uint256 unlockedPortion = (timeElapsed * balance) / (lockup.unlockTime - lockup.lockupTime);
            return Math.min(unlockedPortion, balance);
        } else {
            return 0;
        }
    }

    /**
     * @dev Returns the amount of unlocked shares for a user.
     * @param user The user's address.
     * @return The amount of unlocked shares.
     */
    function unlockedShares(address user) external view returns (uint256) {
        StrategyData storage S = _strategyStorage();
        return _userUnlockedShares(S, user);
    }

    /**
     * @dev Returns the unlock time for a user's locked shares.
     * @param user The user's address.
     * @return The unlock timestamp.
     */
    function getUnlockTime(address user) external view returns (uint256) {
        return _strategyStorage().voluntaryLockups[user].unlockTime;
    }

    /**
     * @notice Returns the remaining cooldown time in seconds for a user's lock
     * @param user The address to check
     * @return remainingTime The time remaining in seconds until unlock (0 if already unlocked)
     */
    function getRemainingCooldown(address user) external view returns (uint256 remainingTime) {
        uint256 unlockTime = _strategyStorage().voluntaryLockups[user].unlockTime;
        if (unlockTime <= block.timestamp) {
            return 0;
        }
        return unlockTime - block.timestamp;
    }

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
        )
    {
        StrategyData storage S = _strategyStorage();
        LockupInfo memory lockup = S.voluntaryLockups[user];

        return (
            lockup.unlockTime,
            lockup.lockedShares,
            lockup.isRageQuit,
            _balanceOf(S, user),
            _userUnlockedShares(S, user)
        );
    }

    /**
     * @notice Initiates a rage quit, allowing gradual withdrawal over 3 months
     * @dev Sets a 3-month lockup and enables proportional withdrawals
     */
    function initiateRageQuit() external {
        StrategyData storage S = _strategyStorage();
        LockupInfo storage lockup = S.voluntaryLockups[msg.sender];

        if (_balanceOf(S, msg.sender) == 0) revert DragonTokenizedStrategy__NoSharesToRageQuit();
        if (block.timestamp >= lockup.unlockTime) revert DragonTokenizedStrategy__SharesAlreadyUnlocked();
        if (lockup.isRageQuit) revert DragonTokenizedStrategy__RageQuitInProgress();

        // Set 3-month lockup
        lockup.lockupTime = block.timestamp;
        lockup.unlockTime = block.timestamp + _strategyStorage().RAGE_QUIT_COOLDOWN_PERIOD;
        lockup.lockedShares = _balanceOf(S, msg.sender);
        lockup.isRageQuit = true;

        emit RageQuitInitiated(msg.sender, lockup.unlockTime);
    }

    /// @dev Internal implementation of {maxWithdraw}.
    function _maxWithdraw(
        StrategyData storage S,
        address _owner
    ) internal view override returns (uint256 maxWithdraw_) {
        // Get the max the owner could withdraw currently.

        maxWithdraw_ = IBaseStrategy(address(this)).availableWithdrawLimit(_owner);
        maxWithdraw_ = Math.min(_convertToAssets(S, _userUnlockedShares(S, _owner), Math.Rounding.Floor), maxWithdraw_);
    }

    /// @dev Internal implementation of {maxRedeem}.
    function _maxRedeem(StrategyData storage S, address _owner) internal view override returns (uint256 maxRedeem_) {
        // Get the max the owner could withdraw currently.
        maxRedeem_ = IBaseStrategy(address(this)).availableWithdrawLimit(_owner);
        maxRedeem_ = Math.min(
            // Can't redeem more than the balance.
            _convertToShares(S, maxRedeem_, Math.Rounding.Floor),
            _userUnlockedShares(S, _owner)
        );
    }

    /**
     * @notice Total number of underlying assets that can be
     * withdrawn from the strategy by `owner`, where `owner`
     * corresponds to the msg.sender of a {redeem} call.
     *
     * @param _owner The owner of the shares.
     * @return _maxWithdraw Max amount of `asset` that can be withdrawn.
     */
    function maxWithdraw(address _owner) external view override returns (uint256) {
        return _maxWithdraw(_strategyStorage(), _owner);
    }

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxWithdraw(address _owner, uint256 /*maxLoss*/) external view override returns (uint256) {
        return _maxWithdraw(_strategyStorage(), _owner);
    }

    /**
     * @notice Withdraws `assets` from `owners` shares and sends
     * the underlying tokens to `receiver`.
     * @dev This includes an added parameter to allow for losses.
     * @param assets The amount of underlying to withdraw.
     * @param receiver The address to receive `assets`.
     * @param _owner The address whose shares are burnt.
     * @param maxLoss The amount of acceptable loss in Basis points.
     * @return shares The actual amount of shares burnt.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address _owner,
        uint256 maxLoss
    ) public override nonReentrant returns (uint256 shares) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();
        LockupInfo storage lockup = S.voluntaryLockups[_owner];
        if (block.timestamp < lockup.unlockTime && !lockup.isRageQuit) {
            revert DragonTokenizedStrategy__SharesStillLocked();
        }
        if (assets > _maxWithdraw(S, _owner)) revert DragonTokenizedStrategy__WithdrawMoreThanMax();
        
        // Check for rounding error or 0 value.
        if ((shares = _convertToShares(S, assets, Math.Rounding.Ceil)) == 0) {
            revert ZeroShares();
        }
        if (lockup.isRageQuit) {
            lockup.lockedShares -= shares;
            lockup.lockupTime = block.timestamp;
        }
        // Withdraw and track the actual amount withdrawn for loss check.
        _withdraw(S, receiver, _owner, assets, shares, maxLoss);
    }

    /**
     * @notice Redeems exactly `shares` from `owner` and
     * sends `assets` of underlying tokens to `receiver`.
     * @dev This includes an added parameter to allow for losses.
     * @param shares The amount of shares burnt.
     * @param receiver The address to receive `assets`.
     * @param _owner The address whose shares are burnt.
     * @param maxLoss The amount of acceptable loss in Basis points.
     * @return . The actual amount of underlying withdrawn.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address _owner,
        uint256 maxLoss
    ) public override nonReentrant returns (uint256) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();
        LockupInfo storage lockup = S.voluntaryLockups[_owner];

        if (shares > _maxRedeem(S, _owner)) revert DragonTokenizedStrategy__RedeemMoreThanMax();
        if (block.timestamp < lockup.unlockTime && !lockup.isRageQuit) {
            revert DragonTokenizedStrategy__SharesStillLocked();
        }
        if (lockup.isRageQuit) {
            lockup.lockedShares -= shares;
            lockup.lockupTime = block.timestamp;
        }

        uint256 assets;
        // Check for rounding error or 0 value.
        if ((assets = _convertToAssets(S, shares, Math.Rounding.Floor)) == 0) {
            revert ZeroAssets();
        }

        // We need to return the actual amount withdrawn in case of a loss.
        return _withdraw(S, receiver, _owner, assets, shares, maxLoss);
    }

    /**
     * @notice Mints `shares` of strategy shares to `receiver` by
     * depositing exactly `assets` of underlying tokens.
     * @dev Please note that deposits are forbidden if rage quit was triggered.
     * @param assets The amount of underlying to deposit in.
     * @param receiver The address to receive the `shares`.
     * @return shares The actual amount of shares issued.
     */
    function deposit(uint256 assets, address receiver) external payable override onlyOperatorIfDragonMode returns (uint256 shares) {
        shares = _deposit(assets, receiver, 0);
    }

    /**
     * @dev Mints `shares` of strategy shares to `receiver` by depositing exactly `assets` of underlying tokens with a lock up
     * @dev The attached gnosis safe module may extend its own lockup duration
     * @dev Deposits with lockup are forbidden if rage quit was triggered for receiver, or if the receiver has existing shares to avoid unauthorized locking of user funds
     * @param assets The amount of assets to deposit.
     * @param receiver The receiver of the shares.
     * @param lockupDuration The duration of the lockup in seconds.
     * @return shares The amount of shares minted.
     */
    function depositWithLockup(
        uint256 assets,
        address receiver,
        uint256 lockupDuration
    ) external payable onlyOperatorIfDragonMode returns (uint256 shares) {
        if (lockupDuration == 0) revert DragonTokenizedStrategy__ZeroLockupDuration();
        shares = _deposit(assets, receiver, lockupDuration);
    }

    function _deposit(uint256 assets, address receiver, uint256 lockupDuration) internal returns (uint256 shares) {
        StrategyData storage S = _strategyStorage();
        if (receiver == S.dragonRouter) revert Unauthorized();
        if (S.voluntaryLockups[receiver].isRageQuit) revert DragonTokenizedStrategy__RageQuitInProgress();
        if (_balanceOf(S, receiver) > 0 && IBaseStrategy(address(this)).target() != address(receiver)) {
            revert DragonTokenizedStrategy__ReceiverHasExistingShares();
        }

        if (assets == type(uint256).max) {
            assets = S.asset.balanceOf(msg.sender);
        }

        if ((shares = _convertToShares(S, assets, Math.Rounding.Floor)) == 0) {
            revert ZeroShares();
        }

        _processDeposit(S, assets, shares, receiver);
        _setOrExtendLockup(S, receiver, lockupDuration, _balanceOf(S, receiver));
    }

    function _processDeposit(StrategyData storage S, uint256 assets, uint256 shares, address receiver) internal {
        if (S.shutdown) revert DragonTokenizedStrategy__StrategyInShutdown();
        if (assets > _maxDeposit(S, receiver)) revert DragonTokenizedStrategy__DepositMoreThanMax();
        if (shares > _maxMint(S, receiver)) revert DragonTokenizedStrategy__MintMoreThanMax();

        _deposit(S, receiver, assets, shares);
    }

    /**
     * @notice Mints exactly `shares` of strategy shares to
     * `receiver` by depositing `assets` of underlying tokens.
     * @param shares The amount of strategy shares mint.
     * @param receiver The address to receive the `shares`.
     * @return assets The actual amount of asset deposited.
     */
    function mint(uint256 shares, address receiver) external payable override onlyOperatorIfDragonMode returns (uint256 assets) {
        assets = _mint(shares, receiver, 0);
    }

    function mintWithLockup(
        uint256 shares,
        address receiver,
        uint256 lockupDuration
    ) external payable onlyOperatorIfDragonMode returns (uint256 assets) {
        if (lockupDuration == 0) revert DragonTokenizedStrategy__ZeroLockupDuration();
        assets = _mint(shares, receiver, lockupDuration);
    }

    function _mint(uint256 shares, address receiver, uint256 lockupDuration) internal returns (uint256 assets) {
        StrategyData storage S = _strategyStorage();
        if ((assets = _convertToAssets(S, shares, Math.Rounding.Ceil)) == 0) {
            revert ZeroAssets();
        }

        _deposit(assets, receiver, lockupDuration);
        return assets;
    }

    /**
     * @dev Internal function to handle loss protection for dragon principal
     * @param loss The amount of loss to protect against
     */
    function _handleDragonLossProtection(StrategyData storage S, uint256 loss) internal {
        // Can only burn up to available shares
        uint256 sharesBurned = Math.min(_convertToShares(S, loss, Math.Rounding.Floor), S.balances[S.dragonRouter]);

        if (sharesBurned > 0) {
            // Burn shares from dragon router
            _burn(S, S.dragonRouter, sharesBurned);
        }
    }

    /**
     * @notice Function for keepers to call to harvest and record all
     * profits accrued.
     *
     * @dev This will account for any gains/losses since the last report
     * and charge fees accordingly.
     *
     * Any profit over the fees charged will be immediately distributed to the dragon router     *
     * In case of a loss it will first attempt to offset the loss
     * with any remaining dragon router shares
     * order to protect dragon principal first and foremost.
     *
     * @return profit The notional amount of gain if any since the last
     * report in terms of `asset`.
     * @return loss The notional amount of loss if any since the last
     * report in terms of `asset`.
     */
    // solhint-disable-next-line code-complexity
    function report() external override nonReentrant onlyKeepers returns (uint256 profit, uint256 loss) {
        // Cache storage pointer since its used repeatedly.
        StrategyData storage S = _strategyStorage();

        uint256 newTotalAssets = IBaseStrategy(address(this)).harvestAndReport();
        uint256 oldTotalAssets = _totalAssets(S);
        address _dragonRouter = S.dragonRouter;

        if (newTotalAssets > oldTotalAssets) {
            unchecked {
                profit = newTotalAssets - oldTotalAssets;
            }
            _mint(S, _dragonRouter, _convertToShares(S, profit, Math.Rounding.Floor));
        } else {
            unchecked {
                loss = oldTotalAssets - newTotalAssets;
            }

            if (loss != 0) {
                // Handle loss protection
                _handleDragonLossProtection(S, loss);
            }
        }

        // Update the new total assets value
        S.totalAssets = newTotalAssets;
        S.lastReport = uint96(block.timestamp);

        emit Reported(
            profit,
            loss,
            0, // Protocol fees
            0 // Performance Fees
        );
    }

    /**
     * @notice Transfer '_amount` of shares from `msg.sender` to `to`.
     * @dev Dragon vault shares are not transferable
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `to` cannot be the address of the strategy.
     * - the caller must have a balance of at least `_amount`.
     *
     * @return . a boolean value indicating whether the operation succeeded.
     */
    function transfer(address, /*to*/ uint256 /*amount*/) external pure override returns (bool) {
        revert DragonTokenizedStrategy__VaultSharesNotTransferable();
    }

    /**
     * @notice `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * @dev
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `to` cannot be the address of the strategy.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     *
     * Emits a {Transfer} event.
     *
     * @return . a boolean value indicating whether the operation succeeded.
     */
    function transferFrom(address, /*from*/ address, /*to*/ uint256 /*amount*/) external pure override returns (bool) {
        revert DragonTokenizedStrategy__VaultSharesNotTransferable();
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        revert DragonTokenizedStrategy__VaultSharesNotTransferable();
    }

    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override {
        revert DragonTokenizedStrategy__VaultSharesNotTransferable();
    }
}
