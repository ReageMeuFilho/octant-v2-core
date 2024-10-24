// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.25;

import { TokenizedStrategy, IBaseStrategy, Math, ERC20 } from "./TokenizedStrategy.sol";
import { IDragonModule } from "../interfaces/IDragonModule.sol";
import { VaultSharesNotTransferable, MaxUnlockIsAlwaysZero, CantWithdrawLockedShares, ZeroLockupDuration, InsufficientLockupDuration, SharesStillLocked } from "src/errors.sol";

contract DragonTokenizedStrategy is TokenizedStrategy {
    event NewLockupSet(address indexed user, uint256 indexed unlockTime, uint256 indexed lockedShares);
    event RageQuitInitiated(address indexed user, uint256 indexed unlockTime);

    // Minimum lockup duration of 3 months (in seconds)
    uint256 private constant MINIMUM_LOCKUP_DURATION = 90 days;

    function initialize(
        address _asset,
        string memory _name,
        address _owner,
        address _management,
        address _keeper,
        address _dragonRouter
    ) external {
        __TokenizedStrategy_init(_asset, _name, _owner, _management, _keeper, _dragonRouter);
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
        if (lockup.unlockTime <= currentTime && lockupDuration > 0) {
            lockup.unlockTime = currentTime + lockupDuration;
            // NOTE: enforce minimum lockup duration for new lockups
            if (lockupDuration <= MINIMUM_LOCKUP_DURATION) revert InsufficientLockupDuration();

            lockup.lockedShares = totalSharesLocked;
        } else {
            // NOTE: update the locked shares
            lockup.lockedShares = totalSharesLocked;
            // NOTE: if there is a lock up and the lockUpDuration is greater than 0 then extend the lockup ensuring it's more than minimum lockup duration
            if (lockupDuration > 0) {
                // Extend existing lockup
                uint256 newUnlockTime = lockup.unlockTime + lockupDuration;
                // Ensure the new unlock time is at least 3 months in the future
                if (newUnlockTime < currentTime + MINIMUM_LOCKUP_DURATION) revert InsufficientLockupDuration();

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
            uint256 timeElapsed = block.timestamp - (lockup.unlockTime - MINIMUM_LOCKUP_DURATION);
            uint256 unlockedPortion = (timeElapsed * lockup.lockedShares) / MINIMUM_LOCKUP_DURATION;
            return Math.min(unlockedPortion, balance);
        } else {
            return balance - lockup.lockedShares;
        }
    }

    /**
     * @dev Returns the amount of unlocked shares for a user.
     * @param user The user's address.
     * @return The amount of unlocked shares.
     */
    function unlockedShares(address user) public view returns (uint256) {
        StrategyData storage S = _strategyStorage();
        return _userUnlockedShares(S, user);
    }

    /**
     * @dev Returns the unlock time for a user's locked shares.
     * @param user The user's address.
     * @return The unlock timestamp.
     */
    function getUnlockTime(address user) public view returns (uint256) {
        return _strategyStorage().voluntaryLockups[user].unlockTime;
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

    /// @dev Internal implementation of {maxWithdraw}.
    function _maxWithdraw(
        StrategyData storage S,
        address _owner
    ) internal view override returns (uint256 maxWithdraw_) {
        // Get the max the owner could withdraw currently.

        maxWithdraw_ = IBaseStrategy(address(this)).availableWithdrawLimit(_owner);
        maxWithdraw_ = Math.min(_convertToAssets(S, _userUnlockedShares(S, _owner), Math.Rounding.Floor), maxWithdraw_);
    }

    /**
     * @dev Override of _withdraw to enforce lockup period.
     */
    function _withdraw(
        StrategyData storage S,
        address receiver,
        address _owner,
        uint256 assets,
        uint256 shares,
        uint256 maxLoss
    ) internal override returns (uint256) {
        LockupInfo memory lockup = S.voluntaryLockups[_owner];

        if (block.timestamp < lockup.unlockTime) revert SharesStillLocked();

        return super._withdraw(S, receiver, _owner, assets, shares, maxLoss);
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

        require(assets <= _maxWithdraw(S, _owner), "ERC4626: withdraw more than max");
        // Check for rounding error or 0 value.
        require((shares = _convertToShares(S, assets, Math.Rounding.Ceil)) != 0, "ZERO_SHARES");

        // Withdraw and track the actual amount withdrawn for loss check.
        _withdraw(S, receiver, _owner, assets, shares, maxLoss);
    }

    /**
     * @notice Total number of strategy shares that can be
     * redeemed from the strategy by `owner`, where `owner`
     * corresponds to the msg.sender of a {redeem} call.
     *
     * @param _owner The owner of the shares.
     * @return _maxRedeem Max amount of shares that can be redeemed.
     */
    function maxRedeem(address _owner) external view override returns (uint256) {
        return _maxRedeem(_strategyStorage(), _owner);
    }

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxRedeem(address _owner, uint256 /*maxLoss*/) external view override returns (uint256) {
        return _maxRedeem(_strategyStorage(), _owner);
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
        require(shares <= _maxRedeem(S, _owner), "ERC4626: redeem more than max");
        uint256 assets;
        // Check for rounding error or 0 value.
        require((assets = _convertToAssets(S, shares, Math.Rounding.Floor)) != 0, "ZERO_ASSETS");

        // We need to return the actual amount withdrawn in case of a loss.
        return _withdraw(S, receiver, _owner, assets, shares, maxLoss);
    }

    /**
     * @notice Mints `shares` of strategy shares to `receiver` by
     * depositing exactly `assets` of underlying tokens.
     * @param assets The amount of underlying to deposit in.
     * @param receiver The address to receive the `shares`.
     * @return shares The actual amount of shares issued.
     */
    function deposit(
        uint256 assets,
        address receiver
    ) external payable override nonReentrant onlyOwner returns (uint256 shares) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();

        // Deposit full balance if using max uint.
        if (assets == type(uint256).max) {
            assets = S.asset.balanceOf(msg.sender);
        }

        // Checking max deposit will also check if shutdown.
        require(assets <= _maxDeposit(S, receiver), "ERC4626: deposit more than max");
        // Check for rounding error.
        require((shares = _convertToShares(S, assets, Math.Rounding.Floor)) != 0, "ZERO_SHARES");

        _deposit(S, receiver, assets, shares);
        _setOrExtendLockup(S, receiver, 0, _balanceOf(S, receiver));
    }

    /**
     * @notice Mints exactly `shares` of strategy shares to
     * `receiver` by depositing `assets` of underlying tokens.
     * @param shares The amount of strategy shares mint.
     * @param receiver The address to receive the `shares`.
     * @return assets The actual amount of asset deposited.
     */
    function mint(
        uint256 shares,
        address receiver
    ) external payable override nonReentrant onlyOwner returns (uint256 assets) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();

        // Checking max mint will also check if shutdown.
        require(shares <= _maxMint(S, receiver), "ERC4626: mint more than max");
        // Check for rounding error.
        require((assets = _convertToAssets(S, shares, Math.Rounding.Ceil)) != 0, "ZERO_ASSETS");

        _deposit(S, receiver, assets, shares);
        _setOrExtendLockup(S, receiver, 0, _balanceOf(S, receiver));
    }

    /**
     * @dev Mints `shares` of strategy shares to `receiver` by depositing exactly `assets` of underlying tokens with a lock up
     * @param assets The amount of assets to deposit.
     * @param receiver The receiver of the shares.
     * @param lockupDuration The duration of the lockup in seconds.
     * @return shares The amount of shares minted.
     */
    function depositWithLockup(
        uint256 assets,
        address receiver,
        uint256 lockupDuration
    ) public onlyOwner returns (uint256 shares) {
        require(lockupDuration > 0, "Lockup duration must be greater than 0");
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();

        // Deposit full balance if using max uint.
        if (assets == type(uint256).max) {
            assets = S.asset.balanceOf(msg.sender);
        }

        // Checking max deposit will also check if shutdown.
        require(assets <= _maxDeposit(S, receiver), "ERC4626: deposit more than max");
        // Check for rounding error.
        require((shares = _convertToShares(S, assets, Math.Rounding.Floor)) != 0, "ZERO_SHARES");

        _deposit(S, receiver, assets, shares);

        _setOrExtendLockup(S, receiver, lockupDuration, _balanceOf(S, receiver));

        return shares;
    }

    /**
     * @notice Initiates a rage quit, allowing gradual withdrawal over 3 months
     * @dev Sets a 3-month lockup and enables proportional withdrawals
     */
    function initiateRageQuit() external {
        StrategyData storage S = _strategyStorage();
        LockupInfo storage lockup = S.voluntaryLockups[msg.sender];

        // Can't rage quit if no shares or already in rage quit
        require(_balanceOf(S, msg.sender) > 0, "No shares to rage quit");
        require(!lockup.isRageQuit, "Already in rage quit");

        // Can't rage quit if shares are already unlocked
        require(block.timestamp < lockup.unlockTime || lockup.unlockTime == 0, "Shares already unlocked");

        // Set 3-month lockup
        lockup.unlockTime = block.timestamp + MINIMUM_LOCKUP_DURATION;
        lockup.lockedShares = _balanceOf(S, msg.sender);
        lockup.isRageQuit = true;

        emit RageQuitInitiated(msg.sender, lockup.unlockTime);
    }

    /**
     * @dev Mints exactly `shares` of strategy shares to `receiver` by depositing `assets` of underlying tokens.with a lockup period.
     * @param shares The amount of strategy shares mint.
     * @param receiver The address to receive the `shares`.
     * @param lockupDuration The duration of the lockup in seconds.
     * @return assets The actual amount of asset deposited.
     */
    function mintWithLockup(
        uint256 shares,
        address receiver,
        uint256 lockupDuration
    ) public onlyOwner returns (uint256 assets) {
        require(lockupDuration > 0, "Lockup duration must be greater than 0");
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();

        // Checking max mint will also check if shutdown.
        require(shares <= _maxMint(S, receiver), "ERC4626: mint more than max");
        // Check for rounding error.
        require((assets = _convertToAssets(S, shares, Math.Rounding.Ceil)) != 0, "ZERO_ASSETS");

        _deposit(S, receiver, assets, shares);

        _setOrExtendLockup(S, receiver, lockupDuration, _balanceOf(S, receiver));

        return assets;
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

        // Tell the strategy to report the real total assets it has.
        // It should do all reward selling and redepositing now and
        // account for deployed and loose `asset` so we can accurately
        // account for all funds including those potentially airdropped
        // and then have any profits immediately locked.
        uint256 newTotalAssets = IBaseStrategy(address(this)).harvestAndReport();

        uint256 oldTotalAssets = _totalAssets(S);

        address _dragonRouter = S.dragonRouter;
        // Calculate profit/loss.
        if (newTotalAssets > oldTotalAssets) {
            // We have a profit.
            unchecked {
                profit = newTotalAssets - oldTotalAssets;
            }

            _deposit(S, _dragonRouter, profit, _convertToShares(S, profit, Math.Rounding.Floor));
        } else {
            // Expect we have a loss.
            unchecked {
                loss = oldTotalAssets - newTotalAssets;
            }

            uint256 sharesToBurn;
            // Check in case `else` was due to being equal.
            if (loss != 0) {
                // We will try and burn the dragon router shares first before touching the dragon's shares.
                sharesToBurn = Math.min(
                    // Cannot burn more than we have.
                    S.balances[_dragonRouter],
                    // Try and burn both the shares already unlocked and the amount for the loss.
                    _convertToShares(S, loss, Math.Rounding.Floor)
                );
            }

            // Check if there is anything to burn.
            if (sharesToBurn != 0) {
                _burn(S, _dragonRouter, sharesToBurn);
            }
        }
        // Update the new total assets value.
        S.totalAssets = newTotalAssets;
        S.lastReport = uint96(block.timestamp);

        // Emit event with info
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
    function transfer(address, /*to*/ uint256 /*amount*/ ) external pure override returns (bool) {
        revert VaultSharesNotTransferable();
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
    function transferFrom(address, /*from*/ address, /*to*/ uint256 /*amount*/ ) external pure override returns (bool) {
        revert VaultSharesNotTransferable();
    }
}
