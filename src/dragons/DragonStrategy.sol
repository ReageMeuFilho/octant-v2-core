// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.25;

import { TokenizedStrategy, IBaseStrategy, Math, ERC20 } from "./TokenizedStrategy.sol";
import { IDragonModule } from "../interfaces/IDragonModule.sol";
import { VaultSharesNotTransferable, PerformanceFeeIsAlwaysZero, PerformanceFeeDisabled, MaxUnlockIsAlwaysZero } from "src/errors.sol";

contract DragonStrategy is TokenizedStrategy {
    constructor(address _dragonModule) TokenizedStrategy(_dragonModule) {}

    struct LockupInfo {
        uint256 amount;
        uint256 unlockTime;
    }

    struct DragonStrategyStorageV0 {
        address dragonModule;
        // Mapping from user address to their lockup information
        mapping(address => LockupInfo) lockups;
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
     * @notice Function for keepers to call to harvest and record all
     * profits accrued.
     *
     * @dev This will account for any gains/losses since the last report
     * and charge fees accordingly.
     *
     * Any profit over the fees charged will be immediately locked
     * so there is no change in PricePerShare. Then slowly unlocked
     * over the `maxProfitUnlockTime` each second based on the
     * calculated `profitUnlockingRate`.
     *
     * In case of a loss it will first attempt to offset the loss
     * with any remaining locked shares from the last report in
     * order to reduce any negative impact to PPS.
     *
     * Will then recalculate the new time to unlock profits over and the
     * rate based on a weighted average of any remaining time from the
     * last report and the new amount of shares to be locked.
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
     * @param _performanceFee New performance fee.
     */
    function setPerformanceFee(uint16 _performanceFee) external override onlyManagement {
        revert PerformanceFeeDisabled();
    }

    /**
     * @notice Disables a new address to receive performance fees.
     * @dev Can only be called by the current `management`.
     *
     * Cannot set to address(0).
     *
     * @param _performanceFeeRecipient New address to set `management` to.
     */
    function setPerformanceFeeRecipient(address _performanceFeeRecipient) external override onlyManagement {
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
     * @param _profitMaxUnlockTime New `profitMaxUnlockTime`.
     */
    function setProfitMaxUnlockTime(uint256 _profitMaxUnlockTime) external override onlyManagement {
        revert MaxUnlockIsAlwaysZero();
    }

    /**
     * @notice Transfer '_amount` of shares from `msg.sender` to `to`.
     * @dev
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `to` cannot be the address of the strategy.
     * - the caller must have a balance of at least `_amount`.
     *
     * @param to The address shares will be transferred to.
     * @param amount The amount of shares to be transferred from sender.
     * @return . a boolean value indicating whether the operation succeeded.
     */
    function transfer(address to, uint256 amount) external override returns (bool) {
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
     * @param from the address to be moving shares from.
     * @param to the address to be moving shares to.
     * @param amount the quantity of shares to move.
     * @return . a boolean value indicating whether the operation succeeded.
     */
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
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
