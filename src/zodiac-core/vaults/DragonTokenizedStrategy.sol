// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { TokenizedStrategy, IBaseStrategy, Math } from "src/zodiac-core/vaults/TokenizedStrategy.sol";
import { IDragonTokenizedStrategy } from "src/zodiac-core/interfaces/IDragonTokenizedStrategy.sol";
import { Unauthorized, TokenizedStrategy__NotOperator, DragonTokenizedStrategy__NoOperation, DragonTokenizedStrategy__InvalidReceiver, DragonTokenizedStrategy__VaultSharesNotTransferable, DragonTokenizedStrategy__ZeroLockupDuration, DragonTokenizedStrategy__InsufficientLockupDuration, DragonTokenizedStrategy__SharesStillLocked, DragonTokenizedStrategy__InvalidLockupDuration, DragonTokenizedStrategy__InvalidRageQuitCooldownPeriod, DragonTokenizedStrategy__RageQuitInProgress, DragonTokenizedStrategy__StrategyInShutdown, DragonTokenizedStrategy__NoSharesToRageQuit, DragonTokenizedStrategy__SharesAlreadyUnlocked, DragonTokenizedStrategy__DepositMoreThanMax, DragonTokenizedStrategy__MintMoreThanMax, DragonTokenizedStrategy__WithdrawMoreThanMax, DragonTokenizedStrategy__RedeemMoreThanMax, ZeroShares, ZeroAssets, DragonTokenizedStrategy__ReceiverHasExistingShares } from "src/errors.sol";
import { IERC4626Payable } from "src/zodiac-core/interfaces/IERC4626Payable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { ITokenizedStrategy } from "src/zodiac-core/interfaces/ITokenizedStrategy.sol";

