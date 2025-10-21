// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

/**
 * @title MultistrategyVault Interface
 * @author yearn.finance; adapted by [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Interface for MultistrategyVault ERC4626-compliant vault with multiple strategies
 * @dev Defines all external functions, events, errors, and types for the vault
 */
interface IMultistrategyVault {
    // ============================================
    // ERRORS
    // ============================================

    /// @notice Thrown when attempting to initialize an already initialized vault
    error AlreadyInitialized();

    /// @notice Thrown when operating on an already shutdown vault where operation is not allowed
    error AlreadyShutdown();

    /// @notice Thrown when a zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when profit unlock time exceeds maximum (1 year)
    error ProfitUnlockTimeTooLong();

    /// @notice Thrown when caller lacks required role permissions
    error NotAllowed();

    /// @notice Thrown when caller is not the pending future role manager
    error NotFutureRoleManager();

    /// @notice Thrown when account has insufficient balance for operation
    error InsufficientFunds();

    /// @notice Thrown when permit owner is invalid
    error InvalidOwner();

    /// @notice Thrown when permit signature has expired
    error PermitExpired();

    /// @notice Thrown when permit signature is invalid
    error InvalidSignature();

    /// @notice Thrown when attempting to add zero address as strategy
    error StrategyCannotBeZeroAddress();

    /// @notice Thrown when strategy asset doesn't match vault asset
    error InvalidAsset();

    /// @notice Thrown when operating on a strategy that hasn't been added
    error InactiveStrategy();

    /// @notice Thrown when attempting to add a strategy that's already active
    error StrategyAlreadyActive();

    /// @notice Thrown when attempting to revoke a non-active strategy
    error StrategyNotActive();

    /// @notice Thrown in buyDebt when strategy has no debt to purchase
    error NothingToBuy();

    /// @notice Thrown in buyDebt when no assets provided for purchase
    error NothingToBuyWith();

    /// @notice Thrown when strategy doesn't have enough debt for operation
    error NotEnoughDebt();

    /// @notice Thrown in buyDebt when purchase would result in zero shares
    error CannotBuyZero();

    /// @notice Thrown in updateDebt when new debt equals current (no-op)
    error NewDebtEqualsCurrentDebt();

    /// @notice Thrown when attempting debt reduction while strategy has unrealized losses
    error StrategyHasUnrealisedLosses();

    /// @notice Thrown when withdrawal loss exceeds maxLoss tolerance
    error TooMuchLoss();

    /// @notice Thrown when ERC20 approval operation fails
    error ApprovalFailed();

    /// @notice Thrown when ERC20 transfer operation fails
    error TransferFailed();

    /// @notice Thrown when attempting deposit on shutdown vault
    error VaultShutdown();

    /// @notice Thrown when attempting to set depositLimit while depositLimitModule is active
    error UsingModule();

    /// @notice Thrown when attempting to set depositLimitModule while depositLimit is set
    error UsingDepositLimit();

    /// @notice Thrown when attempting to add strategy to full withdrawal queue (max 10)
    error MaxQueueLengthReached();

    /// @notice Thrown when deposit would exceed configured limit
    error ExceedDepositLimit();

    /// @notice Thrown when attempting to deposit zero assets
    error CannotDepositZero();

    /// @notice Thrown when attempting to mint zero shares
    error CannotMintZero();

    /// @notice Thrown when attempting withdrawal with zero assets
    error NoAssetsToWithdraw();

    /// @notice Thrown when maxLoss parameter exceeds MAX_BPS (10000)
    error MaxLossExceeded();

    /// @notice Thrown when withdrawal would exceed configured limit
    error ExceedWithdrawLimit();

    /// @notice Thrown when owner has insufficient shares for redemption
    error InsufficientSharesToRedeem();

    /// @notice Thrown when vault doesn't have enough assets to fulfill withdrawal
    error InsufficientAssetsInVault();

    /// @notice Thrown when attempting to revoke strategy that still has debt
    error StrategyHasDebt();

    /// @notice Thrown when receiver address is invalid (vault or zero)
    error InvalidReceiver();

