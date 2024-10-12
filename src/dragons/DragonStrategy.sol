// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.25;

import { TokenizedStrategy, IBaseStrategy, Math, ERC20 } from "./TokenizedStrategy.sol";
import { IDragonModule } from "../interfaces/IDragonModule.sol";
import { VaultSharesNotTransferable, PerformanceFeeDisabled, MaxUnlockIsAlwaysZero, CantWithdrawLockedShares } from "src/errors.sol";

contract DragonStrategy is TokenizedStrategy {
    event NewLockupSet(address indexed user, uint256 indexed unlockTime, uint256 indexed lockedShares);

    constructor(address _dragonModule) TokenizedStrategy(_dragonModule) {}

    struct LockupInfo {
        uint256 unlockTime;
        uint256 lockedShares;
    }

    struct DragonStrategyStorageV0 {
        address dragonModule;
        // Mapping from user address to their lockup information
        mapping(address => LockupInfo) voluntaryLockups;
    }

    /// keccak256(abi.encode(uint256(keccak256("dragonmodule.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 public constant DRAGON_STRATEGY_STORAGE_LOCATION =
        0x5c9920b1e29ceee7a72a6a1d1314bf71f30523f55624a0abe6d215ad1e9bf100;

    function _dragonStrategyStorage() internal pure returns (DragonStrategyStorageV0 storage $) {
        bytes32 loc = DRAGON_STRATEGY_STORAGE_LOCATION;
        assembly {
            $.slot := loc
        }
    }

    /**
     * @notice Used to initialize storage for a newly deployed strategy.
     * @dev This should be called atomically whenever a new strategy is
     * deployed and can only be called once for each strategy.
     *
     * This will set all the default storage that must be set for a
     * strategy to function. Any changes can be made post deployment
     * through external calls from `management`.
     *
     * The function will also emit an event that off chain indexers can
     * look for to track any new deployments using this TokenizedStrategy.
     *
     * @param _asset Address of the underlying asset.
     * @param _name Name the strategy will use.
     * @param _management Address to set as the strategies `management`.
     * @param _keeper Address to set as strategies `keeper`.
     */
    function initialize(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _dragonModule
    ) external override {
        // Cache storage pointer.
        StrategyData storage S = _strategyStorage();
        DragonStrategyStorageV0 storage $ = _dragonStrategyStorage();
        // Make sure we aren't initialized.
        require(address(S.asset) == address(0), "initialized");

        // Set the dragon module address making sure it is not address(0)
        require(_dragonModule != address(0), "ZERO ADDRESS");
        $.dragonModule = _dragonModule;

        // Set the strategy's underlying asset.
        S.asset = ERC20(_asset);
        // Set the Strategy Tokens name.
        S.name = _name;
        // Set decimals based off the `asset`.
        S.decimals = ERC20(_asset).decimals();

        // Disable profit locking by default as all of it will be sent to the dragon router
        S.profitMaxUnlockTime = 0;
        // Set address to receive performance fees.
        // Can't be address(0) or we will be burning fees.
        // NOTE that fees are disabled by default.
        require(FACTORY != address(0), "ZERO ADDRESS");
        // Can't mint shares to its self because of profit locking.
        require(FACTORY != address(this), "self");
        S.performanceFeeRecipient = FACTORY;
        // Default to no performance fee.
        S.performanceFee = 0;
        // Set last report to this block.
        S.lastReport = uint96(block.timestamp);

        // Set the default management address. Can't be 0.
        require(_management != address(0), "ZERO ADDRESS");
        S.management = _management;
        // Set the keeper address
        S.keeper = _keeper;

        // Emit event to signal a new strategy has been initialized.
        emit NewTokenizedStrategy(address(this), _asset, API_VERSION);
    }

    /**
     * @dev Internal function to set or extend a user's lockup.
     * @param user The user's address.
     * @param lockupDuration The amount of time to set or extend a user's lockup.
     * @param totalSharesLocked The amount of shares to lock.
     */
    function _setOrExtendLockup(address user, uint256 lockupDuration, uint256 totalSharesLocked) internal {
        DragonStrategyStorageV0 storage $ = _dragonStrategyStorage();
        LockupInfo storage lockup = $.voluntaryLockups[user];
        uint256 currentTime = block.timestamp;

        if (lockup.unlockTime <= currentTime) {
            // Start a new lockup
            lockup.unlockTime = currentTime + lockupDuration;
            lockup.lockedShares = totalSharesLocked;
        } else {
            // Extend existing lockup
            lockup.unlockTime += lockupDuration;
            lockup.lockedShares = totalSharesLocked;
        }

        emit NewLockupSet(user, lockup.unlockTime, lockup.lockedShares);
    }

    /**
     * @dev Returns the amount of unlocked shares for a user.
     * @param user The user's address.
     * @return The amount of unlocked shares.
     */
    function _userUnlockedShares(
        StrategyData storage S,
        DragonStrategyStorageV0 storage $,
        address user
    ) internal view returns (uint256) {
        LockupInfo memory lockup = $.voluntaryLockups[user];

        if (block.timestamp >= lockup.unlockTime) {
            return _balanceOf(S, user);
        } else {
            return _balanceOf(S, user) - lockup.lockedShares;
        }
    }

    /**
     * @dev Returns the amount of unlocked shares for a user.
     * @param user The user's address.
     * @return The amount of unlocked shares.
     */
    function unlockedShares(address user) external view returns (uint256) {
        StrategyData storage S = _strategyStorage();
        DragonStrategyStorageV0 storage $ = _dragonStrategyStorage();
        return _userUnlockedShares(S, $, user);
    }

    /**
     * @dev Returns the unlock time for a user's locked shares.
     * @param user The user's address.
     * @return The unlock timestamp.
     */
    function getUnlockTime(address user) public view returns (uint256) {
        DragonStrategyStorageV0 storage $ = _dragonStrategyStorage();

        return $.voluntaryLockups[user].unlockTime;
    }

    /// @dev Internal implementation of {maxWithdraw}.
    function _maxWithdraw(
        StrategyData storage S,
        DragonStrategyStorageV0 storage $,
        address owner
    ) internal view returns (uint256 maxWithdraw_) {
        // Get the max the owner could withdraw currently.

        maxWithdraw_ = IBaseStrategy(address(this)).availableWithdrawLimit(owner);
        maxWithdraw_ = Math.min(
            _convertToAssets(S, _userUnlockedShares(S, $, owner), Math.Rounding.Floor),
            maxWithdraw_
        );
    }

    /**
     * @dev Override of _withdraw to enforce lockup period.
     */
    function _withdraw(
        StrategyData storage S,
        DragonStrategyStorageV0 storage $,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 maxLoss
    ) internal returns (uint256) {
        LockupInfo memory lockup = $.voluntaryLockups[owner];
        require(
            block.timestamp >= lockup.unlockTime || shares <= _balanceOf(S, owner) - lockup.lockedShares,
            "Shares are locked"
        );

        if (shares > _balanceOf(S, owner) - lockup.lockedShares) {
            revert CantWithdrawLockedShares();

            // Withdrawing unlocked shares
        }
        return super._withdraw(S, receiver, owner, assets, shares, maxLoss);
    }

    /**
     * @dev Override of _withdraw to enforce lockup period.
     */
    function _withdraw(
        StrategyData storage S,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 maxLoss
    ) internal override returns (uint256) {
        DragonStrategyStorageV0 storage $ = _dragonStrategyStorage();

        LockupInfo memory lockup = $.voluntaryLockups[owner];
        require(
            block.timestamp >= lockup.unlockTime || shares <= _balanceOf(S, owner) - lockup.lockedShares,
            "Shares are locked"
        );

        if (shares > _balanceOf(S, owner) - lockup.lockedShares) {
            revert CantWithdrawLockedShares();
        }
        super._withdraw(S, receiver, owner, assets, shares, maxLoss);
    }

    /// @dev Internal implementation of {maxRedeem}.
    function _maxRedeem(
        StrategyData storage S,
        DragonStrategyStorageV0 storage $,
        address owner
    ) internal view returns (uint256 maxRedeem_) {
        // Get the max the owner could withdraw currently.
        maxRedeem_ = IBaseStrategy(address(this)).availableWithdrawLimit(owner);
        maxRedeem_ = Math.min(
            // Can't redeem more than the balance.
            _convertToShares(S, maxRedeem_, Math.Rounding.Floor),
            _userUnlockedShares(S, $, owner)
        );
    }

    /**
     * @notice Total number of underlying assets that can be
     * withdrawn from the strategy by `owner`, where `owner`
     * corresponds to the msg.sender of a {redeem} call.
     *
     * @param owner The owner of the shares.
     * @return _maxWithdraw Max amount of `asset` that can be withdrawn.
     */
    function maxWithdraw(address owner) external view override returns (uint256) {
        return _maxWithdraw(_strategyStorage(), _dragonStrategyStorage(), owner);
    }

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxWithdraw(address owner, uint256 /*maxLoss*/) external view override returns (uint256) {
        return _maxWithdraw(_strategyStorage(), _dragonStrategyStorage(), owner);
    }

    /**
     * @notice Withdraws `assets` from `owners` shares and sends
     * the underlying tokens to `receiver`.
     * @dev This includes an added parameter to allow for losses.
     * @param assets The amount of underlying to withdraw.
     * @param receiver The address to receive `assets`.
     * @param owner The address whose shares are burnt.
     * @param maxLoss The amount of acceptable loss in Basis points.
     * @return shares The actual amount of shares burnt.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public override nonReentrant returns (uint256 shares) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();
        DragonStrategyStorageV0 storage $ = _dragonStrategyStorage();

        require(assets <= _maxWithdraw(S, $, owner), "ERC4626: withdraw more than max");
        // Check for rounding error or 0 value.
        require((shares = _convertToShares(S, assets, Math.Rounding.Ceil)) != 0, "ZERO_SHARES");

        // Withdraw and track the actual amount withdrawn for loss check.
        _withdraw(S, $, receiver, owner, assets, shares, maxLoss);
    }

    /**
     * @notice Total number of strategy shares that can be
     * redeemed from the strategy by `owner`, where `owner`
     * corresponds to the msg.sender of a {redeem} call.
     *
     * @param owner The owner of the shares.
     * @return _maxRedeem Max amount of shares that can be redeemed.
     */
    function maxRedeem(address owner) external view override returns (uint256) {
        return _maxRedeem(_strategyStorage(), _dragonStrategyStorage(), owner);
    }

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxRedeem(address owner, uint256 /*maxLoss*/) external view override returns (uint256) {
        return _maxRedeem(_strategyStorage(), _dragonStrategyStorage(), owner);
    }

    /**
     * @notice Redeems exactly `shares` from `owner` and
     * sends `assets` of underlying tokens to `receiver`.
     * @dev This includes an added parameter to allow for losses.
     * @param shares The amount of shares burnt.
     * @param receiver The address to receive `assets`.
     * @param owner The address whose shares are burnt.
     * @param maxLoss The amount of acceptable loss in Basis points.
     * @return . The actual amount of underlying withdrawn.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public override nonReentrant returns (uint256) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();
        DragonStrategyStorageV0 storage $ = _dragonStrategyStorage();
        require(shares <= _maxRedeem(S, $, owner), "ERC4626: redeem more than max");
        uint256 assets;
        // Check for rounding error or 0 value.
        require((assets = _convertToAssets(S, shares, Math.Rounding.Floor)) != 0, "ZERO_ASSETS");

        // We need to return the actual amount withdrawn in case of a loss.
        return _withdraw(S, $, receiver, owner, assets, shares, maxLoss);
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
    ) public returns (uint256 shares) {
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

        _setOrExtendLockup(receiver, lockupDuration, _balanceOf(S, receiver));

        return shares;
    }

    /**
     * @dev Mints exactly `shares` of strategy shares to `receiver` by depositing `assets` of underlying tokens.with a lockup period.
     * @param shares The amount of strategy shares mint.
     * @param receiver The address to receive the `shares`.
     * @param lockupDuration The duration of the lockup in seconds.
     * @return assets The actual amount of asset deposited.
     */
    function mintWithLockup(uint256 shares, address receiver, uint256 lockupDuration) public returns (uint256 assets) {
        require(lockupDuration > 0, "Lockup duration must be greater than 0");
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();

        // Checking max mint will also check if shutdown.
        require(shares <= _maxMint(S, receiver), "ERC4626: mint more than max");
        // Check for rounding error.
        require((assets = _convertToAssets(S, shares, Math.Rounding.Ceil)) != 0, "ZERO_ASSETS");

        _deposit(S, receiver, assets, shares);

        _setOrExtendLockup(receiver, lockupDuration, _balanceOf(S, receiver));

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
        DragonStrategyStorageV0 storage $ = _dragonStrategyStorage();
        // Tell the strategy to report the real total assets it has.
        // It should do all reward selling and redepositing now and
        // account for deployed and loose `asset` so we can accurately
        // account for all funds including those potentially airdropped
        // and then have any profits immediately locked.
        uint256 newTotalAssets = IBaseStrategy(address(this)).harvestAndReport();

        uint256 oldTotalAssets = _totalAssets(S);

        // Get the amount of shares we need to burn from previous reports.
        uint256 sharesToBurn = _unlockedShares(S);

        // Initialize variables needed throughout.
        uint256 sharesToLock;
        uint256 totalProfitShares;
        address dragonRouter = IDragonModule($.dragonModule).getDragonRouter();
        // Calculate profit/loss.
        if (newTotalAssets > oldTotalAssets) {
            // We have a profit.
            unchecked {
                profit = newTotalAssets - oldTotalAssets;
            }

            // We need to get the equivalent amount of shares
            // at the current PPS before any minting or burning.
            sharesToLock = _convertToShares(S, profit, Math.Rounding.Floor);

            // all of the profit is sent to the dragon router
            totalProfitShares = sharesToLock;

            _mint(S, IDragonModule(FACTORY).getDragonRouter(), totalProfitShares);
        } else {
            // Expect we have a loss.
            unchecked {
                loss = oldTotalAssets - newTotalAssets;
            }

            // Check in case `else` was due to being equal.
            if (loss != 0) {
                // We will try and burn the dragon router shares first before touching the dragon's shares.
                sharesToBurn = Math.min(
                    // Cannot burn more than we have.
                    S.balances[address(dragonRouter)],
                    // Try and burn both the shares already unlocked and the amount for the loss.
                    _convertToShares(S, loss, Math.Rounding.Floor) + sharesToBurn
                );
            }

            // Check if there is anything to burn.
            if (sharesToBurn != 0) {
                _burn(S, address(this), sharesToBurn);
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
     * @notice Disables the performance fee to be charged on reported gains.
     * @dev Can only be called by the current `management`.
     *
     * Denominated in Basis Points. So 100% == 10_000.
     * Cannot set greater than to MAX_FEE.
     *
     */
    function setPerformanceFee(uint16 /*_performanceFee*/) external override onlyManagement {
        revert PerformanceFeeDisabled();
    }

    /**
     * @notice Disables a new address to receive performance fees.
     * @dev Can only be called by the current `management`.
     *
     * Cannot set to address(0).
     *
     */
    function setPerformanceFeeRecipient(address /*_performanceFeeRecipient*/) external override onlyManagement {
        revert PerformanceFeeDisabled();
    }

    /**
     * @notice Disables setting the time for profits to be unlocked over.
     * @dev Can only be called by the current `management`.
     *
     * Denominated in seconds and cannot be greater than 1 year.
     *
     * NOTE: Setting to 0 will cause all currently locked profit
     * to be unlocked instantly and should be done with care.
     *
     * `profitMaxUnlockTime` is stored as a uint32 for packing but can
     * be passed in as uint256 for simplicity.
     *
     */
    function setProfitMaxUnlockTime(uint256 /*_profitMaxUnlockTime*/) external override onlyManagement {
        revert MaxUnlockIsAlwaysZero();
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
    function transfer(address /*to*/, uint256 /*amount*/) external override returns (bool) {
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
    function transferFrom(address /*from*/, address /*to*/, uint256 /*amount*/) external override returns (bool) {
        revert VaultSharesNotTransferable();
    }

    /**
     * @notice Returns the symbol of the strategies token.
     * @dev Will be 'ys + asset symbol'.
     * @return . The symbol the strategy is using for its tokens.
     */
    function symbol() external view override returns (string memory) {
        return string(abi.encodePacked("dgn", _strategyStorage().asset.symbol()));
    }

    /**
     * @notice Returns the domain separator used in the encoding of the signature
     * for {permit}, as defined by {EIP712}.
     *
     * @return . The domain separator that will be used for any {permit} calls.
     */
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256("Dragon Vault"),
                    keccak256(bytes(API_VERSION)),
                    block.chainid,
                    address(this)
                )
            );
    }
}
