// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { IAccountant } from "../../interfaces/IAccountant.sol";
import { IDepositLimitModule } from "../../interfaces/IDepositLimitModule.sol";
import { IWithdrawLimitModule } from "../../interfaces/IWithdrawLimitModule.sol";
import { IFactory } from "../../interfaces/IFactory.sol";
import { IERC4626Payable } from "../../interfaces/IERC4626Payable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @notice
 *   This Vault is based on the original VaultV3.vy Vyper implementation
 *   that has been ported to Solidity. It is designed as a non-opinionated system
 *   to distribute funds of depositors for a specific `asset` into different
 *   opportunities (aka Strategies) and manage accounting in a robust way.
 *
 *   Depositors receive shares (aka vaults tokens) proportional to their deposit amount.
 *   Vault tokens are yield-bearing and can be redeemed at any time to get back deposit
 *   plus any yield generated.
 *
 *   Addresses that are given different permissioned roles by the `roleManager`
 *   are then able to allocate funds as they best see fit to different strategies
 *   and adjust the strategies and allocations as needed, as well as reporting realized
 *   profits or losses.
 *
 *   Strategies are any ERC-4626 compliant contracts that use the same underlying `asset`
 *   as the vault. The vault provides no assurances as to the safety of any strategy
 *   and it is the responsibility of those that hold the corresponding roles to choose
 *   and fund strategies that best fit their desired specifications.
 *
 *   Those holding vault tokens are able to redeem the tokens for the corresponding
 *   amount of underlying asset based on any reported profits or losses since their
 *   initial deposit.
 *
 *   The vault is built to be customized by the management to be able to fit their
 *   specific desired needs. Including the customization of strategies, accountants,
 *   ownership etc.
 */