    /// @notice Thrown when spender has insufficient allowance
    error InsufficientAllowance();

    /// @notice Thrown when reentrancy is detected
    error Reentrancy();

    /// @notice Thrown when attempting to redeem zero shares
    error NoSharesToRedeem();

    // ============================================
    // ENUMS
    // ============================================

    /**
     * @notice Roles for permissioned vault operations
     * @dev Roles are bitmasked - multiple roles can be combined for a single address
     *      Each role grants specific privileges. Set via setRole, addRole, removeRole
     */
    enum Roles {
        /// @notice Can add new strategies to vault via addStrategy()
        ADD_STRATEGY_MANAGER,
        /// @notice Can remove strategies (soft revoke, requires 0 debt) via revokeStrategy()
        REVOKE_STRATEGY_MANAGER,
        /// @notice Can force remove strategies (hard revoke, realizes losses) via forceRevokeStrategy()
        FORCE_REVOKE_MANAGER,
        /// @notice Can set accountant contract for fee assessment via setAccountant()
        ACCOUNTANT_MANAGER,
        /// @notice Can set default withdrawal queue via setDefaultQueue()
        QUEUE_MANAGER,
        /// @notice Can call processReport() to update strategy accounting
        REPORTING_MANAGER,
        /// @notice Can call updateDebt() to rebalance strategy allocations
        DEBT_MANAGER,
        /// @notice Can set maximum debt limit per strategy via updateMaxDebtForStrategy()
        MAX_DEBT_MANAGER,
        /// @notice Can set deposit limits via setDepositLimit() and setDepositLimitModule()
        DEPOSIT_LIMIT_MANAGER,
        /// @notice Can set withdrawal limits via setWithdrawLimitModule()
        WITHDRAW_LIMIT_MANAGER,
        /// @notice Can set minimum idle reserves via setMinimumTotalIdle()
        MINIMUM_IDLE_MANAGER,
        /// @notice Can set profit unlock duration via setProfitMaxUnlockTime()
        PROFIT_UNLOCK_MANAGER,
        /// @notice Can purchase bad debt via buyDebt() in emergencies
        DEBT_PURCHASER,
        /// @notice Can permanently shutdown vault via shutdownVault()
        EMERGENCY_MANAGER
    }

    /**
     * @notice Type of strategy modification
     * @dev Used in StrategyChanged event
     */
    enum StrategyChangeType {
        /// @notice Strategy was added to vault
        ADDED,
        /// @notice Strategy was revoked from vault
        REVOKED
    }

    /**
     * @notice Rounding direction for share/asset conversions
     * @dev Determines rounding behavior in mathematical operations
     *      ROUND_DOWN favors vault (deposits), ROUND_UP favors user (withdrawals)
     */
    enum Rounding {
        /// @notice Round down (floor): Favors vault in conversions
        ROUND_DOWN,
        ROUND_UP
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Variables for the maxWithdraw function.
     */
    struct MaxWithdrawVars {
        uint256 maxAssets;
        uint256 currentIdle;
        uint256 have;
        uint256 loss;
        address[] withdrawalStrategies;
    }

    /**
     * @notice Variables for the processReport function.
     */
    struct ProcessReportVars {
        address asset;
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
        uint256 profitMaxUnlockTime;
        uint256 totalSupply;
        uint256 totalLockedShares;
        uint256 endingSupply;
        uint256 toBurn;
        uint256 previouslyLockedTime;
        uint256 fullProfitUnlockDate;
        uint256 newProfitLockingPeriod;
    }
    /**
     * @notice Parameters for a strategy.
     * @param activation Timestamp when the strategy was added.
     * @param lastReport Timestamp of the strategies last report.
     * @param currentDebt The current assets the strategy holds.
     * @param maxDebt The max assets the strategy can hold.
     */
    struct StrategyParams {
        uint256 activation;
        uint256 lastReport;
        uint256 currentDebt;
        uint256 maxDebt;
    }

