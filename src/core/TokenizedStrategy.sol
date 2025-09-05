// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**$$$$$$$$$$$$$$$$$$$$$$$$$$$&Mr/|1+~>>iiiiiiiiiii>~+{|tuMW$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$B#j]->iiiiiiiiiiiiiiiiiiiiiiiiiiii>-?f*B$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$@zj}~iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii~}fv@$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$@z(+iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii+)zB$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$Mf~iiiiiiiiiiiiiiiiiii   iiiiiiiiiiiiiiiiiiiiiiiiiiiiii~t#@$$$$$$$$$$$$$$$
$$$$$$$$$$$$$@u[iiiiiiiiiiiiiiiiiii           ii   iiiiiiiiiiiiiiiiiiiiiii?n@$$$$$$$$$$$$$
$$$$$$$$$$$@z]iiiiiiiiiiiiiiiiii                     iiiiiiiiiiiiiiiiiiiiiii?u@$$$$$$$$$$$
$$$$$$$$$$v]iiiiiiiiiiiiiiiii        .-'   `'.      iiiiiiiiiiiiiiiiiiiiiiiiii?u$$$$$$$$
$$$$$$$$%)>iiiiiiiiiiiiiiiiii       /         \       iiiiiiiiiiiiiiiiiiiiiiiiii1%$$$$$$$$
$$$$$$$c~iiiiiiiiiiiiiiiiiiiiii     |         ;       iiiiiiiiiiiiiiiiiiiiiiiii>)%$$$$$$$$
$$$$$B/>iiiiiiiiiiiiiiiiiii         |         |           ___.--,  iiiiiiiiiiiiiii~c$$$$$$
$$$$@)iiiiiiiiiiiiiii      _.._     |0) ~ (0) |    _.---'`__.-( (_. iiiiiiiiiiiiiii/>B$$$$
$$$B|iiiiiiiiiiiii  __.--'`_.. '.__.\    '--. \_.-' ,.--'`     `""` iiiiiiiiiiiiiiii(@$$$$
$$@)iiiiiiiiiii    ( ,.--'`   ',__ /` ;   `, '.__.'`    __        iiiiiiiiiiiiiiiiiii($$$$
$$$)iiiiiiiiiiii   _`) )  .---.__.' / ;   |\   \__..--""  """--.,_   iiiiiiiiiiiiiiiii@$$$
$$%iiiiiiiiii    `---'  ' ''-._.-'` ./  /\ '.  \ _.-~~~````~~~-._`-.__.'iiiiiiiiiiiii\$$$$
$$@iiiiiiiiiiiiiiiiii   | |  .' _.-' |  |   \  \  '.               `~---`iiiiiiiiiiiiii$$$
$${[iiiiiiiiiiiiiii      \ \/ .'     \  \    '. '-._)               iiiiiiiiiiiiiiiiii~$$$
$$uiiiiiiiiiiiiiiiiiii    \/ /        \  \     `=.__`~-       iiiiiiiiiiiiiiiiiiiiiii$$$$$
$$@iiiiiiiiiiiiiiiiii      / /\         `) )     / / `"".`\     iiiiiiiiiiiiiiiiiiiii|B$$$
$$@\iiiiiiiiiiiiiiiii ,_.-'.'\ \        / /     ( (     / /     iiiiiiiiiiiiiiiiiiii(@$$$$
$$$$$iiiiiiiiiiiiiii `--~`   ) )    .-'.'       '.'.  | (      iiiiiiiiiiiiiiiiiiii/>B$$$$
$$$$@iiiiiiiiiiiiiiii       (/`    ( (`      i    ) )  '-;        iiiiiiiiiiiiiiii~c$$$$$$
$$$$$B]iiiiiiiiiiiiiiii      `   i  '-;      ii   (-'          iiiiiiiiiiiiiiiiii>)%$$$$$$
4$$$$$$$B)iiiiiiiiiiiii  iiii!i             iii           liiiiiiiiiiiiiiiiiiiii1%$$$$$$$$
$$$$$$$$$$@u]iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii-x@$$$$$$$
$$$$$$$$$$$@v?iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii-x$$$$$$$$$$$
$$$$$$$$$$$$$$@n?iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii-rB$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$/~iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii<\*@$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$Bc1~iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii~{v%$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$Bvf]<iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii<]tuB$$$$$$$$$$$$$$$$$$$$
4$$$$$$$$$$$$$$$$$$$$$$$$$%zt-+>iiiiiiiiiiiiiiiiiiiiiiiiiiiii+_tc%$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$W#u/|{+~>iiiiiiiiiiii><+{|/n#W$$$$$$$$$$$$$$$$$$$$$$$$$$$$*/

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBaseStrategy } from "src/core/interfaces/IBaseStrategy.sol";