contract Vault is IVault {
    // CONSTANTS
    // The max length the withdrawal queue can be.
    uint256 public constant MAX_QUEUE = 10;
    // 100% in Basis Points.
    uint256 public constant MAX_BPS = 10_000;
    // Extended for profit locking calculations.
    uint256 public constant MAX_BPS_EXTENDED = 1_000_000_000_000;
    // The version of this vault.
    string public constant API_VERSION = "3.0.4";

    // EIP-712 constants
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant PERMIT_TYPE_HASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // STORAGE
    // Underlying token used by the vault.
    address public override asset;
    // Based off the `asset` decimals.
    uint8 public override decimals;
    // Deployer contract used to retrieve the protocol fee config.
    address private factory;
    // State for a withdrawal operation.
    WithdrawalState private _wState;

    // HashMap that records all the strategies that are allowed to receive assets from the vault.
    mapping(address => StrategyParams) private _strategies;

    // The current default withdrawal queue.
    address[] public defaultQueue;
    // Should the vault use the defaultQueue regardless whats passed in.
    bool public useDefaultQueue;
    // Should the vault automatically allocate funds to the first strategy in queue.
    bool public autoAllocate;

    /// ACCOUNTING ///
    // ERC20 - amount of shares per account
    mapping(address => uint256) private balanceOf_;
    // ERC20 - owner -> (spender -> amount)
    mapping(address => mapping(address => uint256)) public override allowance;
    // Total amount of shares that are currently minted including those locked.
    uint256 private totalSupply_;
    // Total amount of assets that has been deposited in strategies.
    uint256 private totalDebt_;
    // Current assets held in the vault contract. Replacing balanceOf(this) to avoid price_per_share manipulation.
    uint256 private totalIdle_;
    // Minimum amount of assets that should be kept in the vault contract to allow for fast, cheap redeems.
    uint256 public override minimumTotalIdle;
    // Maximum amount of tokens that the vault can accept. If totalAssets > depositLimit, deposits will revert.
    uint256 public override depositLimit;

    /// PERIPHERY ///
    // Contract that charges fees and can give refunds.
    address public override accountant;
    // Contract to control the deposit limit.
    address public override depositLimitModule;
    // Contract to control the withdraw limit.
    address public override withdrawLimitModule;

    /// ROLES ///
    // HashMap mapping addresses to their roles
    mapping(address => uint256) public roles;
    // Address that can add and remove roles to addresses.
    address public override roleManager;
    // Temporary variable to store the address of the next roleManager until the role is accepted.
    address public override futureRoleManager;

    // ERC20 - name of the vaults token.
    string public override name;
    // ERC20 - symbol of the vaults token.
    string public override symbol;

    // State of the vault - if set to true, only withdrawals will be available. It can't be reverted.
    bool private shutdown_;
    // The amount of time profits will unlock over.
    uint256 private profitMaxUnlockTime_;
    // The timestamp of when the current unlocking period ends.
    uint256 private fullProfitUnlockDate_;
    // The per second rate at which profit will unlock.
    uint256 private profitUnlockingRate_;
    // Last timestamp of the most recent profitable report.
    uint256 private lastProfitUpdate_;

    // `nonces` track `permit` approvals with signature.
    mapping(address => uint256) public override nonces;

    /// MODIFIERS ///

    // Re-entrancy guard
    bool private locked;

    modifier nonReentrant() {
        require(!locked, "reentrancy");
        locked = true;
        _;
        locked = false;
    }

    /// CONSTRUCTOR ///
    constructor() {
        // Set `asset` so it cannot be re-initialized.
        asset = address(this);
    }

    /**
     * @notice Initialize a new vault. Sets the asset, name, symbol, and role manager.
     * @param _asset The address of the asset that the vault will accept.
     * @param _name The name of the vault token.
     * @param _symbol The symbol of the vault token.
     * @param _roleManager The address that can add and remove roles to addresses
     * @param _profitMaxUnlockTime The amount of time that the profit will be locked for
     */
    function initialize(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime
    ) external override {
        require(asset == address(0), "initialized");
        require(_asset != address(0), "ZERO ADDRESS");
        require(_roleManager != address(0), "ZERO ADDRESS");

        asset = _asset;
        // Get the decimals for the vault to use.
        decimals = IERC20Metadata(_asset).decimals();

        // Set the factory as the deployer address.
        factory = msg.sender;

        // Must be less than one year for report cycles
        require(_profitMaxUnlockTime <= 31_556_952, "profit unlock time too long");
        profitMaxUnlockTime_ = _profitMaxUnlockTime;

        name = _name;
        symbol = _symbol;
        roleManager = _roleManager;
    }

    // SETTERS //

    /**
     * @notice Change the vault name.
     * @dev Can only be called by the Role Manager.
     * @param _name The new name for the vault.
     */
    function setName(string memory _name) external override {
        require(msg.sender == roleManager, "not allowed");
        name = _name;
    }

    /**
     * @notice Change the vault symbol.
     * @dev Can only be called by the Role Manager.
     * @param _symbol The new name for the vault.
     */
    function setSymbol(string memory _symbol) external override {
        require(msg.sender == roleManager, "not allowed");
        symbol = _symbol;
    }

    /**
     * @notice Set the new accountant address.
     * @param newAccountant The new accountant address.
     */
    function setAccountant(address newAccountant) external override {
        _enforceRole(msg.sender, Roles.ACCOUNTANT_MANAGER);
        accountant = newAccountant;

        emit UpdateAccountant(newAccountant);
    }

    /**
     * @notice Set the new default queue array (max 10 strategies)
     * @dev Will check each strategy to make sure it is active. But will not
     *      check that the same strategy is not added twice. maxRedeem and maxWithdraw
     *      return values may be inaccurate if a strategy is added twice.
     * @param newDefaultQueue The new default queue array.
     */
    function setDefaultQueue(address[] calldata newDefaultQueue) external override {
        _enforceRole(msg.sender, Roles.QUEUE_MANAGER);
        require(newDefaultQueue.length <= MAX_QUEUE, "max queue length reached");

        // Make sure every strategy in the new queue is active.
        for (uint256 i = 0; i < newDefaultQueue.length; i++) {
            require(_strategies[newDefaultQueue[i]].activation != 0, "inactive strategy");
        }

        // Save the new queue.
        defaultQueue = newDefaultQueue;

        emit UpdateDefaultQueue(newDefaultQueue);
    }

    /**
     * @notice Set a new value for `useDefaultQueue`.
     * @dev If set `True` the default queue will always be
     *      used no matter whats passed in.
     * @param _useDefaultQueue new value.
     */
    function setUseDefaultQueue(bool _useDefaultQueue) external override {
        _enforceRole(msg.sender, Roles.QUEUE_MANAGER);
        useDefaultQueue = _useDefaultQueue;

        emit UpdateUseDefaultQueue(_useDefaultQueue);
    }

    /**
     * @notice Set new value for `autoAllocate`
     * @dev If `True` every {deposit} and {mint} call will
     *      try and allocate the deposited amount to the strategy
     *      at position 0 of the `defaultQueue` atomically.
     * NOTE: An empty `defaultQueue` will cause deposits to fail.
     * @param _autoAllocate new value.
     */
    function setAutoAllocate(bool _autoAllocate) external override {
        _enforceRole(msg.sender, Roles.DEBT_MANAGER);
        autoAllocate = _autoAllocate;

        emit UpdateAutoAllocate(_autoAllocate);
    }

    /**
     * @notice Set the new deposit limit.
     * @dev Can not be changed if a depositLimitModule
     *      is set unless the override flag is true or if shutdown.
     * @param _depositLimit The new deposit limit.
     * @param shouldOverride If a `depositLimitModule` already set should be overridden.
     */
    function setDepositLimit(uint256 _depositLimit, bool shouldOverride) external override {
        require(shutdown_ == false, "shutdown");
        _enforceRole(msg.sender, Roles.DEPOSIT_LIMIT_MANAGER);

        // If we are overriding the deposit limit module.
        if (shouldOverride) {
            // Make sure it is set to address 0 if not already.
            if (depositLimitModule != address(0)) {
                depositLimitModule = address(0);
                emit UpdateDepositLimitModule(address(0));
            }
        } else {
            // Make sure the depositLimitModule has been set to address(0).
            require(depositLimitModule == address(0), "using module");
        }

        depositLimit = _depositLimit;

        emit UpdateDepositLimit(_depositLimit);
    }

    /**
     * @notice Set a contract to handle the deposit limit.
     * @dev The default `depositLimit` will need to be set to
     *      max uint256 since the module will override it or the override flag
     *      must be set to true to set it to max in 1 tx.
     * @param _depositLimitModule Address of the module.
     * @param shouldOverride If a `depositLimit` already set should be overridden.
     */
    function setDepositLimitModule(address _depositLimitModule, bool shouldOverride) external override {
        require(shutdown_ == false, "shutdown");
        _enforceRole(msg.sender, Roles.DEPOSIT_LIMIT_MANAGER);

        // If we are overriding the deposit limit
        if (shouldOverride) {
            // Make sure it is max uint256 if not already.
            if (depositLimit != type(uint256).max) {
                depositLimit = type(uint256).max;
                emit UpdateDepositLimit(type(uint256).max);
            }
        } else {
            // Make sure the deposit_limit has been set to uint max.
            require(depositLimit == type(uint256).max, "using deposit limit");
        }

        depositLimitModule = _depositLimitModule;

        emit UpdateDepositLimitModule(_depositLimitModule);
    }

    /**
     * @notice Set a contract to handle the withdraw limit.
     * @dev This will override the default `maxWithdraw`.
     * @param _withdrawLimitModule Address of the module.
     */
    function setWithdrawLimitModule(address _withdrawLimitModule) external override {
        _enforceRole(msg.sender, Roles.WITHDRAW_LIMIT_MANAGER);

        withdrawLimitModule = _withdrawLimitModule;

        emit UpdateWithdrawLimitModule(_withdrawLimitModule);
    }

    /**
     * @notice Set the new minimum total idle.
     * @param _minimumTotalIdle The new minimum total idle.
     */
    function setMinimumTotalIdle(uint256 _minimumTotalIdle) external override {
        _enforceRole(msg.sender, Roles.MINIMUM_IDLE_MANAGER);
        minimumTotalIdle = _minimumTotalIdle;

        emit UpdateMinimumTotalIdle(_minimumTotalIdle);
    }

    /**
     * @notice Set the new profit max unlock time.
     * @dev The time is denominated in seconds and must be less than 1 year.
     *      We only need to update locking period if setting to 0,
     *      since the current period will use the old rate and on the next
     *      report it will be reset with the new unlocking time.
     *
     *      Setting to 0 will cause any currently locked profit to instantly
     *      unlock and an immediate increase in the vaults Price Per Share.
     *
     * @param newProfitMaxUnlockTime The new profit max unlock time.
     */
    function setProfitMaxUnlockTime(uint256 newProfitMaxUnlockTime) external override {
        _enforceRole(msg.sender, Roles.PROFIT_UNLOCK_MANAGER);
        // Must be less than one year for report cycles
        require(newProfitMaxUnlockTime <= 31_556_952, "profit unlock time too long");

        // If setting to 0 we need to reset any locked values.
        if (newProfitMaxUnlockTime == 0) {
            uint256 shareBalance = balanceOf_[address(this)];
            if (shareBalance > 0) {
                // Burn any shares the vault still has.
                _burnShares(shareBalance, address(this));
            }

            // Reset unlocking variables to 0.
            profitUnlockingRate_ = 0;
            fullProfitUnlockDate_ = 0;
        }

        profitMaxUnlockTime_ = newProfitMaxUnlockTime;

        emit UpdateProfitMaxUnlockTime(newProfitMaxUnlockTime);
    }

    // ROLE MANAGEMENT //

    /**
     * @dev Enforces that the sender has the required role
     */
    function _enforceRole(address account, Roles role) internal view {
        // Check bit at role position
        require(roles[account] & (1 << uint256(role)) != 0, "not allowed");
    }

    /**
     * @notice Set the roles for an account.
     * @dev This will fully override an accounts current roles
     *      so it should include all roles the account should hold.
     * @param account The account to set the role for.
     * @param rolesBitmask The roles the account should hold.
     */
    function setRole(address account, uint256 rolesBitmask) external override {
        require(msg.sender == roleManager, "not allowed");
        // Store the enum value directly
        roles[account] = rolesBitmask;
        emit RoleSet(account, rolesBitmask);
    }

    /**
     * @notice Add a new role/s to an address.
     * @dev This will add a new role/s to the account
     *      without effecting any of the previously held roles.
     * @param account The account to add a role to.
     * @param role The new role/s to add to account.
     */
    function addRole(address account, Roles role) external override {
        require(msg.sender == roleManager, "not allowed");
        // Add the role with a bitwise OR
        roles[account] = roles[account] | (1 << uint256(role));
        emit RoleSet(account, roles[account]);
    }

    /**
     * @notice Remove a role/s from an account.
     * @dev This will leave all other roles for the
     *      account unchanged.
     * @param account The account to remove a Role/s from.
     * @param role The Role/s to remove.
     */
    function removeRole(address account, Roles role) external override {
        require(msg.sender == roleManager, "not allowed");

        // Bitwise AND with NOT to remove the role
        roles[account] = roles[account] & ~(1 << uint256(role));
        emit RoleSet(account, roles[account]);
    }

    /**
     * @notice Step 1 of 2 in order to transfer the
     *      role manager to a new address. This will set
     *      the futureRoleManager. Which will then need
     *      to be accepted by the new manager.
     * @param _roleManager The new role manager address.
     */
    function transferRoleManager(address _roleManager) external override {
        require(msg.sender == roleManager, "not allowed");
        futureRoleManager = _roleManager;

        emit UpdateFutureRoleManager(_roleManager);
    }

    /**
     * @notice Accept the role manager transfer.
     */
    function acceptRoleManager() external override {
        require(msg.sender == futureRoleManager, "not future role manager");
        roleManager = msg.sender;
        futureRoleManager = address(0);

        emit UpdateRoleManager(msg.sender);
    }

    // VAULT STATUS VIEWS

    /**
     * @notice Get if the vault is shutdown.
     * @return Bool representing the shutdown status
     */
    function isShutdown() external view override returns (bool) {
        return shutdown_;
    }

    /**
     * @notice Get the amount of shares that have been unlocked.
     * @return The amount of shares that have been unlocked.
     */
    function unlockedShares() external view override returns (uint256) {
        return _unlockedShares();
    }

    /**
     * @notice Get the price per share (pps) of the vault.
     * @dev This value offers limited precision. Integrations that require
     *      exact precision should use convertToAssets or convertToShares instead.
     * @return The price per share.
     */
    function pricePerShare() external view override returns (uint256) {
        return _convertToAssets(10 ** uint256(decimals), Rounding.ROUND_DOWN);
    }

    /**
     * @notice Get the full default queue currently set.
     * @return The current default withdrawal queue.
     */
    function getDefaultQueue() external view override returns (address[] memory) {
        return defaultQueue;
    }

    /// REPORTING MANAGEMENT ///

    // Main external function
    function processReport(address strategy) external returns (uint256, uint256) {
        _enforceRole(msg.sender, Roles.REPORTING_MANAGER);
        return _processReport(strategy);
    }

    /**
     * @notice Used for governance to buy bad debt from the vault.
     * @dev This should only ever be used in an emergency in place
     *      of force revoking a strategy in order to not report a loss.
     *      It allows the DEBT_PURCHASER role to buy the strategies debt
     *      for an equal amount of `asset`.
     *
     * @param strategy The strategy to buy the debt for
     * @param amount The amount of debt to buy from the vault.
     */
    function buyDebt(address strategy, uint256 amount) external override nonReentrant {
        _enforceRole(msg.sender, Roles.DEBT_PURCHASER);
        require(_strategies[strategy].activation != 0, "not active");

        // Cache the current debt.
        uint256 currentDebt = _strategies[strategy].currentDebt;
        uint256 _amount = amount;

        require(currentDebt > 0, "nothing to buy");
        require(_amount > 0, "nothing to buy with");

        if (_amount > currentDebt) {
            _amount = currentDebt;
        }

        // We get the proportion of the debt that is being bought and
        // transfer the equivalent shares. We assume this is being used
        // due to strategy issues so won't rely on its conversion rates.
        uint256 shares = (IERC4626Payable(strategy).balanceOf(address(this)) * _amount) / currentDebt;

        require(shares > 0, "cannot buy zero");

        _erc20SafeTransferFrom(asset, msg.sender, address(this), _amount);

        // Lower strategy debt
        uint256 newDebt = currentDebt - _amount;
        _strategies[strategy].currentDebt = newDebt;

        totalDebt_ -= _amount;
        totalIdle_ += _amount;

        // log debt change
        emit DebtUpdated(strategy, currentDebt, newDebt);

        // Transfer the strategies shares out.
        _erc20SafeTransfer(strategy, msg.sender, shares);

        emit DebtPurchased(strategy, _amount);
    }

    /// STRATEGY MANAGEMENT ///

    /**
     * @notice Add a new strategy.
     * @param newStrategy The new strategy to add.
     * @param addToQueue Whether to add the strategy to the default queue.
     */
    function addStrategy(address newStrategy, bool addToQueue) external override {
        _enforceRole(msg.sender, Roles.ADD_STRATEGY_MANAGER);
        _addStrategy(newStrategy, addToQueue);
    }

    /**
     * @notice Revoke a strategy.
     * @param strategy The strategy to revoke.
     */
    function revokeStrategy(address strategy) external override {
        _enforceRole(msg.sender, Roles.REVOKE_STRATEGY_MANAGER);
        _revokeStrategy(strategy, false);
    }

    /**
     * @notice Force revoke a strategy.
     * @dev The vault will remove the strategy and write off any debt left
     *      in it as a loss. This function is a dangerous function as it can force a
     *      strategy to take a loss. All possible assets should be removed from the
     *      strategy first via updateDebt. If a strategy is removed erroneously it
     *      can be re-added and the loss will be credited as profit. Fees will apply.
     * @param strategy The strategy to force revoke.
     */
    function forceRevokeStrategy(address strategy) external override {
        _enforceRole(msg.sender, Roles.FORCE_REVOKE_MANAGER);
        _revokeStrategy(strategy, true);
    }

    /// DEBT MANAGEMENT ///

    /**
     * @notice Update the max debt for a strategy.
     * @param strategy The strategy to update the max debt for.
     * @param newMaxDebt The new max debt for the strategy.
     */
    function updateMaxDebtForStrategy(address strategy, uint256 newMaxDebt) external override {
        _enforceRole(msg.sender, Roles.MAX_DEBT_MANAGER);
        require(_strategies[strategy].activation != 0, "inactive strategy");
        _strategies[strategy].maxDebt = newMaxDebt;

        emit UpdatedMaxDebtForStrategy(msg.sender, strategy, newMaxDebt);
    }

    /**
     * @notice Update the debt for a strategy.
     * @dev Pass max uint256 to allocate as much idle as possible.
     * @param strategy The strategy to update the debt for.
     * @param targetDebt The target debt for the strategy.
     * @param maxLoss Optional to check realized losses on debt decreases.
     * @return The new current debt of the strategy.
     */
    function updateDebt(
        address strategy,
        uint256 targetDebt,
        uint256 maxLoss
    ) external override nonReentrant returns (uint256) {
        _enforceRole(msg.sender, Roles.DEBT_MANAGER);
        console.log("Updating debt for strategy", strategy);
        return _updateDebt(strategy, targetDebt, maxLoss);
    }

    /// EMERGENCY MANAGEMENT ///

    /**
     * @notice Shutdown the vault.
     */
    function shutdownVault() external override {
        _enforceRole(msg.sender, Roles.EMERGENCY_MANAGER);
        require(shutdown_ == false, "already shutdown");

        // Shutdown the vault.
        shutdown_ = true;

        // Set deposit limit to 0.
        if (depositLimitModule != address(0)) {
            depositLimitModule = address(0);
            emit UpdateDepositLimitModule(address(0));
        }

        depositLimit = 0;
        emit UpdateDepositLimit(0);

        // Add debt manager role to the sender
        roles[msg.sender] = roles[msg.sender] | (1 << uint256(Roles.DEBT_MANAGER));
        // todo might need to emit the combined roles
        emit RoleSet(msg.sender, roles[msg.sender]);

        emit Shutdown();
    }

    /// SHARE MANAGEMENT ///
    /// ERC20 + ERC4626 ///

    /**
     * @notice Deposit assets into the vault.
     * @dev Pass max uint256 to deposit full asset balance.
     * @param assets The amount of assets to deposit.
     * @param receiver The address to receive the shares.
     * @return The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) external override nonReentrant returns (uint256) {
        uint256 amount = assets;
        // Deposit all if sent with max uint
        if (amount == type(uint256).max) {
            amount = IERC20(asset).balanceOf(msg.sender);
        }

        uint256 shares = _convertToShares(amount, Rounding.ROUND_DOWN);
        _deposit(receiver, amount, shares);
        return shares;
    }

    /**
     * @notice Mint shares for the receiver.
     * @param shares The amount of shares to mint.
     * @param receiver The address to receive the shares.
     * @return The amount of assets deposited.
     */
    function mint(uint256 shares, address receiver) external nonReentrant returns (uint256) {
        uint256 assets = _convertToAssets(shares, Rounding.ROUND_UP);
        _deposit(receiver, assets, shares);
        return assets;
    }

    /**
     * @notice Withdraw an amount of asset to `receiver` burning `owner`s shares.
     * @dev The default behavior is to not allow any loss.
     * @param assets The amount of asset to withdraw.
     * @param receiver The address to receive the assets.
     * @param owner The address who's shares are being burnt.
     * @param maxLoss Optional amount of acceptable loss in Basis Points.
     * @param strategiesArray Optional array of strategies to withdraw from.
     * @return The amount of shares actually burnt.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) external override nonReentrant returns (uint256) {
        uint256 shares = _convertToShares(assets, Rounding.ROUND_UP);
        _redeem(msg.sender, receiver, owner, assets, shares, maxLoss, strategiesArray);
        return shares;
    }

    /**
     * @notice Redeems an amount of shares of `owners` shares sending funds to `receiver`.
     * @dev The default behavior is to allow losses to be realized.
     * @param shares The amount of shares to burn.
     * @param receiver The address to receive the assets.
     * @param owner The address who's shares are being burnt.
     * @param maxLoss Optional amount of acceptable loss in Basis Points.
     * @param strategiesArray Optional array of strategies to withdraw from.
     * @return The amount of assets actually withdrawn.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) external override nonReentrant returns (uint256) {
        uint256 assets = _convertToAssets(shares, Rounding.ROUND_DOWN);
        // Always return the actual amount of assets withdrawn.
        return _redeem(msg.sender, receiver, owner, assets, shares, maxLoss, strategiesArray);
    }

    /**
     * @notice Approve an address to spend the vault's shares.
     * @param spender The address to approve.
     * @param amount The amount of shares to approve.
     * @return True if the approval was successful.
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        return _approve(msg.sender, spender, amount);
    }

    /**
     * @notice Transfer shares to a receiver.
     * @param receiver The address to transfer shares to.
     * @param amount The amount of shares to transfer.
     * @return True if the transfer was successful.
     */
    function transfer(address receiver, uint256 amount) external override returns (bool) {
        require(receiver != address(this) && receiver != address(0), "invalid receiver");
        _transfer(msg.sender, receiver, amount);
        return true;
    }

    /**
     * @notice Transfer shares from a sender to a receiver.
     * @param sender The address to transfer shares from.
     * @param receiver The address to transfer shares to.
     * @param amount The amount of shares to transfer.
     * @return True if the transfer was successful.
     */
    function transferFrom(address sender, address receiver, uint256 amount) external override returns (bool) {
        require(receiver != address(this) && receiver != address(0), "invalid receiver");
        _spendAllowance(sender, msg.sender, amount);
        _transfer(sender, receiver, amount);
        return true;
    }

    /**
     * @notice Approve an address to spend the vault's shares with permit.
     * @param owner The address to approve from.
     * @param spender The address to approve.
     * @param amount The amount of shares to approve.
     * @param deadline The deadline for the permit.
     * @param v The v component of the signature.
     * @param r The r component of the signature.
     * @param s The s component of the signature.
     * @return True if the approval was successful.
     */
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (bool) {
        return _permit(owner, spender, amount, deadline, v, r, s);
    }

    /**
     * @notice Get the balance of a user.
     * @param addr The address to get the balance of.
     * @return The balance of the user.
     */
    function balanceOf(address addr) public view override returns (uint256) {
        if (addr == address(this)) {
            // If the address is the vault, account for locked shares.
            return balanceOf_[addr] - _unlockedShares();
        }

        return balanceOf_[addr];
    }

    /**
     * @notice Get the total supply of shares.
     * @return The total supply of shares.
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply();
    }

    /**
     * @notice Get the total assets held by the vault.
     * @return The total assets held by the vault.
     */
    function totalAssets() external view override returns (uint256) {
        return _totalAssets();
    }

    /**
     * @notice Get the amount of loose `asset` the vault holds.
     * @return The current total idle.
     */
    function totalIdle() external view override returns (uint256) {
        return totalIdle_;
    }

    /**
     * @notice Get the the total amount of funds invested across all strategies.
     * @return The current total debt.
     */
    function totalDebt() external view override returns (uint256) {
        return totalDebt_;
    }

    /**
     * @notice Convert an amount of assets to shares.
     * @param assets The amount of assets to convert.
     * @return The amount of shares.
     */
    function convertToShares(uint256 assets) external view override returns (uint256) {
        return _convertToShares(assets, Rounding.ROUND_DOWN);
    }

    /**
     * @notice Preview the amount of shares that would be minted for a deposit.
     * @param assets The amount of assets to deposit.
     * @return The amount of shares that would be minted.
     */
    function previewDeposit(uint256 assets) external view override returns (uint256) {
        return _convertToShares(assets, Rounding.ROUND_DOWN);
    }

    /**
     * @notice Preview the amount of assets that would be deposited for a mint.
     * @param shares The amount of shares to mint.
     * @return The amount of assets that would be deposited.
     */
    function previewMint(uint256 shares) external view override returns (uint256) {
        return _convertToAssets(shares, Rounding.ROUND_UP);
    }

    /**
     * @notice Convert an amount of shares to assets.
     * @param shares The amount of shares to convert.
     * @return The amount of assets.
     */
    function convertToAssets(uint256 shares) external view override returns (uint256) {
        return _convertToAssets(shares, Rounding.ROUND_DOWN);
    }

    /**
     * @notice Get the maximum amount of assets that can be deposited.
     * @param receiver The address that will receive the shares.
     * @return The maximum amount of assets that can be deposited.
     */
    function maxDeposit(address receiver) external view override returns (uint256) {
        return _maxDeposit(receiver);
    }

    /**
     * @notice Get the maximum amount of shares that can be minted.
     * @param receiver The address that will receive the shares.
     * @return The maximum amount of shares that can be minted.
     */
    function maxMint(address receiver) external view override returns (uint256) {
        uint256 maxDepositAmount = _maxDeposit(receiver);
        return _convertToShares(maxDepositAmount, Rounding.ROUND_DOWN);
    }

    /**
     * @notice Get the maximum amount of assets that can be withdrawn.
     * @dev Complies to normal 4626 interface and takes custom params.
     * NOTE: Passing in a incorrectly ordered queue may result in
     *       incorrect returns values.
     * @param owner The address that owns the shares.
     * @param maxLoss Custom max_loss if any.
     * @param strategiesArray Custom strategies queue if any.
     * @return The maximum amount of assets that can be withdrawn.
     */
    function maxWithdraw(
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) external view override returns (uint256) {
        return _maxWithdraw(owner, maxLoss, strategiesArray);
    }

    /**
     * @notice Get the maximum amount of shares that can be redeemed.
     * @dev Complies to normal 4626 interface and takes custom params.
     * NOTE: Passing in a incorrectly ordered queue may result in
     *       incorrect returns values.
     * @param owner The address that owns the shares.
     * @param maxLoss Custom max_loss if any.
     * @param strategiesArray Custom strategies queue if any.
     * @return The maximum amount of shares that can be redeemed.
     */
    function maxRedeem(
        address owner,
        uint256 maxLoss,
        address[] calldata strategiesArray
    ) external view override returns (uint256) {
        return
            Math.min(
                // Min of the shares equivalent of max_withdraw or the full balance
                _convertToShares(_maxWithdraw(owner, maxLoss, strategiesArray), Rounding.ROUND_DOWN),
                balanceOf_[owner]
            );
    }

    /**
     * @notice Preview the amount of shares that would be redeemed for a withdraw.
     * @param assets The amount of assets to withdraw.
     * @return The amount of shares that would be redeemed.
     */
    function previewWithdraw(uint256 assets) external view override returns (uint256) {
        return _convertToShares(assets, Rounding.ROUND_UP);
    }

    /**
     * @notice Preview the amount of assets that would be withdrawn for a redeem.
     * @param shares The amount of shares to redeem.
     * @return The amount of assets that would be withdrawn.
     */
    function previewRedeem(uint256 shares) external view override returns (uint256) {
        return _convertToAssets(shares, Rounding.ROUND_DOWN);
    }

    /**
     * @notice Address of the factory that deployed the vault.
     * @dev Is used to retrieve the protocol fees.
     * @return Address of the vault factory.
     */
    function FACTORY() external view override returns (address) {
        return factory;
    }

    /**
     * @notice Get the API version of the vault.
     * @return The API version of the vault.
     */
    function apiVersion() external pure override returns (string memory) {
        return API_VERSION;
    }

    /**
     * @notice Assess the share of unrealised losses that a strategy has.
     * @param strategy The address of the strategy.
     * @param assetsNeeded The amount of assets needed to be withdrawn.
     * @return The share of unrealised losses that the strategy has.
     */
    function assessShareOfUnrealisedLosses(
        address strategy,
        uint256 assetsNeeded
    ) external view override returns (uint256) {
        uint256 currentDebt = _strategies[strategy].currentDebt;
        require(currentDebt >= assetsNeeded, "not enough debt");

        return _assessShareOfUnrealisedLosses(strategy, currentDebt, assetsNeeded);
    }

    /**
     * @notice Gets the current time profits are set to unlock over.
     * @return The current profit max unlock time.
     */
    function profitMaxUnlockTime() external view override returns (uint256) {
        return profitMaxUnlockTime_;
    }

    /**
     * @notice Gets the timestamp at which all profits will be unlocked.
     * @return The full profit unlocking timestamp
     */
    function fullProfitUnlockDate() external view override returns (uint256) {
        return fullProfitUnlockDate_;
    }

    /**
     * @notice The per second rate at which profits are unlocking.
     * @dev This is denominated in EXTENDED_BPS decimals.
     * @return The current profit unlocking rate.
     */
    function profitUnlockingRate() external view override returns (uint256) {
        return profitUnlockingRate_;
    }

    /**
     * @notice The timestamp of the last time shares were locked.
     * @return The last profit update.
     */
    function lastProfitUpdate() external view override returns (uint256) {
        return lastProfitUpdate_;
    }

    /**
     * @notice Get the domain separator for EIP-712.
     * @return The domain separator.
     */
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPE_HASH,
                    keccak256(bytes("Yearn Vault")),
                    keccak256(bytes(API_VERSION)),
                    block.chainid,
                    address(this)
                )
            );
    }

    /**
     * @notice Get the strategy parameters for a given strategy.
     * @param strategy The address of the strategy.
     * @return The strategy parameters.
     */
    function strategies(address strategy) external view returns (StrategyParams memory) {
        return _strategies[strategy];
    }

    /// SHARE MANAGEMENT ///
    /// ERC20 ///
    /**
     * @dev Spends allowance from owner to spender
     */
    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        // Unlimited approval does nothing (saves an SSTORE)
        uint256 currentAllowance = allowance[owner][spender];
        if (currentAllowance < type(uint256).max) {
            require(currentAllowance >= amount, "insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
    }

    /**
     * @dev Transfers tokens from sender to receiver
     */
    function _transfer(address sender, address receiver, uint256 amount) internal {
        uint256 senderBalance = balanceOf_[sender];
        require(senderBalance >= amount, "insufficient funds");
        balanceOf_[sender] = senderBalance - amount;
        balanceOf_[receiver] += amount;
        emit Transfer(sender, receiver, amount);
    }

    /**
     * @dev Sets approval of spender for owner's tokens
     */
    function _approve(address owner, address spender, uint256 amount) internal returns (bool) {
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
        return true;
    }

    /**
     * @dev Implementation of the permit function (EIP-2612)
     */
    function _permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (bool) {
        require(owner != address(0), "invalid owner");
        require(deadline >= block.timestamp, "permit expired");
        uint256 nonce = nonces[owner];
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPE_HASH, owner, spender, amount, nonce, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "invalid signature");

        allowance[owner][spender] = amount;
        nonces[owner] = nonce + 1;
        emit Approval(owner, spender, amount);
        return true;
    }

    /**
     * @dev Burns shares from an account
     */
    function _burnShares(uint256 shares, address owner) internal {
        balanceOf_[owner] -= shares;
        totalSupply_ -= shares;
        emit Transfer(owner, address(0), shares);
    }

    /**
     * @dev Returns the amount of shares that have been unlocked
     */
    function _unlockedShares() internal view returns (uint256) {
        uint256 _fullProfitUnlockDate = fullProfitUnlockDate_;
        uint256 unlockedSharesAmount = 0;

        if (_fullProfitUnlockDate > block.timestamp) {
            // If we have not fully unlocked, we need to calculate how much has been.
            unlockedSharesAmount = (profitUnlockingRate_ * (block.timestamp - lastProfitUpdate_)) / MAX_BPS_EXTENDED;
        } else if (_fullProfitUnlockDate != 0) {
            // All shares have been unlocked
            unlockedSharesAmount = balanceOf_[address(this)];
        }

        return unlockedSharesAmount;
    }

    /**
     * @dev Returns the total supply accounting for unlocked shares
     */
    function _totalSupply() internal view returns (uint256) {
        // Need to account for the shares issued to the vault that have unlocked.
        return totalSupply_ - _unlockedShares();
    }

    /**
     * @dev Returns the total assets (idle + debt)
     */
    function _totalAssets() internal view returns (uint256) {
        return totalIdle_ + totalDebt_;
    }

    /**
     * @dev Converts shares to assets
     */
    function _convertToAssets(uint256 shares, Rounding rounding) internal view returns (uint256) {
        if (shares == type(uint256).max || shares == 0) {
            return shares;
        }

        uint256 supply = _totalSupply();
        // if totalSupply is 0, price_per_share is 1
        if (supply == 0) {
            return shares;
        }

        uint256 numerator = shares * _totalAssets();
        uint256 amount = numerator / supply;
        if (rounding == Rounding.ROUND_UP && numerator % supply != 0) {
            amount += 1;
        }

        return amount;
    }

    /**
     * @dev Converts assets to shares
     */
    function _convertToShares(uint256 assets, Rounding rounding) internal view returns (uint256) {
        if (assets == type(uint256).max || assets == 0) {
            return assets;
        }

        uint256 supply = _totalSupply();

        // if total_supply is 0, price_per_share is 1
        if (supply == 0) {
            return assets;
        }

        uint256 totalAssetsAmount = _totalAssets();

        // if totalSupply > 0 but totalAssets == 0, price_per_share = 0
        if (totalAssetsAmount == 0) {
            return 0;
        }

        uint256 numerator = assets * supply;
        uint256 sharesAmount = numerator / totalAssetsAmount;
        if (rounding == Rounding.ROUND_UP && numerator % totalAssetsAmount != 0) {
            sharesAmount += 1;
        }

        return sharesAmount;
    }

    /**
     * @dev Safe approve for potentially non-compliant tokens
     */
    function _erc20SafeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approval failed");
    }

    /**
     * @dev Safe transferFrom for potentially non-compliant tokens
     */
    function _erc20SafeTransferFrom(address token, address sender, address receiver, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, sender, receiver, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    /**
     * @dev Safe transfer for potentially non-compliant tokens
     */
    function _erc20SafeTransfer(address token, address receiver, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, receiver, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    /**
     * @dev Issues shares to a recipient
     */
    function _issueShares(uint256 shares, address recipient) internal {
        balanceOf_[recipient] += shares;
        totalSupply_ += shares;
        emit Transfer(address(0), recipient, shares);
    }

    /// ERC4626 ///

    /**
     * @dev Returns the maximum deposit possible for a receiver
     */
    function _maxDeposit(address receiver) internal view returns (uint256) {
        if (receiver == address(0) || receiver == address(this)) {
            return 0;
        }

        // If there is a deposit limit module set use that.
        address _depositLimitModule = depositLimitModule;

        if (_depositLimitModule != address(0)) {
            return IDepositLimitModule(_depositLimitModule).availableDepositLimit(receiver);
        }

        // Else use the standard flow.
        uint256 _depositLimit = depositLimit;
        if (_depositLimit == type(uint256).max) {
            return _depositLimit;
        }

        uint256 _totalAssetsAmount = _totalAssets();
        if (_totalAssetsAmount >= _depositLimit) {
            return 0;
        }

        return _depositLimit - _totalAssetsAmount;
    }

    /**
     * @dev Returns the maximum amount an owner can withdraw
     */
    function _maxWithdraw(
        address owner,
        uint256 maxLoss,
        address[] memory strategiesParam
    ) internal view returns (uint256) {
        MaxWithdrawVars memory vars;

        // Get the max amount for the owner if fully liquid
        vars.maxAssets = _convertToAssets(balanceOf_[owner], Rounding.ROUND_DOWN);

        // If there is a withdraw limit module use that
        address _withdrawLimitModule = withdrawLimitModule;
        if (_withdrawLimitModule != address(0)) {
            return
                Math.min(
                    IWithdrawLimitModule(_withdrawLimitModule).availableWithdrawLimit(owner, maxLoss, strategiesParam),
                    vars.maxAssets
                );
        }

        // See if we have enough idle to service the withdraw
        vars.currentIdle = totalIdle_;
        if (vars.maxAssets > vars.currentIdle) {
            // Track how much we can pull
            vars.have = vars.currentIdle;
            vars.loss = 0;

            // Determine which strategy queue to use
            vars.withdrawalStrategies = strategiesParam.length != 0 && !useDefaultQueue
                ? strategiesParam
                : defaultQueue;

            // Process each strategy in the queue
            for (uint256 i = 0; i < vars.withdrawalStrategies.length; i++) {
                address strategy = vars.withdrawalStrategies[i];
                require(_strategies[strategy].activation != 0, "inactive strategy");

                uint256 currentDebt = _strategies[strategy].currentDebt;
                // Get the maximum amount the vault would withdraw from the strategy
                uint256 toWithdraw = Math.min(vars.maxAssets - vars.have, currentDebt);

                // Get any unrealized loss for the strategy
                uint256 unrealizedLoss = _assessShareOfUnrealisedLosses(strategy, currentDebt, toWithdraw);

                // See if any limit is enforced by the strategy
                uint256 strategyLimit = IERC4626Payable(strategy).convertToAssets(
                    IERC4626Payable(strategy).maxRedeem(address(this))
                );

                // Adjust accordingly if there is a max withdraw limit
                uint256 realizableWithdraw = toWithdraw - unrealizedLoss;
                if (strategyLimit < realizableWithdraw) {
                    if (unrealizedLoss != 0) {
                        // Lower unrealized loss proportional to the limit
                        unrealizedLoss = (unrealizedLoss * strategyLimit) / realizableWithdraw;
                    }
                    // Still count the unrealized loss as withdrawable
                    toWithdraw = strategyLimit + unrealizedLoss;
                }

                // If 0 move on to the next strategy
                if (toWithdraw == 0) {
                    continue;
                }

                // If there would be a loss with a non-maximum `maxLoss` value
                if (unrealizedLoss > 0 && maxLoss < MAX_BPS) {
                    // Check if the loss is greater than the allowed range
                    if (vars.loss + unrealizedLoss > ((vars.have + toWithdraw) * maxLoss) / MAX_BPS) {
                        // If so use the amounts up till now
                        break;
                    }
                }

                // Add to what we can pull
                vars.have += toWithdraw;

                // If we have all we need break
                if (vars.have >= vars.maxAssets) {
                    break;
                }

                // Add any unrealized loss to the total
                vars.loss += unrealizedLoss;
            }

            // Update the max after going through the queue
            vars.maxAssets = vars.have;
        }

        return vars.maxAssets;
    }

    /**
     * @dev Handles deposit logic
     */
    function _deposit(address recipient, uint256 assets, uint256 shares) internal {
        require(assets <= _maxDeposit(recipient), "exceed deposit limit");
        require(assets > 0, "cannot deposit zero");
        require(shares > 0, "cannot mint zero");

        // Transfer the tokens to the vault first.
        _erc20SafeTransferFrom(asset, msg.sender, address(this), assets);

        // Record the change in total assets.
        totalIdle_ += assets;

        // Issue the corresponding shares for assets.
        _issueShares(shares, recipient);

        emit Deposit(msg.sender, recipient, assets, shares);

        if (autoAllocate && defaultQueue.length > 0) {
            _updateDebt(defaultQueue[0], type(uint256).max, 0);
        }
    }

    /**
     * @dev Returns share of unrealized losses
     */
    function _assessShareOfUnrealisedLosses(
        address strategy,
        uint256 strategyCurrentDebt,
        uint256 assetsNeeded
    ) internal view returns (uint256) {
        // The actual amount that the debt is currently worth.
        uint256 vaultShares = IERC4626Payable(strategy).balanceOf(address(this));
        uint256 strategyAssets = IERC4626Payable(strategy).convertToAssets(vaultShares);

        // If no losses, return 0
        if (strategyAssets >= strategyCurrentDebt || strategyCurrentDebt == 0) {
            return 0;
        }

        // Users will withdraw assetsNeeded divided by loss ratio (strategyAssets / strategyCurrentDebt - 1).
        // NOTE: If there are unrealised losses, the user will take his share.
        uint256 numerator = assetsNeeded * strategyAssets;
        uint256 usersShareOfLoss = assetsNeeded - numerator / strategyCurrentDebt;

        // Always round up.
        if (numerator % strategyCurrentDebt != 0) {
            usersShareOfLoss += 1;
        }

        return usersShareOfLoss;
    }

    /**
     * @dev Withdraws assets from strategy
     */
    function _withdrawFromStrategy(address strategy, uint256 assetsToWithdraw) internal {
        // Need to get shares since we use redeem to be able to take on losses.
        uint256 sharesToRedeem = Math.min(
            // Use previewWithdraw since it should round up.
            IERC4626Payable(strategy).previewWithdraw(assetsToWithdraw),
            // And check against our actual balance.
            IERC4626Payable(strategy).balanceOf(address(this))
        );

        // Redeem the shares.
        IERC4626Payable(strategy).redeem(sharesToRedeem, address(this), address(this));
    }

    /// STRATEGY MANAGEMENT ///
    /**
     * @dev Adds a new strategy
     */
    function _addStrategy(address newStrategy, bool addToQueue) internal {
        require(newStrategy != address(this) && newStrategy != address(0), "strategy cannot be zero address");
        require(IERC4626Payable(newStrategy).asset() == asset, "invalid asset");
        require(_strategies[newStrategy].activation == 0, "strategy already active");

        // Add the new strategy to the mapping.
        _strategies[newStrategy] = StrategyParams({
            activation: block.timestamp,
            lastReport: block.timestamp,
            currentDebt: 0,
            maxDebt: 0
        });

        // If we are adding to the queue and the default queue has space, add the strategy.
        if (addToQueue && defaultQueue.length < MAX_QUEUE) {
            defaultQueue.push(newStrategy);
        }

        emit StrategyChanged(newStrategy, StrategyChangeType.ADDED);
    }

    // Internal function - exact port of Vyper implementation
    function _processReport(address strategy) internal returns (uint256, uint256) {
        ProcessReportVars memory vars;

        // Cache asset for repeated use
        vars.asset = asset;

        if (strategy != address(this)) {
            // Make sure we have a valid strategy
            require(_strategies[strategy].activation != 0, "inactive strategy");

            // Vault assesses profits using 4626 compliant interface
            uint256 strategyShares = IERC4626(strategy).balanceOf(address(this));
            // How much the vault's position is worth
            vars.totalAssets = IERC4626(strategy).convertToAssets(strategyShares);
            // How much the vault had deposited to the strategy
            vars.currentDebt = _strategies[strategy].currentDebt;
        } else {
            // Accrue any airdropped asset into totalIdle
            vars.totalAssets = IERC20(vars.asset).balanceOf(address(this));
            vars.currentDebt = totalIdle_;
        }

        // Assess Gain or Loss
        if (vars.totalAssets > vars.currentDebt) {
            // We have a gain
            vars.gain = vars.totalAssets - vars.currentDebt;
        } else {
            // We have a loss
            vars.loss = vars.currentDebt - vars.totalAssets;
        }

        // Assess Fees and Refunds
        address accountant_ = accountant;
        if (accountant_ != address(0)) {
            (vars.totalFees, vars.totalRefunds) = IAccountant(accountant_).report(strategy, vars.gain, vars.loss);

            if (vars.totalRefunds > 0) {
                // Make sure we have enough approval and enough asset to pull
                vars.totalRefunds = Math.min(
                    vars.totalRefunds,
                    Math.min(
                        IERC20(vars.asset).balanceOf(accountant_),
                        IERC20(vars.asset).allowance(accountant_, address(this))
                    )
                );
            }
        }

        // Only need to burn shares if there is a loss or fees
        if (vars.loss + vars.totalFees > 0) {
            // The amount of shares we will want to burn to offset losses and fees
            vars.sharesToBurn = _convertToShares(vars.loss + vars.totalFees, Rounding.ROUND_UP);

            // If we have fees then get the proportional amount of shares to issue
            if (vars.totalFees > 0) {
                // Get the total amount shares to issue for the fees
                vars.totalFeesShares = (vars.sharesToBurn * vars.totalFees) / (vars.loss + vars.totalFees);

                // Get the protocol fee config for this vault
                (vars.protocolFeeBps, vars.protocolFeeRecipient) = IFactory(factory).protocolFeeConfig();

                // If there is a protocol fee
                if (vars.protocolFeeBps > 0) {
                    // Get the percent of fees to go to protocol fees
                    vars.protocolFeesShares = (vars.totalFeesShares * uint256(vars.protocolFeeBps)) / MAX_BPS;
                }
            }
        }

        // Shares to lock is any amount that would otherwise increase the vault's PPS
        vars.profitMaxUnlockTime = profitMaxUnlockTime_;
        // Get the amount we will lock to avoid a PPS increase
        if (vars.gain + vars.totalRefunds > 0 && vars.profitMaxUnlockTime != 0) {
            vars.sharesToLock = _convertToShares(vars.gain + vars.totalRefunds, Rounding.ROUND_DOWN);
        }

        // The total current supply including locked shares
        vars.totalSupply = _totalSupply();
        // The total shares the vault currently owns. Both locked and unlocked
        vars.totalLockedShares = balanceOf_[address(this)];
        // Get the desired end amount of shares after all accounting
        vars.endingSupply = vars.totalSupply + vars.sharesToLock - vars.sharesToBurn - _unlockedShares();

        // If we will end with more shares than we have now
        if (vars.endingSupply > vars.totalSupply) {
            // Issue the difference
            _issueShares(vars.endingSupply - vars.totalSupply, address(this));
        }
        // Else we need to burn shares
        else if (vars.totalSupply > vars.endingSupply) {
            // Can't burn more than the vault owns
            vars.toBurn = Math.min(vars.totalSupply - vars.endingSupply, vars.totalLockedShares);
            _burnShares(vars.toBurn, address(this));
        }

        // Adjust the amount to lock for this period
        if (vars.sharesToLock > vars.sharesToBurn) {
            // Don't lock fees or losses
            vars.sharesToLock = vars.sharesToLock - vars.sharesToBurn;
        } else {
            vars.sharesToLock = 0;
        }

        // Pull refunds
        if (vars.totalRefunds > 0) {
            // Transfer the refunded amount of asset to the vault
            IERC20(vars.asset).transferFrom(accountant_, address(this), vars.totalRefunds);
            // Update storage to increase total assets
            totalIdle_ += vars.totalRefunds;
        }

        // Record any reported gains
        if (vars.gain > 0) {
            // NOTE: this will increase total_assets
            vars.currentDebt = vars.currentDebt + vars.gain;
            if (strategy != address(this)) {
                _strategies[strategy].currentDebt = vars.currentDebt;
                totalDebt_ += vars.gain;
            } else {
                // Add in any refunds since it is now idle
                vars.currentDebt = vars.currentDebt + vars.totalRefunds;
                totalIdle_ = vars.currentDebt;
            }
        }
        // Or record any reported loss
        else if (vars.loss > 0) {
            vars.currentDebt = vars.currentDebt - vars.loss;
            if (strategy != address(this)) {
                _strategies[strategy].currentDebt = vars.currentDebt;
                totalDebt_ -= vars.loss;
            } else {
                // Add in any refunds since it is now idle
                vars.currentDebt = vars.currentDebt + vars.totalRefunds;
                totalIdle_ = vars.currentDebt;
            }
        }

        // Issue shares for fees that were calculated above if applicable
        if (vars.totalFeesShares > 0) {
            // Accountant fees are (total_fees - protocol_fees)
            _issueShares(vars.totalFeesShares - vars.protocolFeesShares, accountant_);

            // If we also have protocol fees
            if (vars.protocolFeesShares > 0) {
                _issueShares(vars.protocolFeesShares, vars.protocolFeeRecipient);
            }
        }

        // Update unlocking rate and time to fully unlocked
        vars.totalLockedShares = balanceOf_[address(this)];
        if (vars.totalLockedShares > 0) {
            vars.fullProfitUnlockDate = fullProfitUnlockDate_;
            // Check if we need to account for shares still unlocking
            if (vars.fullProfitUnlockDate > block.timestamp) {
                // There will only be previously locked shares if time remains
                // We calculate this here since it will not occur every time we lock shares
                vars.previouslyLockedTime =
                    (vars.totalLockedShares - vars.sharesToLock) *
                    (vars.fullProfitUnlockDate - block.timestamp);
            }

            // new_profit_locking_period is a weighted average between the remaining time of the previously locked shares and the profit_max_unlock_time
            vars.newProfitLockingPeriod =
                (vars.previouslyLockedTime + vars.sharesToLock * vars.profitMaxUnlockTime) /
                vars.totalLockedShares;
            // Calculate how many shares unlock per second
            profitUnlockingRate_ = (vars.totalLockedShares * MAX_BPS_EXTENDED) / vars.newProfitLockingPeriod;
            // Calculate how long until the full amount of shares is unlocked
            fullProfitUnlockDate_ = block.timestamp + vars.newProfitLockingPeriod;
            // Update the last profitable report timestamp
            lastProfitUpdate_ = block.timestamp;
        } else {
            // NOTE: only setting this to 0 will turn in the desired effect,
            // no need to update profit_unlocking_rate
            fullProfitUnlockDate_ = 0;
        }

        // Record the report of profit timestamp
        _strategies[strategy].lastReport = block.timestamp;

        // We have to recalculate the fees paid for cases with an overall loss or no profit locking
        if (vars.loss + vars.totalFees > vars.gain + vars.totalRefunds || vars.profitMaxUnlockTime == 0) {
            vars.totalFees = _convertToAssets(vars.totalFeesShares, Rounding.ROUND_DOWN);
        }

        emit StrategyReported(
            strategy,
            vars.gain,
            vars.loss,
            vars.currentDebt,
            (vars.totalFees * uint256(vars.protocolFeeBps)) / MAX_BPS, // Protocol Fees
            vars.totalFees,
            vars.totalRefunds
        );

        return (vars.gain, vars.loss);
    }

    /**
     * @dev Redeems shares from strategies
     */
    function _redeem(
        address sender,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 maxLoss,
        address[] memory strategiesParam
    ) internal returns (uint256) {
        require(receiver != address(0), "ZERO ADDRESS");
        require(shares > 0, "no shares to redeem");
        require(assets > 0, "no assets to withdraw");
        require(maxLoss <= MAX_BPS, "max loss");

        // If there is a withdraw limit module, check the max.
        address _withdrawLimitModule = withdrawLimitModule;
        if (_withdrawLimitModule != address(0)) {
            require(
                assets <=
                    IWithdrawLimitModule(_withdrawLimitModule).availableWithdrawLimit(owner, maxLoss, strategiesParam),
                "exceed withdraw limit"
            );
        }

        require(balanceOf_[owner] >= shares, "insufficient shares to redeem");

        if (sender != owner) {
            _spendAllowance(owner, sender, shares);
        }

        // Initialize our redemption state
        RedeemState memory state;
        state.requestedAssets = assets;
        state.currentTotalIdle = totalIdle_;
        state.asset = asset;
        state.currentTotalDebt = totalDebt_;

        // If there are not enough assets in the Vault contract, we try to free
        // funds from strategies.
        if (state.requestedAssets > state.currentTotalIdle) {
            // Determine which strategies to use
            if (strategiesParam.length != 0 && !useDefaultQueue) {
                state.withdrawalStrategies = strategiesParam;
            } else {
                state.withdrawalStrategies = defaultQueue;
            }

            // Calculate how much we need to withdraw from strategies
            state.assetsNeeded = state.requestedAssets - state.currentTotalIdle;

            // Track the previous balance to calculate actual withdrawn amounts
            state.previousBalance = IERC20(state.asset).balanceOf(address(this));

            // Withdraw from each strategy until we have enough
            for (uint256 i = 0; i < state.withdrawalStrategies.length; i++) {
                address strategy = state.withdrawalStrategies[i];

                // Make sure we have a valid strategy
                require(_strategies[strategy].activation != 0, "inactive strategy");

                // How much the strategy should have
                uint256 currentDebt = _strategies[strategy].currentDebt;

                // What is the max amount to withdraw from this strategy
                uint256 assetsToWithdraw = Math.min(state.assetsNeeded, currentDebt);

                // Cache max withdraw for use if unrealized loss > 0
                uint256 maxWithdrawAmount = IERC4626Payable(strategy).convertToAssets(
                    IERC4626Payable(strategy).maxRedeem(address(this))
                );

                // Check for unrealized losses
                uint256 unrealisedLossesShare = _assessShareOfUnrealisedLosses(strategy, currentDebt, assetsToWithdraw);

                // Handle unrealized losses if any
                if (unrealisedLossesShare > 0) {
                    // If max withdraw is limiting the amount to pull, adjust the portion of
                    // unrealized loss the user should take
                    if (maxWithdrawAmount < assetsToWithdraw - unrealisedLossesShare) {
                        // How much we would want to withdraw
                        uint256 wanted = assetsToWithdraw - unrealisedLossesShare;
                        // Get the proportion of unrealized comparing what we want vs what we can get
                        unrealisedLossesShare = (unrealisedLossesShare * maxWithdrawAmount) / wanted;
                        // Adjust assetsToWithdraw so all future calculations work correctly
                        assetsToWithdraw = maxWithdrawAmount + unrealisedLossesShare;
                    }

                    // User now "needs" less assets to be unlocked (as they took some as losses)
                    assetsToWithdraw -= unrealisedLossesShare;
                    state.requestedAssets -= unrealisedLossesShare;
                    state.assetsNeeded -= unrealisedLossesShare;
                    state.currentTotalDebt -= unrealisedLossesShare;

                    // If max withdraw is 0 and unrealized loss is still > 0, the strategy
                    // likely realized a 100% loss and we need to realize it before moving on
                    if (maxWithdrawAmount == 0 && unrealisedLossesShare > 0) {
                        // Adjust the strategy debt accordingly
                        uint256 newDebt = currentDebt - unrealisedLossesShare;
                        // Update strategies storage
                        _strategies[strategy].currentDebt = newDebt;
                        // Log the debt update
                        emit DebtUpdated(strategy, currentDebt, newDebt);
                    }
                }

                // Adjust based on max withdraw of the strategy
                assetsToWithdraw = Math.min(assetsToWithdraw, maxWithdrawAmount);

                // Can't withdraw 0
                if (assetsToWithdraw == 0) {
                    continue;
                }

                // Withdraw from strategy
                // Need to get shares since we use redeem to be able to take on losses
                uint256 sharesToRedeem = Math.min(
                    // Use previewWithdraw since it should round up
                    IERC4626Payable(strategy).previewWithdraw(assetsToWithdraw),
                    // And check against our actual balance
                    IERC4626Payable(strategy).balanceOf(address(this))
                );

                IERC4626Payable(strategy).redeem(sharesToRedeem, address(this), address(this));
                uint256 postBalance = IERC20(state.asset).balanceOf(address(this));

                // Always check against the real amounts
                uint256 withdrawn = postBalance - state.previousBalance;
                uint256 loss = 0;

                // Check if we redeemed too much
                if (withdrawn > assetsToWithdraw) {
                    // Make sure we don't underflow in debt updates
                    if (withdrawn > currentDebt) {
                        // Can't withdraw more than our debt
                        assetsToWithdraw = currentDebt;
                    } else {
                        // Add the extra to how much we withdrew
                        assetsToWithdraw += (withdrawn - assetsToWithdraw);
                    }
                }
                // If we have not received what we expected, consider the difference a loss
                else if (withdrawn < assetsToWithdraw) {
                    loss = assetsToWithdraw - withdrawn;
                }

                // Strategy's debt decreases by the full amount but total idle increases
                // by the actual amount only (as the difference is considered lost)
                state.currentTotalIdle += (assetsToWithdraw - loss);
                state.requestedAssets -= loss;
                state.currentTotalDebt -= assetsToWithdraw;

                // Vault will reduce debt because the unrealized loss has been taken by user
                uint256 newDebtAmount = currentDebt - (assetsToWithdraw + unrealisedLossesShare);

                // Update strategies storage
                _strategies[strategy].currentDebt = newDebtAmount;
                // Log the debt update
                emit DebtUpdated(strategy, currentDebt, newDebtAmount);

                // Break if we have enough total idle to serve initial request
                if (state.requestedAssets <= state.currentTotalIdle) {
                    break;
                }

                // Update previous balance for next iteration
                state.previousBalance = postBalance;

                // Reduce what we still need
                state.assetsNeeded -= assetsToWithdraw;
            }

            // If we exhaust the queue and still have insufficient total idle, revert
            require(state.currentTotalIdle >= state.requestedAssets, "insufficient assets in vault");
        }

        // Check if there is a loss and a non-default value was set
        if (assets > state.requestedAssets && maxLoss < MAX_BPS) {
            // Assure the loss is within the allowed range
            require(assets - state.requestedAssets <= (assets * maxLoss) / MAX_BPS, "too much loss");
        }

        // First burn the corresponding shares from the redeemer
        _burnShares(shares, owner);

        // Commit memory to storage
        totalIdle_ = state.currentTotalIdle - state.requestedAssets;
        totalDebt_ = state.currentTotalDebt;

        // Transfer the requested amount to the receiver
        _erc20SafeTransfer(state.asset, receiver, state.requestedAssets);

        emit Withdraw(sender, receiver, owner, state.requestedAssets, shares);
        return state.requestedAssets;
    }

    /**
     * @dev Revokes a strategy
     */
    function _revokeStrategy(address strategy, bool force) internal {
        require(_strategies[strategy].activation != 0, "strategy not active");

        if (_strategies[strategy].currentDebt != 0) {
            require(force, "strategy has debt");
            // Vault realizes the full loss of outstanding debt.
            uint256 loss = _strategies[strategy].currentDebt;
            // Adjust total vault debt.
            totalDebt_ -= loss;

            emit StrategyReported(strategy, 0, loss, 0, 0, 0, 0);
        }

        // Set strategy params all back to 0 (WARNING: it can be re-added).
        _strategies[strategy] = StrategyParams({ activation: 0, lastReport: 0, currentDebt: 0, maxDebt: 0 });

        // First count how many strategies we'll keep to properly size the new array
        uint256 strategiesInQueue = 0;
        bool strategyFound = false;

        for (uint256 i = 0; i < defaultQueue.length; i++) {
            if (defaultQueue[i] == strategy) {
                strategyFound = true;
            } else {
                strategiesInQueue++;
            }
        }

        // Only create a new queue if the strategy was actually in the queue
        if (strategyFound) {
            address[] memory newQueue = new address[](strategiesInQueue);
            uint256 j = 0;

            for (uint256 i = 0; i < defaultQueue.length; i++) {
                // Add all strategies to the new queue besides the one revoked
                if (defaultQueue[i] != strategy) {
                    newQueue[j] = defaultQueue[i];
                    j++;
                }
            }

            // Set the default queue to our updated queue
            defaultQueue = newQueue;
        }

        emit StrategyChanged(strategy, StrategyChangeType.REVOKED);
    }

    // DEBT MANAGEMENT //

    /**
     * @dev Updates debt for a strategy
     */
    function _updateDebt(address strategy, uint256 targetDebt, uint256 maxLoss) internal returns (uint256) {
        // How much we want the strategy to have.
        uint256 newDebt = targetDebt;
        // How much the strategy currently has.
        uint256 currentDebt = _strategies[strategy].currentDebt;
        // If the vault is shutdown we can only pull funds.
        if (shutdown_) {
            console.log("Vault is shutdown, setting new debt to 0");
            newDebt = 0;
        }

        require(newDebt != currentDebt, "new debt equals current debt");

        if (currentDebt > newDebt) {
            // Reducing debt - withdrawing from strategy
            newDebt = _decreaseStrategyDebt(strategy, currentDebt, newDebt, maxLoss);
        } else {
            // Increasing debt - depositing to strategy
            newDebt = _increaseStrategyDebt(strategy, currentDebt, newDebt);
        }

        // Commit memory to storage.
        _strategies[strategy].currentDebt = newDebt;

        emit DebtUpdated(strategy, currentDebt, newDebt);
        return newDebt;
    }

    /**
     * @dev Decreases a strategy's debt by withdrawing assets
     */
    function _decreaseStrategyDebt(
        address strategy,
        uint256 currentDebt,
        uint256 newDebt,
        uint256 maxLoss
    ) internal returns (uint256) {
        // Calculate how much to withdraw
        uint256 assetsToWithdraw = _calculateAssetsToWithdraw(strategy, currentDebt, newDebt);

        if (assetsToWithdraw == 0) {
            return currentDebt;
        }

        // Check for unrealized losses
        uint256 unrealisedLossesShare = _assessShareOfUnrealisedLosses(strategy, currentDebt, assetsToWithdraw);
        require(unrealisedLossesShare == 0, "strategy has unrealised losses");

        // Execute withdrawal and handle results
        return _executeWithdrawalAndUpdateDebt(strategy, currentDebt, assetsToWithdraw, maxLoss);
    }

    /**
     * @dev Calculate how much to withdraw from a strategy when decreasing debt
     */
    function _calculateAssetsToWithdraw(
        address strategy,
        uint256 currentDebt,
        uint256 newDebt
    ) internal view returns (uint256) {
        uint256 assetsToWithdraw = currentDebt - newDebt;

        // Ensure we always have minimumTotalIdle when updating debt.
        uint256 _minimumTotalIdle = minimumTotalIdle;
        uint256 totalIdleAmount = totalIdle_;

        // Respect minimum total idle in vault
        if (totalIdleAmount + assetsToWithdraw < _minimumTotalIdle) {
            assetsToWithdraw = _minimumTotalIdle - totalIdleAmount;
            // Cant withdraw more than the strategy has.
            if (assetsToWithdraw > currentDebt) {
                assetsToWithdraw = currentDebt;
            }
        }

        // Check how much we are able to withdraw.
        uint256 withdrawable = IERC4626Payable(strategy).convertToAssets(
            IERC4626Payable(strategy).maxRedeem(address(this))
        );

        // If insufficient withdrawable, withdraw what we can.
        if (withdrawable < assetsToWithdraw) {
            assetsToWithdraw = withdrawable;
        }

        return assetsToWithdraw;
    }

    /**
     * @dev Execute withdrawal and update accounting when decreasing debt
     */
    function _executeWithdrawalAndUpdateDebt(
        address strategy,
        uint256 currentDebt,
        uint256 assetsToWithdraw,
        uint256 maxLoss
    ) internal returns (uint256) {
        address _asset = asset;

        // Always check the actual amount withdrawn.
        uint256 preBalance = IERC20(_asset).balanceOf(address(this));
        _withdrawFromStrategy(strategy, assetsToWithdraw);
        uint256 postBalance = IERC20(_asset).balanceOf(address(this));

        // Calculate actual amount withdrawn
        uint256 withdrawn = Math.min(postBalance - preBalance, currentDebt);

        // Handle loss case
        if (withdrawn < assetsToWithdraw && maxLoss < MAX_BPS) {
            require(assetsToWithdraw - withdrawn <= (assetsToWithdraw * maxLoss) / MAX_BPS, "too much loss");
        }
        // Handle case where we got more than expected
        else if (withdrawn > assetsToWithdraw) {
            assetsToWithdraw = withdrawn;
        }

        // Update storage.
        totalIdle_ += withdrawn; // actual amount we got.
        totalDebt_ -= assetsToWithdraw;

        return currentDebt - assetsToWithdraw;
    }

    /**
     * @dev Increases a strategy's debt by depositing assets
     */
    function _increaseStrategyDebt(address strategy, uint256 currentDebt, uint256 newDebt) internal returns (uint256) {
        console.log("Increasing debt for strategy");
        console.log("Current debt", currentDebt);
        console.log("New debt", newDebt);
        // Apply max debt limit
        newDebt = _applyMaxDebtLimit(strategy, currentDebt, newDebt);

        console.log("New debt after applying max debt limit", newDebt);

        // Calculate assets to deposit respecting strategy and vault limits
        uint256 assetsToDeposit = _calculateAssetsToDeposit(strategy, currentDebt, newDebt);

        if (assetsToDeposit == 0) {
            return currentDebt;
        }

        // Execute deposit and update accounting
        return _executeDepositAndUpdateDebt(strategy, currentDebt, assetsToDeposit);
    }

    /**
     * @dev Apply max debt limit for a strategy
     */
    function _applyMaxDebtLimit(
        address strategy,
        uint256 currentDebt,
        uint256 newDebt
    ) internal view returns (uint256) {
        console.log("max debt", _strategies[strategy].maxDebt);
        if (newDebt > _strategies[strategy].maxDebt) {
            newDebt = _strategies[strategy].maxDebt;
            // Possible for current to be greater than max from reports.
            if (newDebt < currentDebt) {
                return currentDebt;
            }
        }

        // Check if strategy accepts deposits
        uint256 maxDepositAmount = IERC4626Payable(strategy).maxDeposit(address(this));
        if (maxDepositAmount == 0) {
            return currentDebt;
        }

        return newDebt;
    }

    /**
     * @dev Calculate assets to deposit respecting limits
     */
    function _calculateAssetsToDeposit(
        address strategy,
        uint256 currentDebt,
        uint256 newDebt
    ) internal view returns (uint256) {
        // Deposit the difference between desired and current.
        uint256 assetsToDeposit = newDebt - currentDebt;

        // Check strategy deposit limit
        uint256 maxDepositAmount = IERC4626Payable(strategy).maxDeposit(address(this));
        if (assetsToDeposit > maxDepositAmount) {
            assetsToDeposit = maxDepositAmount;
        }

        // Check vault minimum idle requirement
        uint256 _minimumTotalIdle = minimumTotalIdle;
        uint256 totalIdleAmount = totalIdle_;

        if (totalIdleAmount <= _minimumTotalIdle) {
            return 0;
        }

        uint256 availableIdleAmount = totalIdleAmount - _minimumTotalIdle;

        // If insufficient funds to deposit, transfer only what is free.
        if (assetsToDeposit > availableIdleAmount) {
            assetsToDeposit = availableIdleAmount;
        }

        return assetsToDeposit;
    }

    /**
     * @dev Execute deposit and update accounting
     */
    function _executeDepositAndUpdateDebt(
        address strategy,
        uint256 currentDebt,
        uint256 assetsToDeposit
    ) internal returns (uint256) {
        if (assetsToDeposit == 0) {
            return currentDebt;
        }

        address _asset = asset;

        // Approve the strategy to pull only what we are giving it.
        _erc20SafeApprove(_asset, strategy, assetsToDeposit);

        // Always update based on actual amounts deposited.
        uint256 preBalance = IERC20(_asset).balanceOf(address(this));
        IERC4626Payable(strategy).deposit(assetsToDeposit, address(this));
        uint256 postBalance = IERC20(_asset).balanceOf(address(this));

        // Make sure our approval is always back to 0.
        _erc20SafeApprove(_asset, strategy, 0);

        // Making sure we are changing according to the real result no matter what.
        assetsToDeposit = preBalance - postBalance;

        // Update storage.
        totalIdle_ -= assetsToDeposit;
        totalDebt_ += assetsToDeposit;

        return currentDebt + assetsToDeposit;
    }

    /// ACCOUNTING MANAGEMENT ///
    // Define the struct outside the function (class level)
    struct ReportData {
        uint256 totalAssets;
        uint256 currentDebt;
        uint256 gain;
        uint256 loss;
        uint256 totalFees;
        uint256 totalRefunds;
        uint256 totalFeesShares;
        uint16 protocolFeeBps;
        uint256 protocolFeesShares;
        address protocolFeeRecipient;
        uint256 sharesToBurn;
        uint256 sharesToLock;
        uint256 totalSupply;
        uint256 totalLockedShares;
        uint256 endingSupply;
        uint256 previouslyLockedTime;
        uint256 newProfitLockingPeriod;
    }

    /**
     * @dev Updates the profit unlocking rate and period based on locked shares
     * @param totalLockedShares The total shares locked in the vault
     * @param sharesToLock New shares being locked
     */
    function _updateProfitUnlocking(uint256 totalLockedShares, uint256 sharesToLock) internal {
        if (totalLockedShares > 0) {
            uint256 previouslyLockedTime = 0;
            uint256 _fullProfitUnlockDate = fullProfitUnlockDate_;

            // Check if we need to account for shares still unlocking
            if (_fullProfitUnlockDate > block.timestamp) {
                // There will only be previously locked shares if time remains.
                // We calculate this here since it will not occur every time we lock shares.
                previouslyLockedTime = (totalLockedShares - sharesToLock) * (_fullProfitUnlockDate - block.timestamp);
            }

            // new_profit_locking_period is a weighted average between the remaining time of the previously locked shares and the profit_max_unlock_time
            uint256 newProfitLockingPeriod = (previouslyLockedTime + sharesToLock * profitMaxUnlockTime_) /
                totalLockedShares;

            // Calculate how many shares unlock per second.
            profitUnlockingRate_ = (totalLockedShares * MAX_BPS_EXTENDED) / newProfitLockingPeriod;

            // Calculate how long until the full amount of shares is unlocked.
            fullProfitUnlockDate_ = block.timestamp + newProfitLockingPeriod;

            // Update the last profitable report timestamp.
            lastProfitUpdate_ = block.timestamp;
        } else {
            // NOTE: only setting this to 0 will have the desired effect,
            // no need to update profit_unlocking_rate
            fullProfitUnlockDate_ = 0;
        }
    }

    /**
     * @dev Assesses the gain or loss for a strategy based on its current assets vs. debt
     * @param strategy The address of the strategy to assess
     * @return totalAssetsAmount The total assets in the strategy
     * @return currentDebtAmount The current debt allocated to the strategy
     * @return gainAmount The amount of gain if any
     * @return lossAmount The amount of loss if any
     */
    function _assessStrategyGainOrLoss(
        address strategy
    )
        internal
        view
        returns (uint256 totalAssetsAmount, uint256 currentDebtAmount, uint256 gainAmount, uint256 lossAmount)
    {
        // Initialize gain and loss
        gainAmount = 0;
        lossAmount = 0;

        if (strategy != address(this)) {
            // Make sure we have a valid strategy.
            require(_strategies[strategy].activation != 0, "inactive strategy");

            // Vault assesses profits using 4626 compliant interface.
            // NOTE: It is important that a strategies `convertToAssets` implementation
            // cannot be manipulated or else the vault could report incorrect gains/losses.
            uint256 strategySharesAmount = IERC4626Payable(strategy).balanceOf(address(this));
            // How much the vaults position is worth.
            totalAssetsAmount = IERC4626Payable(strategy).convertToAssets(strategySharesAmount);
            // How much the vault had deposited to the strategy.
            currentDebtAmount = _strategies[strategy].currentDebt;
        } else {
            // Accrue any airdropped `asset` into `totalIdle`
            totalAssetsAmount = IERC20(asset).balanceOf(address(this));
            currentDebtAmount = totalIdle_;
        }

        // Compare reported assets vs. the current debt.
        if (totalAssetsAmount > currentDebtAmount) {
            // We have a gain.
            gainAmount = totalAssetsAmount - currentDebtAmount;
        } else {
            // We have a loss.
            lossAmount = currentDebtAmount - totalAssetsAmount;
        }

        return (totalAssetsAmount, currentDebtAmount, gainAmount, lossAmount);
    }

    /**
     * @dev Calculates fees and refunds for a strategy report
     * @param strategy The address of the strategy being reported
     * @param gain The amount of gain
     * @param loss The amount of loss
     * @return totalFees The total fees to be charged
     * @return totalRefunds The total refunds to be given
     * @return protocolFeeBps The protocol fee basis points
     * @return protocolFeeRecipient The address that will receive protocol fees
     */
    function _calculateFeesAndRefunds(
        address strategy,
        uint256 gain,
        uint256 loss
    ) internal returns (uint256 totalFees, uint256 totalRefunds, uint16 protocolFeeBps, address protocolFeeRecipient) {
        // Initialize fees and refunds
        totalFees = 0;
        totalRefunds = 0;
        protocolFeeBps = 0;
        protocolFeeRecipient = address(0);

        // If accountant is not set, fees and refunds remain unchanged.
        address _accountant = accountant;
        if (_accountant != address(0)) {
            (totalFees, totalRefunds) = IAccountant(_accountant).report(strategy, gain, loss);

            if (totalRefunds > 0) {
                // Make sure we have enough approval and enough asset to pull.
                totalRefunds = Math.min(
                    totalRefunds,
                    Math.min(IERC20(asset).balanceOf(_accountant), IERC20(asset).allowance(_accountant, address(this)))
                );
            }
        }

        // Get the protocol fee config for this vault if we have fees
        if (totalFees > 0) {
            (protocolFeeBps, protocolFeeRecipient) = IFactory(factory).protocolFeeConfig();
        }

        return (totalFees, totalRefunds, protocolFeeBps, protocolFeeRecipient);
    }

    /**
     * @dev Adjusts share balances, processes refunds, and updates accounting after strategy report
     * @param strategy The strategy being reported
     * @param gain Amount of gain reported
     * @param loss Amount of loss reported
     * @param currentDebt Current debt of the strategy
     * @param sharesToLock Shares to lock from profit
     * @param sharesToBurn Shares to burn from loss
     * @param totalRefunds Refunds amount from accountant
     * @param totalFeesShares Total shares to issue for fees
     * @param protocolFeesShares Portion of fee shares for protocol
     * @param protocolFeeRecipient Address to receive protocol fees
     * @return updatedCurrentDebt The updated current debt value
     * @return finalSharesToLock The final shares to lock after adjustments
     */
    function _adjustSharesAndUpdateAccounting(
        address strategy,
        uint256 gain,
        uint256 loss,
        uint256 currentDebt,
        uint256 sharesToLock,
        uint256 sharesToBurn,
        uint256 totalRefunds,
        uint256 totalFeesShares,
        uint256 protocolFeesShares,
        address protocolFeeRecipient
    ) internal returns (uint256 updatedCurrentDebt, uint256 finalSharesToLock) {
        // Adjust shares based on ending supply
        _adjustVaultShares(sharesToLock, sharesToBurn);

        // Calculate final shares to lock
        finalSharesToLock = _calculateFinalSharesToLock(sharesToLock, sharesToBurn);

        // Process refunds if any
        _processRefunds(totalRefunds);

        // Update debt based on gain or loss
        updatedCurrentDebt = _updateDebtForReport(strategy, currentDebt, gain, loss, totalRefunds);

        // Issue fee shares if any
        _issueFeeShares(totalFeesShares, protocolFeesShares, protocolFeeRecipient);

        _strategies[strategy].lastReport = block.timestamp;

        return (updatedCurrentDebt, finalSharesToLock);
    }

    // Helper functions:

    function _adjustVaultShares(uint256 sharesToLock, uint256 sharesToBurn) internal {
        uint256 totalSupplyAmount = totalSupply_;
        uint256 totalLockedSharesAmount = balanceOf_[address(this)];
        uint256 endingSupplyAmount = totalSupplyAmount + sharesToLock - sharesToBurn - _unlockedShares();

        if (endingSupplyAmount > totalSupplyAmount) {
            _issueShares(endingSupplyAmount - totalSupplyAmount, address(this));
        } else if (totalSupplyAmount > endingSupplyAmount) {
            uint256 toBurnAmount = Math.min(totalSupplyAmount - endingSupplyAmount, totalLockedSharesAmount);
            _burnShares(toBurnAmount, address(this));
        }
    }

    function _calculateFinalSharesToLock(uint256 sharesToLock, uint256 sharesToBurn) internal pure returns (uint256) {
        if (sharesToLock > sharesToBurn) {
            return sharesToLock - sharesToBurn;
        }
        return 0;
    }

    /**
     * @dev Process refunds from accountant
     */
    function _processRefunds(uint256 totalRefunds) internal {
        if (totalRefunds > 0) {
            _erc20SafeTransferFrom(asset, accountant, address(this), totalRefunds);
            totalIdle_ += totalRefunds;
        }
    }

    /**
     * @dev Updates debt based on gain or loss from a report
     */
    function _updateDebtForReport(
        address strategy,
        uint256 currentDebt,
        uint256 gain,
        uint256 loss,
        uint256 totalRefunds
    ) internal returns (uint256 updatedCurrentDebt) {
        updatedCurrentDebt = currentDebt;

        if (gain > 0) {
            updatedCurrentDebt = currentDebt + gain;
            if (strategy != address(this)) {
                _strategies[strategy].currentDebt = updatedCurrentDebt;
                totalDebt_ += gain;
            } else {
                updatedCurrentDebt = currentDebt + gain + totalRefunds;
                totalIdle_ = updatedCurrentDebt;
            }
        } else if (loss > 0) {
            updatedCurrentDebt = currentDebt - loss;
            if (strategy != address(this)) {
                _strategies[strategy].currentDebt = updatedCurrentDebt;
                totalDebt_ -= loss;
            } else {
                updatedCurrentDebt = currentDebt + totalRefunds;
                totalIdle_ = updatedCurrentDebt;
            }
        }

        return updatedCurrentDebt;
    }

    /**
     * @dev Issue shares for fees
     */
    function _issueFeeShares(
        uint256 totalFeesShares,
        uint256 protocolFeesShares,
        address protocolFeeRecipient
    ) internal {
        if (totalFeesShares > 0) {
            _issueShares(totalFeesShares - protocolFeesShares, accountant);

            if (protocolFeesShares > 0) {
                _issueShares(protocolFeesShares, protocolFeeRecipient);
            }
        }
    }

    /**
     * @dev Get the appropriate strategy queue based on parameters
     */
    function _getStrategyQueue(address[] memory strategiesParam) internal view returns (address[] memory) {
        if (strategiesParam.length != 0 && !useDefaultQueue) {
            return strategiesParam;
        }
        return defaultQueue;
    }

    /**
     * @dev Calculate how much can be withdrawn from a strategy
     * @return withdrawable The amount that can be withdrawn
     * @return unrealizedLoss The unrealized loss that would be taken
     */
    function _calculateStrategyWithdrawal(
        address strategyAddress,
        uint256 needed,
        uint256 have,
        uint256 maxLoss,
        uint256 currentLoss
    ) internal view returns (uint256 withdrawable, uint256 unrealizedLoss) {
        uint256 currentDebt = _strategies[strategyAddress].currentDebt;

        // Calculate how much to withdraw from this strategy
        uint256 toWithdraw = Math.min(needed, currentDebt);

        // Get any unrealized loss for the strategy
        unrealizedLoss = _assessShareOfUnrealisedLosses(strategyAddress, currentDebt, toWithdraw);

        // Check strategy limits
        withdrawable = _applyStrategyWithdrawLimits(strategyAddress, toWithdraw, unrealizedLoss);

        // If nothing to withdraw or exceeds max loss, return 0
        if (withdrawable == 0) {
            return (0, 0);
        }

        // Check if loss exceeds max loss setting
        if (unrealizedLoss > 0 && maxLoss < MAX_BPS) {
            if (_exceedsMaxLoss(currentLoss, unrealizedLoss, have, withdrawable, maxLoss)) {
                return (0, 0);
            }
        }

        return (withdrawable, unrealizedLoss);
    }

    /**
     * @dev Apply strategy withdrawal limits
     */
    function _applyStrategyWithdrawLimits(
        address strategyAddress,
        uint256 toWithdraw,
        uint256 unrealizedLoss
    ) internal view returns (uint256) {
        // Check strategy's actual limit
        uint256 strategyLimit = IERC4626Payable(strategyAddress).convertToAssets(
            IERC4626Payable(strategyAddress).maxRedeem(address(this))
        );

        // Calculate what can be actually withdrawn without loss
        uint256 realizableWithdraw = toWithdraw - unrealizedLoss;

        // If strategy limit is less than what we want to withdraw
        if (strategyLimit < realizableWithdraw) {
            // Scale down unrealized loss proportionally
            if (unrealizedLoss != 0) {
                unrealizedLoss = (unrealizedLoss * strategyLimit) / realizableWithdraw;
            }

            // Adjust total withdrawal
            toWithdraw = strategyLimit + unrealizedLoss;
        }

        return toWithdraw;
    }

    /**
     * @dev Check if total loss exceeds max loss percentage
     */
    function _exceedsMaxLoss(
        uint256 currentLoss,
        uint256 newLoss,
        uint256 currentAssets,
        uint256 newAssets,
        uint256 maxLoss
    ) internal pure returns (bool) {
        return currentLoss + newLoss > ((currentAssets + newAssets) * maxLoss) / MAX_BPS;
    }
}