    /**
     * @notice Variables for the processReport function.
     */
    struct ProcessReportLocalVars {
        uint256 strategyTotalAssets;
        uint256 currentDebt;
        uint256 gain;
        uint256 loss;
        uint256 totalFees;
        uint256 totalRefunds;
        address accountant;
        uint256 totalFeesShares;
        uint16 protocolFeeBps;
        uint256 protocolFeesShares;
        address protocolFeeRecipient;
        uint256 sharesToBurn;
        uint256 sharesToLock;
        uint256 profitMaxUnlockTimeVar;
        uint256 currentTotalSupply;
        uint256 totalLockedShares;
        uint256 endingSupply;
        uint256 toBurn;
        uint256 previouslyLockedTime;
        uint256 fullProfitUnlockDateVar;
        uint256 newProfitLockingPeriod;
    }

    /**
     * @notice State for a redeem operation.
     * @param requestedAssets The requested assets to redeem.
     * @param currentTotalIdle The current total idle of the vault.
     * @param currentTotalDebt The current total debt of the vault.
     * @param asset The asset of the vault.
     * @param withdrawalStrategies The strategies to withdraw from.
     * @param assetsNeeded The assets needed to fulfill the redeem request.
     * @param previousBalance The previous balance of the vault.
     */
    struct RedeemState {
        uint256 requestedAssets;
        uint256 currentTotalIdle;
        uint256 currentTotalDebt;
        address asset;
        address[] withdrawalStrategies;
        uint256 assetsNeeded;
        uint256 previousBalance;
    }

    /**
     * @notice Variables for the updateDebt function.
     */
    struct UpdateDebtVars {
        uint256 newDebt; // Target debt we want the strategy to have
        uint256 currentDebt; // Current debt the strategy has
        uint256 assetsToWithdraw; // Amount to withdraw when decreasing debt
        uint256 assetsToDeposit; // Amount to deposit when increasing debt
        uint256 minimumTotalIdle; // Minimum amount to keep in vault
        uint256 totalIdle; // Current amount in vault
        uint256 availableIdle; // Amount available for deposits
        uint256 maxDebt; // Maximum debt for the strategy
        uint256 maxDepositAmount; // Maximum amount strategy can accept
        uint256 maxRedeemAmount; // Maximum amount strategy can redeem
        uint256 withdrawable; // Amount that can be withdrawn
        uint256 preBalance; // Balance before operation
        uint256 postBalance; // Balance after operation
        uint256 actualAmount; // Actual amount moved
        bool isDebtDecrease; // Whether debt is being decreased
        address _asset; // Cached asset address
        uint256 unrealisedLossesShare; // Any unrealized losses
    }

    /**
     * @notice State for a withdrawal operation.
     * @param requestedAssets The requested assets to withdraw.
     * @param currentTotalIdle The current total idle of the vault.
     * @param currentTotalDebt The current total debt of the vault.
     * @param assetsNeeded The assets needed to fulfill the withdrawal request.
     * @param previousBalance The previous balance of the vault.
     */
    struct WithdrawalState {
        uint256 requestedAssets;
        uint256 currentTotalIdle;
        uint256 currentTotalDebt;
        uint256 assetsNeeded;
        uint256 previousBalance;
        uint256 currentDebt;
        uint256 assetsToWithdraw;
        uint256 maxWithdraw;
        uint256 unrealisedLossesShare;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // ERC4626 EVENTS
    /// @notice Emitted when assets are deposited and shares minted
    /// @param sender The caller that initiated the deposit
    /// @param owner The address receiving the minted shares
    /// @param assets The amount of assets deposited
    /// @param shares The amount of shares minted
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    /// @notice Emitted when shares are redeemed and assets withdrawn
    /// @param sender The caller that initiated the withdrawal
    /// @param receiver The address receiving the withdrawn assets
    /// @param owner The owner whose shares were burned
    /// @param assets The amount of assets withdrawn
    /// @param shares The amount of shares burned
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    // ERC20 EVENTS
    /// @notice Emitted when tokens are transferred
    /// @param sender Address tokens are transferred from
    /// @param receiver Address tokens are transferred to
    /// @param value Amount of tokens transferred
    event Transfer(address indexed sender, address indexed receiver, uint256 value);
    /// @notice Emitted when allowance is set
    /// @param owner Token owner granting allowance
    /// @param spender Address granted spending allowance
    /// @param value Allowance amount
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // STRATEGY EVENTS
    /// @notice Emitted when a strategy is added to or revoked from the vault
    /// @param strategy The strategy address
    /// @param change_type The type of change (ADDED or REVOKED)
    event StrategyChanged(address indexed strategy, StrategyChangeType indexed change_type);
    /// @notice Emitted when a strategy report is processed
    /// @param strategy The strategy address that reported
    /// @param gain Reported profit amount
    /// @param loss Reported loss amount
    /// @param currentDebt Strategy debt after accounting
    /// @param protocolFees Protocol fees (if any)
    /// @param totalFees Total fees paid (including protocol fees)
    /// @param totalRefunds Refunds credited back to the vault
    event StrategyReported(
        address indexed strategy,
        uint256 gain,
        uint256 loss,
        uint256 currentDebt,
        uint256 protocolFees,
        uint256 totalFees,
        uint256 totalRefunds
    );