contract DragonTokenizedStrategy is IDragonTokenizedStrategy, TokenizedStrategy {
    // DragonTokenizedStrategy storage slot
    bytes32 internal constant DRAGON_TOKENIZED_STRATEGY_STORAGE = keccak256("DragonTokenizedStrategy.storage");

    modifier onlyOperatorIfDragonMode() {
        DragonTokenizedStrategyStorage storage S = _dragonTokenizedStrategyStorage();
        if (S.isDragonOnly && msg.sender != super._strategyStorage().operator) revert TokenizedStrategy__NotOperator();
        _;
    }

    modifier validateArgsForLockupFunctions(address receiver, uint256 lockupDuration) {
        DragonTokenizedStrategyStorage storage S = _dragonTokenizedStrategyStorage();
        if (lockupDuration == 0) revert DragonTokenizedStrategy__ZeroLockupDuration();
        if (!S.isDragonOnly && receiver != msg.sender) revert DragonTokenizedStrategy__InvalidReceiver();
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
    ) external override(TokenizedStrategy, ITokenizedStrategy) {
        // set dragon only to true
        _dragonTokenizedStrategyStorage().isDragonOnly = true;
        __TokenizedStrategy_init(_asset, _name, _operator, _management, _keeper, _dragonRouter, _regenGovernance);
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function toggleDragonMode(bool enabled) external override onlyOperator {
        DragonTokenizedStrategyStorage storage S = _dragonTokenizedStrategyStorage();
        if (enabled == S.isDragonOnly) revert DragonTokenizedStrategy__NoOperation();
        S.isDragonOnly = enabled;
        emit DragonModeToggled(enabled);
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function setLockupDuration(uint256 _lockupDuration) external override onlyRegenGovernance {
        if (_lockupDuration < RANGE_MINIMUM_LOCKUP_DURATION || _lockupDuration > RANGE_MAXIMUM_LOCKUP_DURATION) {
            revert DragonTokenizedStrategy__InvalidLockupDuration();
        }
        super._strategyStorage().minimumLockupDuration = _lockupDuration;
        emit LockupDurationSet(_lockupDuration);
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function setRageQuitCooldownPeriod(uint256 _rageQuitCooldownPeriod) external override onlyRegenGovernance {
        if (
            _rageQuitCooldownPeriod < RANGE_MINIMUM_RAGE_QUIT_COOLDOWN_PERIOD ||
            _rageQuitCooldownPeriod > RANGE_MAXIMUM_RAGE_QUIT_COOLDOWN_PERIOD
        ) revert DragonTokenizedStrategy__InvalidRageQuitCooldownPeriod();
        super._strategyStorage().rageQuitCooldownPeriod = _rageQuitCooldownPeriod;
        emit RageQuitCooldownPeriodSet(_rageQuitCooldownPeriod);
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function initiateRageQuit() external {
        StrategyData storage S = super._strategyStorage();
        LockupInfo storage lockup = S.voluntaryLockups[msg.sender];

        if (_balanceOf(S, msg.sender) == 0) revert DragonTokenizedStrategy__NoSharesToRageQuit();
        if (block.timestamp >= lockup.unlockTime) revert DragonTokenizedStrategy__SharesAlreadyUnlocked();
        if (lockup.isRageQuit) revert DragonTokenizedStrategy__RageQuitInProgress();

        // Use the minimum of current unlock time and rage quit period
        uint256 rageQuitUnlockTime = block.timestamp + super._strategyStorage().rageQuitCooldownPeriod;
        lockup.unlockTime = lockup.unlockTime < rageQuitUnlockTime ? lockup.unlockTime : rageQuitUnlockTime;
        lockup.lockupTime = block.timestamp; // Set the starting point for gradual unlocking
        lockup.isRageQuit = true;

        emit RageQuitInitiated(msg.sender, lockup.unlockTime);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function deposit(
        uint256 assets,
        address receiver
    ) external payable override(TokenizedStrategy, IERC4626Payable) onlyOperatorIfDragonMode returns (uint256 shares) {
        shares = _depositWithLockup(assets, receiver, 0);
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function depositWithLockup(
        uint256 assets,
        address receiver,
        uint256 lockupDuration
    )
        external
        payable
        override
        onlyOperatorIfDragonMode
        validateArgsForLockupFunctions(receiver, lockupDuration)
        returns (uint256 shares)
    {
        shares = _depositWithLockup(assets, receiver, lockupDuration);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function mint(
        uint256 shares,
        address receiver
    ) external payable override(TokenizedStrategy, IERC4626Payable) onlyOperatorIfDragonMode returns (uint256 assets) {
        assets = _mintWithLockup(shares, receiver, 0);
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function mintWithLockup(
        uint256 shares,
        address receiver,
        uint256 lockupDuration
    )
        external
        payable
        override
        onlyOperatorIfDragonMode
        validateArgsForLockupFunctions(receiver, lockupDuration)
        returns (uint256 assets)
    {
        assets = _mintWithLockup(shares, receiver, lockupDuration);
    }

    function minimumLockupDuration() external view returns (uint256) {
        return super._strategyStorage().minimumLockupDuration;
    }

    function rageQuitCooldownPeriod() external view returns (uint256) {
        return super._strategyStorage().rageQuitCooldownPeriod;
    }

    function regenGovernance() external view returns (address) {
        return super._strategyStorage().REGEN_GOVERNANCE;
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function isDragonOnly() external view returns (bool) {
        DragonTokenizedStrategyStorage storage S = _dragonTokenizedStrategyStorage();
        return S.isDragonOnly;
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function unlockedShares(address user) external view returns (uint256) {
        StrategyData storage S = super._strategyStorage();
        return _userUnlockedShares(S, user);
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function getUnlockTime(address user) external view returns (uint256) {
        return super._strategyStorage().voluntaryLockups[user].unlockTime;
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function getRemainingCooldown(address user) external view returns (uint256 remainingTime) {
        uint256 unlockTime = super._strategyStorage().voluntaryLockups[user].unlockTime;
        if (unlockTime <= block.timestamp) {
            return 0;
        }
        return unlockTime - block.timestamp;
    }

    /**
     * @inheritdoc IDragonTokenizedStrategy
     */
    function getUserLockupInfo(
        address user
    )
        external
        view
        override
        returns (
            uint256 unlockTime,
            uint256 lockedShares,
            bool isRageQuit,
            uint256 totalShares,
            uint256 withdrawableShares
        )
    {
        StrategyData storage S = super._strategyStorage();
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
     * @inheritdoc IERC4626Payable
     */
    function maxWithdraw(address _owner) external view override(TokenizedStrategy, IERC4626Payable) returns (uint256) {
        return _maxWithdraw(super._strategyStorage(), _owner);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function maxWithdraw(
        address _owner,
        uint256 /*maxLoss*/
    ) external view override(TokenizedStrategy, ITokenizedStrategy) returns (uint256) {
        return _maxWithdraw(super._strategyStorage(), _owner);
    }

    /**
     * @inheritdoc IERC20
     */
    function transfer(
        address,
        /*to*/ uint256 /*amount*/
    ) external pure override(TokenizedStrategy, IERC20) returns (bool) {
        revert DragonTokenizedStrategy__VaultSharesNotTransferable();
    }

    /**
     * @inheritdoc IERC20
     */
    function transferFrom(
        address,
        /*from*/ address,
        /*to*/ uint256 /*amount*/
    ) external pure override(TokenizedStrategy, IERC20) returns (bool) {
        revert DragonTokenizedStrategy__VaultSharesNotTransferable();
    }

    /**
     * @inheritdoc TokenizedStrategy
     */
    function permit(
        address,
        address,
        uint256,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) external pure override(TokenizedStrategy, IERC20Permit) {
        revert DragonTokenizedStrategy__VaultSharesNotTransferable();
    }

    /**
     * @inheritdoc IERC20
     */
    function approve(address, uint256) external pure override(TokenizedStrategy, IERC20) returns (bool) {
        revert DragonTokenizedStrategy__VaultSharesNotTransferable();
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address _owner,
        uint256 maxLoss
    ) public virtual override(TokenizedStrategy, ITokenizedStrategy) nonReentrant returns (uint256 shares) {
        // Get the storage slot for all following calls.
        StrategyData storage S = super._strategyStorage();
        LockupInfo storage lockup = S.voluntaryLockups[_owner];
        if (block.timestamp < lockup.unlockTime && !lockup.isRageQuit) {
            revert DragonTokenizedStrategy__SharesStillLocked();
        }
        if (assets > _maxWithdraw(S, _owner)) revert DragonTokenizedStrategy__WithdrawMoreThanMax();

        // Check for rounding error or 0 value.
        //slither-disable-next-line incorrect-equality
        if ((shares = _convertToShares(S, assets, Math.Rounding.Ceil)) == 0) {
            revert ZeroShares();
        }

        // Withdraw and track the actual amount withdrawn for loss check.
        _withdraw(S, receiver, _owner, assets, shares, maxLoss);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function redeem(
        uint256 shares,
        address receiver,
        address _owner,
        uint256 maxLoss
    ) public virtual override(TokenizedStrategy, ITokenizedStrategy) nonReentrant returns (uint256) {
        // Get the storage slot for all following calls.
        StrategyData storage S = super._strategyStorage();
        LockupInfo storage lockup = S.voluntaryLockups[_owner];

        if (shares > _maxRedeem(S, _owner)) revert DragonTokenizedStrategy__RedeemMoreThanMax();
        if (block.timestamp < lockup.unlockTime && !lockup.isRageQuit) {
            revert DragonTokenizedStrategy__SharesStillLocked();
        }

        uint256 assets = 0;
        // Check for rounding error or 0 value.
        //slither-disable-next-line incorrect-equality
        if ((assets = _convertToAssets(S, shares, Math.Rounding.Floor)) == 0) {
            revert ZeroAssets();
        }

        // We need to return the actual amount withdrawn in case of a loss.
        return _withdraw(S, receiver, _owner, assets, shares, maxLoss);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function report()
        public
        virtual
        override(TokenizedStrategy, ITokenizedStrategy)
        nonReentrant
        onlyKeepers
        returns (uint256 profit, uint256 loss)
    {
        // Cache storage pointer since its used repeatedly.
        StrategyData storage S = super._strategyStorage();

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
    ) internal {
        LockupInfo storage lockup = S.voluntaryLockups[user];
        uint256 currentTime = block.timestamp;

        // NOTE: if there is no lockup, and the lockup duration not 0 then set a new lockup
        if (lockup.unlockTime <= currentTime) {
            if (lockupDuration == 0) return;
            // NOTE: enforce minimum lockup duration for new lockups
            if (lockupDuration < super._strategyStorage().minimumLockupDuration) {
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
                if (newUnlockTime < currentTime + super._strategyStorage().minimumLockupDuration) {
                    revert DragonTokenizedStrategy__InsufficientLockupDuration();
                }

                lockup.unlockTime = newUnlockTime;
            }
        }

        emit NewLockupSet(user, lockup.lockupTime, lockup.unlockTime, lockup.lockedShares);
    }

    function _depositWithLockup(
        uint256 assets,
        address receiver,
        uint256 lockupDuration
    ) internal virtual returns (uint256 shares) {
        StrategyData storage S = super._strategyStorage();
        require(!S.shutdown, DragonTokenizedStrategy__StrategyInShutdown());

        require(receiver != S.dragonRouter, Unauthorized());
        require(!S.voluntaryLockups[receiver].isRageQuit, DragonTokenizedStrategy__RageQuitInProgress());
        require(
            _balanceOf(S, receiver) == 0 ||
                IBaseStrategy(address(this)).target() == address(receiver) ||
                lockupDuration == 0,
            DragonTokenizedStrategy__ReceiverHasExistingShares()
        );
        //slither-disable-next-line incorrect-equality
        assets = type(uint256).max == assets ? S.asset.balanceOf(msg.sender) : assets;

        require((shares = _convertToShares(S, assets, Math.Rounding.Floor)) != 0, ZeroShares());
        require(assets < _maxDeposit(S, receiver), DragonTokenizedStrategy__DepositMoreThanMax());
        require(shares < _maxMint(S, receiver), DragonTokenizedStrategy__MintMoreThanMax());

        _deposit(S, receiver, assets, shares);
        _setOrExtendLockup(S, receiver, lockupDuration, _balanceOf(S, receiver));
    }

    function _mintWithLockup(
        uint256 shares,
        address receiver,
        uint256 lockupDuration
    ) internal virtual returns (uint256 assets) {
        StrategyData storage S = super._strategyStorage();
        require((assets = _convertToAssets(S, shares, Math.Rounding.Ceil)) != 0, ZeroAssets());
        _depositWithLockup(assets, receiver, lockupDuration);
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
     * @dev Returns the amount of unlocked shares for a user.
     * @param user The user's address.
     * @return The amount of unlocked shares.
     */
    function _userUnlockedShares(StrategyData storage S, address user) internal view virtual returns (uint256) {
        LockupInfo memory lockup = super._strategyStorage().voluntaryLockups[user];
        uint256 balance = _balanceOf(S, user);

        if (block.timestamp >= lockup.unlockTime) {
            return balance;
        } else if (lockup.isRageQuit) {
            // Calculate unlocked portion based on time elapsed
            uint256 timeElapsed = block.timestamp - lockup.lockupTime;
            uint256 unlockedPortion = (timeElapsed * lockup.lockedShares) / (lockup.unlockTime - lockup.lockupTime);
            uint256 sharesPreviouslyWithdrawn = lockup.lockedShares - balance;
            uint256 maxWithdrawalAmount = unlockedPortion - sharesPreviouslyWithdrawn;
            return Math.min(maxWithdrawalAmount, balance);
        } else {
            return 0;
        }
    }

    /// @dev Internal implementation of {maxWithdraw}.
    function _maxWithdraw(
        StrategyData storage S,
        address _owner
    ) internal view virtual override returns (uint256 maxWithdraw_) {
        // Get the max the owner could withdraw currently.

        maxWithdraw_ = IBaseStrategy(address(this)).availableWithdrawLimit(_owner);
        maxWithdraw_ = Math.min(_convertToAssets(S, _userUnlockedShares(S, _owner), Math.Rounding.Floor), maxWithdraw_);
    }

    /// @dev Internal implementation of {maxRedeem}.
    function _maxRedeem(StrategyData storage S, address _owner) internal view override returns (uint256 maxRedeem_) {
        // Get the max the owner could withdraw currently.
        maxRedeem_ = IBaseStrategy(address(this)).availableWithdrawLimit(_owner);
        if (maxRedeem_ == type(uint256).max) {
            maxRedeem_ = _userUnlockedShares(S, _owner);
        } else {
            maxRedeem_ = Math.min(
                // Can't redeem more than the balance.
                _convertToShares(S, maxRedeem_, Math.Rounding.Floor),
                _userUnlockedShares(S, _owner)
            );
        }
    }

    function _dragonTokenizedStrategyStorage() internal pure returns (DragonTokenizedStrategyStorage storage S) {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = DRAGON_TOKENIZED_STRATEGY_STORAGE;
        assembly ("memory-safe") {
            S.slot := slot
        }
    }
}