/**
 * @title Tokenized Strategy (Octant V2 Fork)
 * @author yearn.finance; forked and modified by octant.finance
 * @notice
 *  This TokenizedStrategy is a fork of Yearn's TokenizedStrategy that has been
 *  modified by Octant to support donation functionality and other security enhancements.
 *
 *  The original contract can be used by anyone wishing to easily build
 *  and deploy their own custom ERC4626 compliant single strategy Vault.
 *
 *  The TokenizedStrategy contract is meant to be used as the proxy
 *  implementation contract that will handle all logic, storage and
 *  management for a custom strategy that inherits the `BaseStrategy`.
 *  Any function calls to the strategy that are not defined within that
 *  strategy will be forwarded through a delegateCall to this contract.
 *
 *  A strategist only needs to override a few simple functions that are
 *  focused entirely on the strategy specific needs to easily and cheaply
 *  deploy their own permissionless 4626 compliant vault.
 *
 *  @dev Changes from Yearn V3:
 *  - Added dragonRouter to the StrategyData struct to enable yield distribution
 *  - Added getter and setter for dragonRouter
 *  - Added validation checks for all critical addresses (management, keeper, emergencyAdmin, dragonRouter)
 *  - Enhanced initialize function to include emergencyAdmin and dragonRouter parameters
 *  - Standardized error messages for zero-address checks
 *  - Removed the yield/profit unlocking mechanism (profits are immediately realized)
 *  - Made the report() function virtual to enable specialized implementations
 *  - Made this contract abstract as a base for specialized strategy implementations
 *
 *  Two specialized implementations are provided:
 *  - YieldDonatingTokenizedStrategy: Mints profits as new shares and sends them to a specified dragon router
 *  - YieldSkimmingTokenizedStrategy: Skims the appreciation of asset and dilutes the original shares by minting new ones to the dragon router
 *
 *  WARNING: When creating custom strategies, DO NOT declare state variables outside
 *  the StrategyData struct. Doing so risks storage collisions if the implementation
 *  contract changes. Either extend the StrategyData struct or use a custom storage slot.
 */