    // DEBT MANAGEMENT EVENTS
    /// @notice Emitted when a strategy's debt is updated
    /// @param strategy The strategy address
    /// @param currentDebt The previous debt value
    /// @param newDebt The new debt value
    event DebtUpdated(address indexed strategy, uint256 currentDebt, uint256 newDebt);

    // ROLE UPDATES
    /// @notice Emitted when role is set for an account
    /// @param account Account address
    /// @param role Role bitmask
    event RoleSet(address indexed account, uint256 indexed role);

    // STORAGE MANAGEMENT EVENTS
    /// @notice Emitted when future role manager is proposed
    /// @param futureRoleManager Proposed role manager address
    event UpdateFutureRoleManager(address indexed futureRoleManager);
    /// @notice Emitted when role manager is updated
    /// @param roleManager New role manager address
    event UpdateRoleManager(address indexed roleManager);
    /// @notice Emitted when accountant is updated
    /// @param accountant New accountant address
    event UpdateAccountant(address indexed accountant);
    /// @notice Emitted when deposit limit module is updated
    /// @param depositLimitModule New deposit limit module address
    event UpdateDepositLimitModule(address indexed depositLimitModule);
    /// @notice Emitted when withdraw limit module is updated
    /// @param withdrawLimitModule New withdraw limit module address
    event UpdateWithdrawLimitModule(address indexed withdrawLimitModule);
    /// @notice Emitted when default withdrawal queue is updated
    /// @param newDefaultQueue Array of strategy addresses in new queue order
    event UpdateDefaultQueue(address[] newDefaultQueue);
    /// @notice Emitted when useDefaultQueue flag is toggled
    /// @param useDefaultQueue True if default queue is enabled
    event UpdateUseDefaultQueue(bool useDefaultQueue);
    /// @notice Emitted when autoAllocate flag is toggled
    /// @param autoAllocate True if auto-allocation is enabled
    event UpdateAutoAllocate(bool autoAllocate);
    /// @notice Emitted when maximum debt for a strategy is updated
    /// @param sender Address that initiated the update
    /// @param strategy Strategy address
    /// @param newDebt New maximum debt in asset base units
    event UpdatedMaxDebtForStrategy(address indexed sender, address indexed strategy, uint256 newDebt);
    /// @notice Emitted when deposit limit is updated
    /// @param depositLimit New deposit limit in asset base units
    event UpdateDepositLimit(uint256 depositLimit);
    /// @notice Emitted when minimum total idle is updated
    /// @param minimumTotalIdle New minimum idle amount in asset base units
    event UpdateMinimumTotalIdle(uint256 minimumTotalIdle);
    /// @notice Emitted when profit unlock time is updated
    /// @param profitMaxUnlockTime New profit unlock time in seconds
    event UpdateProfitMaxUnlockTime(uint256 profitMaxUnlockTime);
    /// @notice Emitted when debt is purchased from a strategy
    /// @param strategy Strategy whose debt was purchased
    /// @param amount Amount of debt purchased in asset base units
    event DebtPurchased(address indexed strategy, uint256 amount);
    /// @notice Emitted when vault is permanently shut down
    event Shutdown();

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    // NOTE: The following functions are declared for interface completeness where
    // some implementations may expose equivalent public state variables.
    function strategies(address strategy) external view returns (StrategyParams memory);
    function defaultQueue() external view returns (address[] memory);
    function useDefaultQueue() external view returns (bool);
    function autoAllocate() external view returns (bool);
    function minimumTotalIdle() external view returns (uint256);
    function depositLimit() external view returns (uint256);
    function accountant() external view returns (address);
    function depositLimitModule() external view returns (address);
    function withdrawLimitModule() external view returns (address);
    function roles(address) external view returns (uint256);
    function roleManager() external view returns (address);
    function futureRoleManager() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function isShutdown() external view returns (bool);
    function unlockedShares() external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function nonces(address owner) external view returns (uint256);

    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function totalIdle() external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function balanceOf(address addr) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);

    function maxDeposit(address receiver) external view returns (uint256);
    function maxMint(address receiver) external view returns (uint256);
    function maxWithdraw(address owner, uint256 maxLoss, address[] calldata strategies) external view returns (uint256);
    function maxRedeem(address owner, uint256 maxLoss, address[] calldata strategies) external view returns (uint256);

    function FACTORY() external view returns (address);
    function apiVersion() external pure returns (string memory);
    function assessShareOfUnrealisedLosses(
        address strategy,
        uint256 currentDebt,
        uint256 assetsNeeded
    ) external view returns (uint256);

    function profitMaxUnlockTime() external view returns (uint256);
    function fullProfitUnlockDate() external view returns (uint256);
    function profitUnlockingRate() external view returns (uint256);
    function lastProfitUpdate() external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                           MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address asset,
        string memory name,
        string memory symbol,
        address roleManager,
        uint256 profitMaxUnlockTime
    ) external;

    // ERC20 & ERC4626 Functions
    function deposit(uint256 assets, address receiver) external returns (uint256);
    // function mint(uint256 shares, address receiver) external returns (uint256);
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategies
    ) external returns (uint256);
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategies
    ) external returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address receiver, uint256 amount) external returns (bool);
    function transferFrom(address sender, address receiver, uint256 amount) external returns (bool);
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool);

    // Management Functions
    function setName(string memory name) external;
    function setSymbol(string memory symbol) external;
    function setAccountant(address newAccountant) external;
    function setDefaultQueue(address[] calldata newDefaultQueue) external;
    function setUseDefaultQueue(bool useDefaultQueue) external;
    function setAutoAllocate(bool autoAllocate) external;
    function setDepositLimit(uint256 depositLimit, bool shouldOverride) external;
    function setDepositLimitModule(address depositLimitModule, bool shouldOverride) external;
    function setWithdrawLimitModule(address withdrawLimitModule) external;
    function setMinimumTotalIdle(uint256 minimumTotalIdle) external;
    function setProfitMaxUnlockTime(uint256 newProfitMaxUnlockTime) external;

    // Role Management
    function setRole(address account, uint256 roles) external;
    function addRole(address account, Roles role) external;
    function removeRole(address account, Roles role) external;
    function transferRoleManager(address roleManager) external;
    function acceptRoleManager() external;

    // Reporting Management
    function processReport(address strategy) external returns (uint256, uint256);
    function buyDebt(address strategy, uint256 amount) external;

    // Strategy Management
    function addStrategy(address newStrategy, bool addToQueue) external;
    function revokeStrategy(address strategy) external;
    function forceRevokeStrategy(address strategy) external;

    // Debt Management
    function updateMaxDebtForStrategy(address strategy, uint256 newMaxDebt) external;
    function updateDebt(address strategy, uint256 targetDebt, uint256 maxLoss) external returns (uint256);

    // Emergency Management
    function shutdownVault() external;
}