abstract contract TokenizedStrategy {
    using Math for uint256;
    using SafeERC20 for ERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Emitted when a strategy is shutdown.
     */
    event StrategyShutdown();

    /**
     * @notice Emitted on the initialization of any new `strategy` that uses `asset`
     * with this specific `apiVersion`.
     */
    event NewTokenizedStrategy(address indexed strategy, address indexed asset, string apiVersion);

    /**
     * @notice Emitted when the strategy reports `profit` or `loss`.
     */
    event Reported(uint256 profit, uint256 loss);

    /**
     * @notice Emitted when the 'keeper' address is updated to 'newKeeper'.
     */
    event UpdateKeeper(address indexed newKeeper);

    /**
     * @notice Emitted when the 'management' address is updated to 'newManagement'.
     */
    event UpdateManagement(address indexed newManagement);

    /**
     * @notice Emitted when the 'emergencyAdmin' address is updated to 'newEmergencyAdmin'.
     */
    event UpdateEmergencyAdmin(address indexed newEmergencyAdmin);

    /**
     * @notice Emitted when the `pendingManagement` address is updated to `newPendingManagement`.
     */
    event UpdatePendingManagement(address indexed newPendingManagement);

    /**
     * @notice Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @notice Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @notice Emitted when the `caller` has exchanged `assets` for `shares`,
     * and transferred those `shares` to `owner`.
     */
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when the `caller` has exchanged `owner`s `shares` for `assets`,
     * and transferred those `assets` to `receiver`.
     */
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /**
     * @notice Emitted when the dragon router address is updated.
     */
    event UpdateDragonRouter(address indexed newDragonRouter);

    /**
     * @notice Emitted when a pending dragon router change is initiated.
     */
    event PendingDragonRouterChange(address indexed newDragonRouter, uint256 effectiveTimestamp);

    /**
     * @notice Emitted when the burning mechanism is enabled or disabled.
     */
    event UpdateBurningMechanism(bool enableBurning);

    /*//////////////////////////////////////////////////////////////
                        STORAGE STRUCT
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The struct that will hold all the storage data for each strategy
     * that uses this implementation.
     *
     * This replaces all state variables for a traditional contract. This
     * full struct will be initialized on the creation of the strategy
     * and continually updated and read from for the life of the contract.
     *
     * We combine all the variables into one struct to limit the amount of
     * times the custom storage slots need to be loaded during complex functions.
     *
     * Loading the corresponding storage slot for the struct does not
     * load any of the contents of the struct into memory. So the size
     * will not increase memory related gas usage.
     */
    // prettier-ignore
    // solhint-disable gas-struct-packing, gas-small-strings
    struct StrategyData {
        mapping(address => uint256) nonces; // Mapping of nonces used for permit functions.
        mapping(address => uint256) balances; // Mapping to track current balances for each account that holds shares.
        mapping(address => mapping(address => uint256)) allowances; // Mapping to track the allowances for the strategies shares.
        
        // These are the corresponding ERC20 variables needed for the
        // strategies token that is issued and burned on each deposit or withdraw.
        ERC20 asset; // The ERC20 compliant underlying asset that will be used by the Strategy
        string name; // The name of the token for the strategy.
        uint256 totalSupply; // The total amount of shares currently issued.
        uint256 totalAssets; // We manually track `totalAssets` to prevent PPS manipulation through airdrops.

        // Variables for reporting.
        // We use uint96 for timestamps to fit in the same slot as an address.
        address keeper; // Address given permission to call {report} and {tend}.
        uint96 lastReport; // The last time a {report} was called.

        // Access management variables.
        address management; // Main address that can set all configurable variables.
        address pendingManagement; // Address that is pending to take over `management`.
        address emergencyAdmin; // Address to act in emergencies as well as `management`.
        address dragonRouter; // Router that receives minted shares from yield in specialized strategies
        address pendingDragonRouter; // Address that is pending to become the new dragon router.
        uint96 dragonRouterChangeTimestamp; // Timestamp when the dragon router change was initiated.

        // Strategy Status
        uint8 decimals; // The amount of decimals that `asset` and strategy use.
        uint8 entered; // To prevent reentrancy. Use uint8 for gas savings.
        bool shutdown; // Bool that can be used to stop deposits into the strategy.
        
        // Burning mechanism control
        bool enableBurning; // Whether to burn shares from dragon router during loss protection
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev On contract creation we set `asset` for this contract to address(1).
     * This prevents it from ever being initialized in the future.
     */
    constructor() {
        _strategyStorage().asset = ERC20(address(1));
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Require that the call is coming from the strategies management.
     */
    modifier onlyManagement() {
        requireManagement(msg.sender);
        _;
    }

    /**
     * @dev Require that the call is coming from either the strategies
     * management or the keeper.
     */
    modifier onlyKeepers() {
        requireKeeperOrManagement(msg.sender);
        _;
    }

    /**
     * @dev Require that the call is coming from either the strategies
     * management or the emergencyAdmin.
     */
    modifier onlyEmergencyAuthorized() {
        requireEmergencyAuthorized(msg.sender);
        _;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Placed over all state changing functions for increased safety.
     */
    modifier nonReentrant() {
        StrategyData storage S = _strategyStorage();
        // On the first call to nonReentrant, `entered` will be false (2)
        require(S.entered != ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        S.entered = ENTERED;

        _;

        // Reset to false (1) once call has finished.
        S.entered = NOT_ENTERED;
    }

    /**
     * @notice Require a caller is `management`.
     * @dev Is left public so that it can be used by the Strategy.
     *
     * When the Strategy calls this the msg.sender would be the
     * address of the strategy so we need to specify the sender.
     *
     * @param _sender The original msg.sender.
     */
    function requireManagement(address _sender) public view {
        require(_sender == _strategyStorage().management, "!management");
    }

    /**
     * @notice Require a caller is the `keeper` or `management`.
     * @dev Is left public so that it can be used by the Strategy.
     *
     * When the Strategy calls this the msg.sender would be the
     * address of the strategy so we need to specify the sender.
     *
     * @param _sender The original msg.sender.
     */
    function requireKeeperOrManagement(address _sender) public view {
        StrategyData storage S = _strategyStorage();
        require(_sender == S.keeper || _sender == S.management, "!keeper");
    }

    /**
     * @notice Require a caller is the `management` or `emergencyAdmin`.
     * @dev Is left public so that it can be used by the Strategy.
     *
     * When the Strategy calls this the msg.sender would be the
     * address of the strategy so we need to specify the sender.
     *
     * @param _sender The original msg.sender.
     */
    function requireEmergencyAuthorized(address _sender) public view {
        StrategyData storage S = _strategyStorage();
        require(_sender == S.emergencyAdmin || _sender == S.management, "!emergency authorized");
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice API version this TokenizedStrategy implements.
    string internal constant API_VERSION = "1.0.0";

    /// @notice Value to set the `entered` flag to during a call.
    uint8 internal constant ENTERED = 2;
    /// @notice Value to set the `entered` flag to at the end of the call.
    uint8 internal constant NOT_ENTERED = 1;

    /// @notice Used for calculations.
    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Cooldown period for dragon router changes (14 days).
    uint256 internal constant DRAGON_ROUTER_COOLDOWN = 14 days;

    /// @notice Permit type hash for EIP-2612 permit functionality.
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice EIP712Domain type hash for EIP-712 domain separator.
    bytes32 internal constant EIP712DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Hash of the vault name for EIP-712 domain separator.
    bytes32 internal constant NAME_HASH = keccak256("Octant Vault");

    /// @notice Hash of the API version for EIP-712 domain separator.
    bytes32 internal constant VERSION_HASH = keccak256(bytes(API_VERSION));

    /**
     * @dev Custom storage slot that will be used to store the
     * `StrategyData` struct that holds each strategies
     * specific storage variables.
     *
     * Any storage updates done by the TokenizedStrategy actually update
     * the storage of the calling contract. This variable points
     * to the specific location that will be used to store the
     * struct that holds all that data.
     *
     * We use a custom string in order to get a random
     * storage slot that will allow for strategists to use any
     * amount of storage in their strategy without worrying
     * about collisions.
     */
    bytes32 internal constant BASE_STRATEGY_STORAGE = bytes32(uint256(keccak256("octant.base.strategy.storage")) - 1);

    /*//////////////////////////////////////////////////////////////
                            STORAGE GETTER
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev will return the actual storage slot where the strategy
     * specific `StrategyData` struct is stored for both read
     * and write operations.
     *
     * This loads just the slot location, not the full struct
     * so it can be used in a gas efficient manner.
     */
    function _strategyStorage() internal pure returns (StrategyData storage S) {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = BASE_STRATEGY_STORAGE;
        assembly {
            S.slot := slot
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

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
     * @param _emergencyAdmin Address to set as strategy's `emergencyAdmin`.
     * @param _dragonRouter Address that receives minted shares from yield in specialized strategies.
     * @param _enableBurning Whether to enable burning shares from dragon router during loss protection.
     */
    function initialize(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _dragonRouter,
        bool _enableBurning
    ) public virtual {
        // Cache storage pointer.
        StrategyData storage S = _strategyStorage();

        // Make sure we aren't initialized.
        require(address(S.asset) == address(0), "initialized");

        // Set the strategy's underlying asset.
        S.asset = ERC20(_asset);
        // Set the Strategy Tokens name.
        S.name = _name;
        // Set decimals based off the `asset`.
        S.decimals = ERC20(_asset).decimals();

        // Set last report to this block.
        S.lastReport = uint96(block.timestamp);

        // Set the default management address. Can't be 0.
        require(_management != address(0), "ZERO ADDRESS");
        S.management = _management;

        // Set the keeper address, can't be 0
        require(_keeper != address(0), "ZERO ADDRESS");
        S.keeper = _keeper;

        // Set the emergency admin address, can't be 0
        require(_emergencyAdmin != address(0), "ZERO ADDRESS");
        S.emergencyAdmin = _emergencyAdmin;

        // Set the dragon router address, can't be 0
        require(_dragonRouter != address(0), "ZERO ADDRESS");
        S.dragonRouter = _dragonRouter;

        // Set the burning mechanism flag
        S.enableBurning = _enableBurning;

        // Emit event to signal a new strategy has been initialized.
        emit NewTokenizedStrategy(address(this), _asset, API_VERSION);
    }

    /*//////////////////////////////////////////////////////////////
                      ERC4626 WRITE METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints `shares` of strategy shares to `receiver` by
     * depositing exactly `assets` of underlying tokens.
     * @param assets The amount of underlying to deposit in.
     * @param receiver The address to receive the `shares`.
     * @return shares The actual amount of shares issued.
     */
    function deposit(uint256 assets, address receiver) external virtual nonReentrant returns (uint256 shares) {
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
    }

    /**
     * @notice Mints exactly `shares` of strategy shares to
     * `receiver` by depositing `assets` of underlying tokens.
     * @param shares The amount of strategy shares mint.
     * @param receiver The address to receive the `shares`.
     * @return assets The actual amount of asset deposited.
     */
    function mint(uint256 shares, address receiver) external virtual nonReentrant returns (uint256 assets) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();

        // Checking max mint will also check if shutdown.
        require(shares <= _maxMint(S, receiver), "ERC4626: mint more than max");
        // Check for rounding error.
        require((assets = _convertToAssets(S, shares, Math.Rounding.Ceil)) != 0, "ZERO_ASSETS");

        _deposit(S, receiver, assets, shares);
    }

    /**
     * @notice Withdraws exactly `assets` from `owners` shares and sends
     * the underlying tokens to `receiver`.
     * @dev This will default to not allowing any loss to be taken.
     * @param assets The amount of underlying to withdraw.
     * @param receiver The address to receive `assets`.
     * @param owner The address whose shares are burnt.
     * @return shares The actual amount of shares burnt.
     */
    function withdraw(uint256 assets, address receiver, address owner) external virtual returns (uint256 shares) {
        return withdraw(assets, receiver, owner, 0);
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
    ) public virtual nonReentrant returns (uint256 shares) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();
        require(assets <= _maxWithdraw(S, owner), "ERC4626: withdraw more than max");
        // Check for rounding error or 0 value.
        require((shares = _convertToShares(S, assets, Math.Rounding.Ceil)) != 0, "ZERO_SHARES");

        // Withdraw and track the actual amount withdrawn for loss check.
        _withdraw(S, receiver, owner, assets, shares, maxLoss);
    }

    /**
     * @notice Redeems exactly `shares` from `owner` and
     * sends `assets` of underlying tokens to `receiver`.
     * @dev This will default to allowing any loss passed to be realized.
     * @param shares The amount of shares burnt.
     * @param receiver The address to receive `assets`.
     * @param owner The address whose shares are burnt.
     * @return assets The actual amount of underlying withdrawn.
     */
    function redeem(uint256 shares, address receiver, address owner) external virtual returns (uint256) {
        // We default to not limiting a potential loss.
        return redeem(shares, receiver, owner, MAX_BPS);
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
    ) public virtual nonReentrant returns (uint256) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();
        require(shares <= _maxRedeem(S, owner), "ERC4626: redeem more than max");
        // slither-disable-next-line uninitialized-local
        uint256 assets;
        // Check for rounding error or 0 value.
        require((assets = _convertToAssets(S, shares, Math.Rounding.Floor)) != 0, "ZERO_ASSETS");

        // We need to return the actual amount withdrawn in case of a loss.
        return _withdraw(S, receiver, owner, assets, shares, maxLoss);
    }

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL 4626 VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the total amount of assets this strategy holds
     * as of the last report.
     *
     * We manually track `totalAssets` to avoid any PPS manipulation.
     *
     * @return . Total assets the strategy holds.
     */
    function totalAssets() external view returns (uint256) {
        return _totalAssets(_strategyStorage());
    }

    /**
     * @notice Get the current supply of the strategies shares.
     *
     * Locked shares issued to the strategy from profits are not
     * counted towards the full supply until they are unlocked.
     *
     * As more shares slowly unlock the totalSupply will decrease
     * causing the PPS of the strategy to increase.
     *
     * @return . Total amount of shares outstanding.
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply(_strategyStorage());
    }

    /**
     * @notice The amount of shares that the strategy would
     *  exchange for the amount of assets provided, in an
     * ideal scenario where all the conditions are met.
     *
     * @param assets The amount of underlying.
     * @return . Expected shares that `assets` represents.
     */
    function convertToShares(uint256 assets) external view returns (uint256) {
        return _convertToShares(_strategyStorage(), assets, Math.Rounding.Floor);
    }

    /**
     * @notice The amount of assets that the strategy would
     * exchange for the amount of shares provided, in an
     * ideal scenario where all the conditions are met.
     *
     * @param shares The amount of the strategies shares.
     * @return . Expected amount of `asset` the shares represents.
     */
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _convertToAssets(_strategyStorage(), shares, Math.Rounding.Floor);
    }

    /**
     * @notice Allows an on-chain or off-chain user to simulate
     * the effects of their deposit at the current block, given
     * current on-chain conditions.
     * @dev This will round down.
     *
     * @param assets The amount of `asset` to deposits.
     * @return . Expected shares that would be issued.
     */
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return _convertToShares(_strategyStorage(), assets, Math.Rounding.Floor);
    }

    /**
     * @notice Allows an on-chain or off-chain user to simulate
     * the effects of their mint at the current block, given
     * current on-chain conditions.
     * @dev This is used instead of convertToAssets so that it can
     * round up for safer mints.
     *
     * @param shares The amount of shares to mint.
     * @return . The needed amount of `asset` for the mint.
     */
    function previewMint(uint256 shares) external view returns (uint256) {
        return _convertToAssets(_strategyStorage(), shares, Math.Rounding.Ceil);
    }

    /**
     * @notice Allows an on-chain or off-chain user to simulate
     * the effects of their withdrawal at the current block,
     * given current on-chain conditions.
     * @dev This is used instead of convertToShares so that it can
     * round up for safer withdraws.
     *
     * @param assets The amount of `asset` that would be withdrawn.
     * @return . The amount of shares that would be burnt.
     */
    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return _convertToShares(_strategyStorage(), assets, Math.Rounding.Ceil);
    }

    /**
     * @notice Allows an on-chain or off-chain user to simulate
     * the effects of their redemption at the current block,
     * given current on-chain conditions.
     * @dev This will round down.
     *
     * @param shares The amount of shares that would be redeemed.
     * @return . The amount of `asset` that would be returned.
     */
    function previewRedeem(uint256 shares) external view returns (uint256) {
        return _convertToAssets(_strategyStorage(), shares, Math.Rounding.Floor);
    }

    /**
     * @notice Total number of underlying assets that can
     * be deposited into the strategy, where `receiver`
     * corresponds to the receiver of the shares of a {deposit} call.
     *
     * @param receiver The address receiving the shares.
     * @return . The max that `receiver` can deposit in `asset`.
     */
    function maxDeposit(address receiver) public view virtual returns (uint256) {
        return _maxDeposit(_strategyStorage(), receiver);
    }

    /**
     * @notice Total number of shares that can be minted to `receiver`
     * of a {mint} call.
     *
     * @param receiver The address receiving the shares.
     * @return _maxMint The max that `receiver` can mint in shares.
     */
    function maxMint(address receiver) public view virtual returns (uint256) {
        return _maxMint(_strategyStorage(), receiver);
    }

    /**
     * @notice Total number of underlying assets that can be
     * withdrawn from the strategy by `owner`, where `owner`
     * corresponds to the msg.sender of a {redeem} call.
     *
     * @param owner The owner of the shares.
     * @return _maxWithdraw Max amount of `asset` that can be withdrawn.
     */
    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return _maxWithdraw(_strategyStorage(), owner);
    }

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxWithdraw(address owner, uint256 /*maxLoss*/) external view returns (uint256) {
        return _maxWithdraw(_strategyStorage(), owner);
    }

    /**
     * @notice Total number of strategy shares that can be
     * redeemed from the strategy by `owner`, where `owner`
     * corresponds to the msg.sender of a {redeem} call.
     *
     * @param owner The owner of the shares.
     * @return _maxRedeem Max amount of shares that can be redeemed.
     */
    function maxRedeem(address owner) public view virtual returns (uint256) {
        return _maxRedeem(_strategyStorage(), owner);
    }

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxRedeem(address owner, uint256 /*maxLoss*/) external view returns (uint256) {
        return _maxRedeem(_strategyStorage(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL 4626 VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal implementation of {totalAssets}.
    function _totalAssets(StrategyData storage S) internal view returns (uint256) {
        return S.totalAssets;
    }

    /// @dev Internal implementation of {totalSupply}.
    function _totalSupply(StrategyData storage S) internal view returns (uint256) {
        return S.totalSupply;
    }

    /// @dev Internal implementation of {convertToShares}.
    function _convertToShares(
        StrategyData storage S,
        uint256 assets,
        Math.Rounding _rounding
    ) internal view virtual returns (uint256) {
        // Saves an extra SLOAD if values are non-zero.
        uint256 totalSupply_ = _totalSupply(S);
        // If supply is 0, PPS = 1.
        if (totalSupply_ == 0) return assets;

        uint256 totalAssets_ = _totalAssets(S);
        // If assets are 0 but supply is not PPS = 0.
        if (totalAssets_ == 0) return 0;

        return assets.mulDiv(totalSupply_, totalAssets_, _rounding);
    }

    /// @dev Internal implementation of {convertToAssets}.
    // WARNING: When deploying donated assets with YieldDonatingTokenizedStrategy,
    // potential losses can be amplified due to the multi-hop donation flow:
    // For example OctantVault → YearnVault → MorphoVault → Morpho
    function _convertToAssets(
        StrategyData storage S,
        uint256 shares,
        Math.Rounding _rounding
    ) internal view virtual returns (uint256) {
        // Saves an extra SLOAD if totalSupply() is non-zero.
        uint256 supply = _totalSupply(S);

        return supply == 0 ? shares : shares.mulDiv(_totalAssets(S), supply, _rounding);
    }

    /// @dev Internal implementation of {maxDeposit}.
    function _maxDeposit(StrategyData storage S, address receiver) internal view returns (uint256) {
        // Cannot deposit when shutdown or to the strategy.
        if (S.shutdown || receiver == address(this)) return 0;

        return IBaseStrategy(address(this)).availableDepositLimit(receiver);
    }

    /// @dev Internal implementation of {maxMint}.
    function _maxMint(StrategyData storage S, address receiver) internal view returns (uint256 maxMint_) {
        // Cannot mint when shutdown or to the strategy.
        if (S.shutdown || receiver == address(this)) return 0;

        maxMint_ = IBaseStrategy(address(this)).availableDepositLimit(receiver);
        if (maxMint_ != type(uint256).max) {
            maxMint_ = _convertToShares(S, maxMint_, Math.Rounding.Floor);
        }
    }

    /// @dev Internal implementation of {maxWithdraw}.
    function _maxWithdraw(StrategyData storage S, address owner) internal view returns (uint256 maxWithdraw_) {
        // Get the max the owner could withdraw currently.
        maxWithdraw_ = IBaseStrategy(address(this)).availableWithdrawLimit(owner);

        // If there is no limit enforced.
        if (maxWithdraw_ == type(uint256).max) {
            // Saves a min check if there is no withdrawal limit.
            maxWithdraw_ = _convertToAssets(S, _balanceOf(S, owner), Math.Rounding.Floor);
        } else {
            maxWithdraw_ = Math.min(_convertToAssets(S, _balanceOf(S, owner), Math.Rounding.Floor), maxWithdraw_);
        }
    }

    /// @dev Internal implementation of {maxRedeem}.
    function _maxRedeem(StrategyData storage S, address owner) internal view returns (uint256 maxRedeem_) {
        // Get the max the owner could withdraw currently.
        maxRedeem_ = IBaseStrategy(address(this)).availableWithdrawLimit(owner);

        // Conversion would overflow and saves a min check if there is no withdrawal limit.
        if (maxRedeem_ == type(uint256).max) {
            maxRedeem_ = _balanceOf(S, owner);
        } else {
            maxRedeem_ = Math.min(
                // Can't redeem more than the balance.
                _convertToShares(S, maxRedeem_, Math.Rounding.Floor),
                _balanceOf(S, owner)
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL 4626 WRITE METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Function to be called during {deposit} and {mint}.
     *
     * This function handles all logic including transfers,
     * minting and accounting.
     *
     * We do all external calls before updating any internal
     * values to prevent view reentrancy issues from the token
     * transfers or the _deployFunds() calls.
     */
    function _deposit(StrategyData storage S, address receiver, uint256 assets, uint256 shares) internal virtual {
        // Cache storage variables used more than once.
        ERC20 _asset = S.asset;

        // Need to transfer before minting or ERC777s could reenter.
        _asset.safeTransferFrom(msg.sender, address(this), assets);

        // We can deploy the full loose balance currently held.
        IBaseStrategy(address(this)).deployFunds(_asset.balanceOf(address(this)));

        // Adjust total Assets.
        S.totalAssets += assets;

        // mint shares
        _mint(S, receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @dev To be called during {redeem} and {withdraw}.
     *
     * This will handle all logic, transfers and accounting
     * in order to service the withdraw request.
     *
     * If we are not able to withdraw the full amount needed, it will
     * be counted as a loss and passed on to the user.
     */
    function _withdraw(
        StrategyData storage S,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 maxLoss
    ) internal returns (uint256) {
        require(receiver != address(0), "ZERO ADDRESS");
        require(maxLoss <= MAX_BPS, "exceeds MAX_BPS");

        // Spend allowance if applicable.
        if (msg.sender != owner) {
            _spendAllowance(S, owner, msg.sender, shares);
        }

        // Cache `asset` since it is used multiple times..
        ERC20 _asset = S.asset;

        uint256 idle = _asset.balanceOf(address(this));
        // slither-disable-next-line uninitialized-local
        uint256 loss;
        // Check if we need to withdraw funds.
        if (idle < assets) {
            // Tell Strategy to free what we need.
            unchecked {
                IBaseStrategy(address(this)).freeFunds(assets - idle);
            }

            // Return the actual amount withdrawn. Adjust for potential under withdraws.
            idle = _asset.balanceOf(address(this));

            // If we didn't get enough out then we have a loss.
            if (idle < assets) {
                unchecked {
                    loss = assets - idle;
                }
                // If a non-default max loss parameter was set.
                if (maxLoss < MAX_BPS) {
                    // Make sure we are within the acceptable range.
                    require(loss <= (assets * maxLoss) / MAX_BPS, "too much loss");
                }
                // Lower the amount to be withdrawn.
                assets = idle;
            }
        }

        // Update assets based on how much we took.
        S.totalAssets -= (assets + loss);

        _burn(S, owner, shares);

        // Transfer the amount of underlying to the receiver.
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        // Return the actual amount of assets withdrawn.
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                        PROFIT REPORTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Function for keepers to call to harvest and record all
     * donations accrued.
     *
     * @dev This will account for any gains/losses since the last report.
     * This function is virtual and meant to be overridden by specialized
     * strategies that implement custom yield handling mechanisms.
     *
     * Two primary implementations are provided in specialized strategies:
     * - YieldDonatingTokenizedStrategy: Mints shares from profits to the dragonRouter
     * - YieldSkimmingTokenizedStrategy: Skims asset appreciation by diluting shares
     *
     * @return profit The notional amount of gain if any since the last
     * report in terms of `asset`.
     * @return loss The notional amount of loss if any since the last
     * report in terms of `asset`.
     */
    function report() external virtual returns (uint256 profit, uint256 loss);

    /*//////////////////////////////////////////////////////////////
                            TENDING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice For a 'keeper' to 'tend' the strategy if a custom
     * tendTrigger() is implemented.
     *
     * @dev Both 'tendTrigger' and '_tend' will need to be overridden
     * for this to be used.
     *
     * This will callback the internal '_tend' call in the BaseStrategy
     * with the total current amount available to the strategy to deploy.
     *
     * This is a permissioned function so if desired it could
     * be used for illiquid or manipulatable strategies to compound
     * rewards, perform maintenance or deposit/withdraw funds.
     *
     * This will not cause any change in PPS. Total assets will
     * be the same before and after.
     *
     * A report() call will be needed to record any profits or losses.
     */
    function tend() external nonReentrant onlyKeepers {
        // Tend the strategy with the current loose balance.
        IBaseStrategy(address(this)).tendThis(_strategyStorage().asset.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY SHUTDOWN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Used to shutdown the strategy preventing any further deposits.
     * @dev Can only be called by the current `management` or `emergencyAdmin`.
     *
     * This will stop any new {deposit} or {mint} calls but will
     * not prevent {withdraw} or {redeem}. It will also still allow for
     * {tend} and {report} so that management can report any last losses
     * in an emergency as well as provide any maintenance to allow for full
     * withdraw.
     *
     * This is a one way switch and can never be set back once shutdown.
     */
    function shutdownStrategy() external onlyEmergencyAuthorized {
        _strategyStorage().shutdown = true;

        emit StrategyShutdown();
    }

    /**
     * @notice To manually withdraw funds from the yield source after a
     * strategy has been shutdown.
     * @dev This can only be called post {shutdownStrategy}.
     *
     * This will never cause a change in PPS. Total assets will
     * be the same before and after.
     *
     * A strategist will need to override the {_emergencyWithdraw} function
     * in their strategy for this to work.
     *
     * @param amount The amount of asset to attempt to free.
     */
    function emergencyWithdraw(uint256 amount) external nonReentrant onlyEmergencyAuthorized {
        // Make sure the strategy has been shutdown.
        require(_strategyStorage().shutdown, "not shutdown");

        // Withdraw from the yield source.
        IBaseStrategy(address(this)).shutdownWithdraw(amount);
    }

    /*//////////////////////////////////////////////////////////////
                        GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the underlying asset for the strategy.
     * @return . The underlying asset.
     */
    function asset() external view returns (address) {
        return address(_strategyStorage().asset);
    }

    /**
     * @notice Get the API version for this TokenizedStrategy.
     * @return . The API version for this TokenizedStrategy
     */
    function apiVersion() external pure returns (string memory) {
        return API_VERSION;
    }

    /**
     * @notice Get the current address that controls the strategy.
     * @return . Address of management
     */
    function management() external view returns (address) {
        return _strategyStorage().management;
    }

    /**
     * @notice Get the current pending management address if any.
     * @return . Address of pendingManagement
     */
    function pendingManagement() external view returns (address) {
        return _strategyStorage().pendingManagement;
    }

    /**
     * @notice Get the current address that can call tend and report.
     * @return . Address of the keeper
     */
    function keeper() external view returns (address) {
        return _strategyStorage().keeper;
    }

    /**
     * @notice Get the current address that can shutdown and emergency withdraw.
     * @return . Address of the emergencyAdmin
     */
    function emergencyAdmin() external view returns (address) {
        return _strategyStorage().emergencyAdmin;
    }

    /**
     * @notice Get the current dragon router address that will receive minted shares.
     * @return Address of the dragon router
     */
    function dragonRouter() external view returns (address) {
        return _strategyStorage().dragonRouter;
    }

    /**
     * @notice Get the pending dragon router address if any.
     * @return Address of the pending dragon router
     */
    function pendingDragonRouter() external view returns (address) {
        return _strategyStorage().pendingDragonRouter;
    }

    /**
     * @notice Get the timestamp when dragon router change was initiated.
     * @return Timestamp of the dragon router change initiation
     */
    function dragonRouterChangeTimestamp() external view returns (uint256) {
        return uint256(_strategyStorage().dragonRouterChangeTimestamp);
    }

    /**
     * @notice The timestamp of the last time Yield was reported.
     * @return . The last report.
     */
    function lastReport() external view returns (uint256) {
        return uint256(_strategyStorage().lastReport);
    }

    /**
     * @notice Get the price per share.
     * @dev This value offers limited precision. Integrations that require
     * exact precision should use convertToAssets or convertToShares instead.
     *
     * @return . The price per share.
     */
    function pricePerShare() public view returns (uint256) {
        StrategyData storage S = _strategyStorage();
        return _convertToAssets(S, 10 ** S.decimals, Math.Rounding.Floor);
    }

    /**
     * @notice To check if the strategy has been shutdown.
     * @return . Whether or not the strategy is shutdown.
     */
    function isShutdown() external view returns (bool) {
        return _strategyStorage().shutdown;
    }

    /**
     * @notice Get whether burning shares from dragon router during loss protection is enabled.
     * @return Whether the burning mechanism is enabled.
     */
    function enableBurning() external view returns (bool) {
        return _strategyStorage().enableBurning;
    }

    /*//////////////////////////////////////////////////////////////
                        SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Step one of two to set a new address to be in charge of the strategy.
     * @dev Can only be called by the current `management`. The address is
     * set to pending management and will then have to call {acceptManagement}
     * in order for the 'management' to officially change.
     *
     * Cannot set `management` to address(0).
     *
     * @param _management New address to set `pendingManagement` to.
     */
    function setPendingManagement(address _management) external onlyManagement {
        require(_management != address(0), "ZERO ADDRESS");
        _strategyStorage().pendingManagement = _management;

        emit UpdatePendingManagement(_management);
    }

    /**
     * @notice Step two of two to set a new 'management' of the strategy.
     * @dev Can only be called by the current `pendingManagement`.
     */
    function acceptManagement() external {
        StrategyData storage S = _strategyStorage();
        require(msg.sender == S.pendingManagement, "!pending");
        S.management = msg.sender;
        S.pendingManagement = address(0);

        emit UpdateManagement(msg.sender);
    }

    /**
     * @notice Sets a new address to be in charge of tend and reports.
     * @dev Can only be called by the current `management`.
     *
     * @param _keeper New address to set `keeper` to.
     */
    function setKeeper(address _keeper) external onlyManagement {
        require(_keeper != address(0), "ZERO ADDRESS");
        _strategyStorage().keeper = _keeper;

        emit UpdateKeeper(_keeper);
    }

    /**
     * @notice Sets a new address to be able to shutdown the strategy.
     * @dev Can only be called by the current `management`.
     *
     * @param _emergencyAdmin New address to set `emergencyAdmin` to.
     */
    function setEmergencyAdmin(address _emergencyAdmin) external onlyManagement {
        require(_emergencyAdmin != address(0), "ZERO ADDRESS");
        _strategyStorage().emergencyAdmin = _emergencyAdmin;

        emit UpdateEmergencyAdmin(_emergencyAdmin);
    }

    /**
     * @notice Initiates a change to a new dragon router address with a cooldown period.
     * @dev Users have 7 days to withdraw if they disagree with the new donation address.
     * @param _dragonRouter New address to set as pending `dragonRouter`.
     */
    function setDragonRouter(address _dragonRouter) external onlyManagement {
        require(_dragonRouter != address(0), "ZERO ADDRESS");
        StrategyData storage S = _strategyStorage();
        require(_dragonRouter != S.dragonRouter, "same dragon router");

        S.pendingDragonRouter = _dragonRouter;
        S.dragonRouterChangeTimestamp = uint96(block.timestamp);

        uint256 effectiveTimestamp = block.timestamp + DRAGON_ROUTER_COOLDOWN;
        emit PendingDragonRouterChange(_dragonRouter, effectiveTimestamp);
    }

    /**
     * @notice Finalizes the dragon router change after the cooldown period.
     * @dev Can only be called after the cooldown period has elapsed.
     */
    function finalizeDragonRouterChange() external virtual {
        StrategyData storage S = _strategyStorage();
        require(S.pendingDragonRouter != address(0), "no pending change");
        require(block.timestamp >= S.dragonRouterChangeTimestamp + DRAGON_ROUTER_COOLDOWN, "cooldown not elapsed");

        S.dragonRouter = S.pendingDragonRouter;
        S.pendingDragonRouter = address(0);
        S.dragonRouterChangeTimestamp = 0;

        emit UpdateDragonRouter(S.dragonRouter);
    }

    /**
     * @notice Cancels a pending dragon router change.
     * @dev Can only be called by management during the cooldown period.
     */
    function cancelDragonRouterChange() external onlyManagement {
        StrategyData storage S = _strategyStorage();
        require(S.pendingDragonRouter != address(0), "no pending change");

        S.pendingDragonRouter = address(0);
        S.dragonRouterChangeTimestamp = 0;

        emit PendingDragonRouterChange(address(0), 0);
    }

    /**
     * @notice Updates the name for the strategy.
     * @param _name The new name for the strategy.
     */
    function setName(string calldata _name) external onlyManagement {
        _strategyStorage().name = _name;
    }

    /**
     * @notice Sets whether to enable burning shares from dragon router during loss protection.
     * @dev Can only be called by the current `management`.
     * @param _enableBurning Whether to enable the burning mechanism.
     */
    function setEnableBurning(bool _enableBurning) external onlyManagement {
        _strategyStorage().enableBurning = _enableBurning;
        emit UpdateBurningMechanism(_enableBurning);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the name of the token.
     * @return . The name the strategy is using for its token.
     */
    function name() external view returns (string memory) {
        return _strategyStorage().name;
    }

    /**
     * @notice Returns the symbol of the strategies token.
     * @dev Will be 'os + asset symbol'.
     * @return . The symbol the strategy is using for its tokens.
     */
    function symbol() external view returns (string memory) {
        return string(abi.encodePacked("os", _strategyStorage().asset.symbol()));
    }

    /**
     * @notice Returns the number of decimals used to get its user representation.
     * @return . The decimals used for the strategy and `asset`.
     */
    function decimals() external view returns (uint8) {
        return _strategyStorage().decimals;
    }

    /**
     * @notice Returns the current balance for a given '_account'.
     * @dev If the '_account` is the strategy then this will subtract
     * the amount of shares that have been unlocked since the last profit first.
     * @param account the address to return the balance for.
     * @return . The current balance in y shares of the '_account'.
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf(_strategyStorage(), account);
    }

    /// @dev Internal implementation of {balanceOf}.
    function _balanceOf(StrategyData storage S, address account) internal view returns (uint256) {
        return S.balances[account];
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
    function transfer(address to, uint256 amount) external virtual returns (bool) {
        _transfer(_strategyStorage(), msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     * @param owner The address who owns the shares.
     * @param spender The address who would be moving the owners shares.
     * @return . The remaining amount of shares of `owner` that could be moved by `spender`.
     */
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowance(_strategyStorage(), owner, spender);
    }

    /// @dev Internal implementation of {allowance}.
    function _allowance(StrategyData storage S, address owner, address spender) internal view returns (uint256) {
        return S.allowances[owner][spender];
    }

    /**
     * @notice Sets `amount` as the allowance of `spender` over the caller's tokens.
     * @dev
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     *
     * @param spender the address to allow the shares to be moved by.
     * @param amount the amount of shares to allow `spender` to move.
     * @return . a boolean value indicating whether the operation succeeded.
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_strategyStorage(), msg.sender, spender, amount);
        return true;
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
    function transferFrom(address from, address to, uint256 amount) external virtual returns (bool) {
        StrategyData storage S = _strategyStorage();
        _spendAllowance(S, from, msg.sender, amount);
        _transfer(S, from, to, amount);
        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `to` cannot be the strategies address
     * - `from` must have a balance of at least `amount`.
     *
     */
    function _transfer(StrategyData storage S, address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(to != address(this), "ERC20 transfer to strategy");

        S.balances[from] -= amount;
        unchecked {
            S.balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     *
     */
    function _mint(StrategyData storage S, address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        S.totalSupply += amount;
        unchecked {
            S.balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(StrategyData storage S, address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        S.balances[account] -= amount;
        unchecked {
            S.totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(StrategyData storage S, address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        S.allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(StrategyData storage S, address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowance(S, owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(S, owner, spender, currentAllowance - amount);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * @dev Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     *
     * @param _owner the address of the account to return the nonce for.
     * @return . the current nonce for the account.
     */
    function nonces(address _owner) external view returns (uint256) {
        return _strategyStorage().nonces[_owner];
    }

    /**
     * @notice Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * @dev IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "ERC20: PERMIT_DEADLINE_EXPIRED");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                PERMIT_TYPEHASH,
                                owner,
                                spender,
                                value,
                                _strategyStorage().nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, "ERC20: INVALID_SIGNER");

            _approve(_strategyStorage(), recoveredAddress, spender, value);
        }
    }

    /**
     * @notice Returns the domain separator used in the encoding of the signature
     * for {permit}, as defined by {EIP712}.
     *
     * @return . The domain separator that will be used for any {permit} calls.
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }
}
