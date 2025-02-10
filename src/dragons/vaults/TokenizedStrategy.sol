// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { IAvatar } from "zodiac/interfaces/IAvatar.sol";
import { ZeroAddress, ZeroShares, ZeroAssets, ReentrancyGuard__ReentrantCall, TokenizedStrategy__NotOperator, TokenizedStrategy__NotManagement, TokenizedStrategy__NotKeeperOrManagement, TokenizedStrategy__NotRegenGovernance, TokenizedStrategy__NotEmergencyAuthorized, TokenizedStrategy__AlreadyInitialized, TokenizedStrategy__DepositMoreThanMax, TokenizedStrategy__MintMoreThanMax, TokenizedStrategy__InvalidMaxLoss, TokenizedStrategy__TransferFromZeroAddress, TokenizedStrategy__TransferToZeroAddress, TokenizedStrategy__TransferToStrategy, TokenizedStrategy__MintToZeroAddress, TokenizedStrategy__BurnFromZeroAddress, TokenizedStrategy__ApproveFromZeroAddress, TokenizedStrategy__ApproveToZeroAddress, TokenizedStrategy__InsufficientAllowance, TokenizedStrategy__PermitDeadlineExpired, TokenizedStrategy__InvalidSigner, TokenizedStrategy__NotSelf, TokenizedStrategy__WithdrawMoreThanMax, TokenizedStrategy__RedeemMoreThanMax, TokenizedStrategy__TransferFailed, TokenizedStrategy__NotPendingManagement, TokenizedStrategy__StrategyNotInShutdown, TokenizedStrategy__TooMuchLoss, TokenizedStrategy__HatsAlreadyInitialized, TokenizedStrategy__InvalidHatsAddress } from "../../errors.sol";

import { IBaseStrategy } from "src/interfaces/IBaseStrategy.sol";
import { IHats } from "src/interfaces/IHats.sol";

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
     * @notice Emitted when the strategy reports `profit` or `loss` and
     * `performanceFees` and `protocolFees` are paid out.
     */
    event Reported(uint256 profit, uint256 loss, uint256 protocolFees, uint256 performanceFees);

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
     * @notice Emitted when the 'pendingManagement' address is updated to 'newPendingManagement'.
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
     * @notice Emitted when Hats Protocol integration is set up
     */
    event HatsProtocolSetup(
        address indexed hats,
        uint256 indexed keeperHat,
        uint256 indexed managementHat,
        uint256 emergencyAdminHat,
        uint256 regenGovernanceHat
    );

    /*//////////////////////////////////////////////////////////////
                        STORAGE STRUCT
    //////////////////////////////////////////////////////////////*/

    struct LockupInfo {
        uint256 lockupTime;
        uint256 unlockTime;
        uint256 lockedShares;
        bool isRageQuit;
    }

    struct StrategyData {
        // The ERC20 compliant underlying asset that will be
        // used by the Strategy
        ERC20 asset;
        address operator;
        address dragonRouter;
        // These are the corresponding ERC20 variables needed for the
        // strategies token that is issued and burned on each deposit or withdraw.
        uint8 decimals; // The amount of decimals that `asset` and strategy use.
        string name; // The name of the token for the strategy.
        uint256 totalSupply; // The total amount of shares currently issued.
        mapping(address => uint256) nonces; // Mapping of nonces used for permit functions.
        mapping(address => uint256) balances; // Mapping to track current balances for each account that holds shares.
        mapping(address => mapping(address => uint256)) allowances; // Mapping to track the allowances for the strategies shares.
        mapping(address => LockupInfo) voluntaryLockups; // Mapping allowing us to track lockups.
        // We manually track `totalAssets` to prevent PPS manipulation through airdrops.
        uint256 totalAssets;
        address keeper; // Address given permission to call {report} and {tend}.
        uint96 lastReport; // The last time a {report} was called.
        // Access management variables.
        address management; // Main address that can set all configurable variables.
        address pendingManagement; // Address that is pending to take over `management`.
        address emergencyAdmin; // Address to act in emergencies as well as `management`.
        // Strategy Status
        uint8 entered; // To prevent reentrancy. Use uint8 for gas savings.
        bool shutdown; // Bool that can be used to stop deposits into the strategy.
        uint256 MINIMUM_LOCKUP_DURATION;
        uint256 RAGE_QUIT_COOLDOWN_PERIOD;
        address REGEN_GOVERNANCE;
        // Hats protocol integration
        IHats HATS;
        uint256 KEEPER_HAT;
        uint256 MANAGEMENT_HAT;
        uint256 EMERGENCY_ADMIN_HAT;
        uint256 REGEN_GOVERNANCE_HAT;
        bool hatsInitialized; // Flag for Hats Protocol initialization
    }

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // using this address to represent native ETH

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOperator() {
        if (msg.sender != _strategyStorage().operator) revert TokenizedStrategy__NotOperator();
        _;
    }

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
     * @dev Require that the call is coming from the regen governance.
     */

    modifier onlyRegenGovernance() {
        requireRegenGovernance(msg.sender);
        _;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Placed over all state changing functions for increased safety.
     */
    modifier nonReentrant() {
        StrategyData storage S = _strategyStorage();
        // On the first call to nonReentrant, `entered` will be false (2)
        if (S.entered == ENTERED) revert ReentrancyGuard__ReentrantCall();

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
        StrategyData storage S = _strategyStorage();
        if (_sender != S.management && !_isHatsWearer(S, _sender, S.MANAGEMENT_HAT)) {
            revert TokenizedStrategy__NotManagement();
        }
    }

    /**
     * @dev Require that the call is coming from either the strategies
     * management or the keeper.
     * @dev Is left public so that it can be used by the Strategy.
     *
     * When the Strategy calls this the msg.sender would be the
     * address of the strategy so we need to specify the sender.
     *
     * @param _sender The original msg.sender.
     */
    function requireKeeperOrManagement(address _sender) public view {
        StrategyData storage S = _strategyStorage();
        if (
            _sender != S.keeper &&
            _sender != S.management &&
            !_isHatsWearer(S, _sender, S.KEEPER_HAT) &&
            !_isHatsWearer(S, _sender, S.MANAGEMENT_HAT)
        ) revert TokenizedStrategy__NotKeeperOrManagement();
    }

    /**
     * @dev Require that the call is coming from either the strategies
     * management or the emergencyAdmin.
     * @dev Is left public so that it can be used by the Strategy.
     *
     * When the Strategy calls this the msg.sender would be the
     * address of the strategy so we need to specify the sender.
     *
     * @param _sender The original msg.sender.
     */
    function requireEmergencyAuthorized(address _sender) public view {
        StrategyData storage S = _strategyStorage();
        if (
            _sender != S.emergencyAdmin &&
            _sender != S.management &&
            !_isHatsWearer(S, _sender, S.EMERGENCY_ADMIN_HAT) &&
            !_isHatsWearer(S, _sender, S.MANAGEMENT_HAT)
        ) revert TokenizedStrategy__NotEmergencyAuthorized();
    }

    /**
     * @notice Require a caller is `regenGovernance`.
     * @dev Is left public so that it can be used by the Strategy.
     *
     * When the Strategy calls this the msg.sender would be the
     * address of the strategy so we need to specify the sender.
     *
     * @param _sender The original msg.sender.
     */
    function requireRegenGovernance(address _sender) public view {
        StrategyData storage S = _strategyStorage();
        if (_sender != S.REGEN_GOVERNANCE && !_isHatsWearer(S, _sender, S.REGEN_GOVERNANCE_HAT)) {
            revert TokenizedStrategy__NotRegenGovernance();
        }
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

    /// @notice Used for fee calculations.
    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Minimum and maximum durations for lockup and rage quit periods
    uint256 internal constant RANGE_MINIMUM_LOCKUP_DURATION = 30 days;
    uint256 internal constant RANGE_MAXIMUM_LOCKUP_DURATION = 3650 days;
    uint256 internal constant RANGE_MINIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 30 days;
    uint256 internal constant RANGE_MAXIMUM_RAGE_QUIT_COOLDOWN_PERIOD = 3650 days;

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
        assembly ("memory-safe") {
            S.slot := slot
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function __TokenizedStrategy_init(
        address _asset,
        string memory _name,
        address _operator,
        address _management,
        address _keeper,
        address _dragonRouter,
        address _regenGovernance
    ) internal {
        // Cache storage pointer.
        StrategyData storage S = _strategyStorage();

        // Make sure we aren't initialized.
        if (address(S.asset) != address(0)) revert TokenizedStrategy__AlreadyInitialized();

        // Set the strategy's underlying asset.
        S.asset = ERC20(_asset);

        S.operator = _operator;
        S.dragonRouter = _dragonRouter;

        // Set the Strategy Tokens name.
        S.name = _name;
        // Set decimals based off the `asset`.
        S.decimals = _asset == ETH ? 18 : ERC20(_asset).decimals();

        S.lastReport = uint96(block.timestamp);

        // Set the default management address. Can't be 0.
        if (_management == address(0)) revert ZeroAddress();
        S.management = _management;
        // Set the keeper address
        S.keeper = _keeper;

        S.REGEN_GOVERNANCE = _regenGovernance;
        S.MINIMUM_LOCKUP_DURATION = 90 days;
        S.RAGE_QUIT_COOLDOWN_PERIOD = 90 days;

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
    function deposit(
        uint256 assets,
        address receiver
    ) external payable virtual nonReentrant onlyOperator returns (uint256 shares) {}

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
    ) external payable virtual nonReentrant onlyOperator returns (uint256 assets) {}

    /**
     * @notice Withdraws exactly `assets` from `owners` shares and sends
     * the underlying tokens to `receiver`.
     * @dev This will default to not allowing any loss to be taken.
     * @param assets The amount of underlying to withdraw.
     * @param receiver The address to receive `assets`.
     * @param _owner The address whose shares are burnt.
     * @return shares The actual amount of shares burnt.
     */
    function withdraw(uint256 assets, address receiver, address _owner) external returns (uint256 shares) {
        return withdraw(assets, receiver, _owner, 0);
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
    ) public virtual nonReentrant returns (uint256 shares) {}

    /**
     * @notice Redeems exactly `shares` from `owner` and
     * sends `assets` of underlying tokens to `receiver`.
     * @dev This will default to allowing any loss passed to be realized.
     * @param shares The amount of shares burnt.
     * @param receiver The address to receive `assets`.
     * @param _owner The address whose shares are burnt.
     * @return assets The actual amount of underlying withdrawn.
     */
    function redeem(uint256 shares, address receiver, address _owner) external returns (uint256) {
        // We default to not limiting a potential loss.
        return redeem(shares, receiver, _owner, MAX_BPS);
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
    ) public virtual nonReentrant returns (uint256) {}

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
    function maxDeposit(address receiver) external view returns (uint256) {
        return _maxDeposit(_strategyStorage(), receiver);
    }

    /**
     * @notice Total number of shares that can be minted to `receiver`
     * of a {mint} call.
     *
     * @param receiver The address receiving the shares.
     * @return _maxMint The max that `receiver` can mint in shares.
     */
    function maxMint(address receiver) external view returns (uint256) {
        return _maxMint(_strategyStorage(), receiver);
    }

    /**
     * @notice Total number of underlying assets that can be
     * withdrawn from the strategy by `owner`, where `owner`
     * corresponds to the msg.sender of a {redeem} call.
     *
     * @param _owner The owner of the shares.
     * @return _maxWithdraw Max amount of `asset` that can be withdrawn.
     */
    function maxWithdraw(address _owner) external view virtual returns (uint256) {}

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxWithdraw(address _owner, uint256 /*maxLoss*/) external view virtual returns (uint256) {}

    /**
     * @notice Total number of strategy shares that can be
     * redeemed from the strategy by `owner`, where `owner`
     * corresponds to the msg.sender of a {redeem} call.
     *
     * @param _owner The owner of the shares.
     * @return _maxRedeem Max amount of shares that can be redeemed.
     */
    function maxRedeem(address _owner) external view returns (uint256) {
        return _maxRedeem(_strategyStorage(), _owner);
    }

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxRedeem(address _owner, uint256 /*maxLoss*/) external view returns (uint256) {
        return _maxRedeem(_strategyStorage(), _owner);
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
    ) internal view returns (uint256) {
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
    function _convertToAssets(
        StrategyData storage S,
        uint256 shares,
        Math.Rounding _rounding
    ) internal view returns (uint256) {
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
    function _maxMint(StrategyData storage S, address receiver) internal view virtual returns (uint256 maxMint_) {
        // Cannot mint when shutdown or to the strategy.
        if (S.shutdown || receiver == address(this)) return 0;

        maxMint_ = IBaseStrategy(address(this)).availableDepositLimit(receiver);
        if (maxMint_ != type(uint256).max) {
            maxMint_ = _convertToShares(S, maxMint_, Math.Rounding.Floor);
        }
    }

    /// @dev Internal implementation of {maxWithdraw}.
    function _maxWithdraw(StrategyData storage S, address _owner) internal view virtual returns (uint256 maxWithdraw_) {
        // Get the max the owner could withdraw currently.
        maxWithdraw_ = IBaseStrategy(address(this)).availableWithdrawLimit(_owner);

        // If there is no limit enforced.
        if (maxWithdraw_ == type(uint256).max) {
            // Saves a min check if there is no withdrawal limit.
            maxWithdraw_ = _convertToAssets(S, _balanceOf(S, _owner), Math.Rounding.Floor);
        } else {
            maxWithdraw_ = Math.min(_convertToAssets(S, _balanceOf(S, _owner), Math.Rounding.Floor), maxWithdraw_);
        }
    }

    /// @dev Internal implementation of {maxRedeem}.
    function _maxRedeem(StrategyData storage S, address _owner) internal view virtual returns (uint256 maxRedeem_) {}

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
    function _deposit(StrategyData storage S, address receiver, uint256 assets, uint256 shares) internal nonReentrant {
        // Cache storage variables used more than once.
        ERC20 _asset = S.asset;
        address target = IBaseStrategy(address(this)).target();
        if (target == address(0)) revert TokenizedStrategy__NotOperator();

        if (msg.sender == target || msg.sender == S.operator) {
            if (address(_asset) == ETH) {
                require(
                    IAvatar(target).execTransactionFromModule(address(this), assets, "", Enum.Operation.Call),
                    TokenizedStrategy__DepositMoreThanMax()
                );
            } else {
                require(
                    IAvatar(target).execTransactionFromModule(
                        address(_asset),
                        0,
                        abi.encodeWithSignature("transfer(address,uint256)", address(this), assets),
                        Enum.Operation.Call
                    ),
                    TokenizedStrategy__TransferFailed()
                );
            }
        } else {
            if (address(_asset) == ETH) {
                require(msg.value >= assets, TokenizedStrategy__DepositMoreThanMax());
            } else {
                require(_asset.transferFrom(msg.sender, address(this), assets), TokenizedStrategy__TransferFailed());
            }
        }

        // We can deploy the full loose balance currently held.
        IBaseStrategy(address(this)).deployFunds(
            address(_asset) == ETH ? address(this).balance : _asset.balanceOf(address(this))
        );

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
    // solhint-disable-next-line code-complexity
    function _withdraw(
        StrategyData storage S,
        address receiver,
        address _owner,
        uint256 assets,
        uint256 shares,
        uint256 maxLoss
    ) internal virtual returns (uint256) {
        if (receiver == address(0)) revert ZeroAddress();
        if (maxLoss > MAX_BPS) revert TokenizedStrategy__InvalidMaxLoss();

        // Spend allowance if applicable.
        if (msg.sender != _owner) {
            _spendAllowance(S, _owner, msg.sender, shares);
        }

        // Cache `asset` since it is used multiple times..
        ERC20 _asset = S.asset;

        uint256 idle = address(_asset) == ETH ? address(this).balance : _asset.balanceOf(address(this));
        uint256 loss;
        // Check if we need to withdraw funds.
        if (idle < assets) {
            // Tell Strategy to free what we need.
            unchecked {
                IBaseStrategy(address(this)).freeFunds(assets - idle);
            }

            // Return the actual amount withdrawn. Adjust for potential under withdraws.
            idle = address(_asset) == ETH ? address(this).balance : _asset.balanceOf(address(this));

            // If we didn't get enough out then we have a loss.
            if (idle < assets) {
                unchecked {
                    loss = assets - idle;
                }
                // If a non-default max loss parameter was set.
                if (maxLoss < MAX_BPS) {
                    // Make sure we are within the acceptable range.
                    if (loss > (assets * maxLoss) / MAX_BPS) revert TokenizedStrategy__TooMuchLoss();
                }
                // Lower the amount to be withdrawn.
                assets = idle;
            }
        }

        // Update assets based on how much we took.
        S.totalAssets -= (assets + loss);

        _burn(S, _owner, shares);

        if (address(S.asset) == ETH) {
            (bool success, ) = receiver.call{ value: assets }("");
            if (!success) revert TokenizedStrategy__TransferFailed();
        } else {
            // Transfer the amount of underlying to the receiver.
            _asset.safeTransfer(receiver, assets);
        }

        emit Withdraw(msg.sender, receiver, _owner, assets, shares);

        // Return the actual amount of assets withdrawn.
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                        PROFIT REPORTING
    //////////////////////////////////////////////////////////////*/

    function report() external virtual nonReentrant onlyKeepers returns (uint256 profit, uint256 loss) {}

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
        ERC20 _asset = _strategyStorage().asset;
        uint256 _balance = address(_asset) == ETH ? address(this).balance : _asset.balanceOf(address(this));
        // Tend the strategy with the current loose balance.
        IBaseStrategy(address(this)).tendThis(_balance);
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
        if (!_strategyStorage().shutdown) revert TokenizedStrategy__StrategyNotInShutdown();

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

    function operator() external view returns (address) {
        return _strategyStorage().operator;
    }

    function dragonRouter() external view returns (address) {
        return _strategyStorage().dragonRouter;
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
     * @notice The timestamp of the last time protocol fees were charged.
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
    function pricePerShare() external view returns (uint256) {
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
        if (_management == address(0)) revert ZeroAddress();
        _strategyStorage().pendingManagement = _management;

        emit UpdatePendingManagement(_management);
    }

    /**
     * @notice Step two of two to set a new 'management' of the strategy.
     * @dev Can only be called by the current `pendingManagement`.
     */
    function acceptManagement() external {
        StrategyData storage S = _strategyStorage();
        if (msg.sender != S.pendingManagement) revert TokenizedStrategy__NotPendingManagement();
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
        _strategyStorage().emergencyAdmin = _emergencyAdmin;

        emit UpdateEmergencyAdmin(_emergencyAdmin);
    }

    /**
     * @notice Updates the name for the strategy.
     * @param _name The new name for the strategy.
     */
    function setName(string calldata _name) external virtual onlyManagement {
        _strategyStorage().name = _name;
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
     * @dev Will be 'ys + asset symbol'.
     * @return . The symbol the strategy is using for its tokens.
     */
    function symbol() external view returns (string memory) {
        return string(abi.encodePacked("dgn", _strategyStorage().asset.symbol()));
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
    function transfer(address to, uint256 amount) external virtual returns (bool) {}

    /**
     * @notice Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     * @param _owner The address who owns the shares.
     * @param _spender The address who would be moving the owners shares.
     * @return . The remaining amount of shares of `_owner` that could be moved by `_spender`.
     */
    function allowance(address _owner, address _spender) external view returns (uint256) {
        return _allowance(_strategyStorage(), _owner, _spender);
    }

    /// @dev Internal implementation of {allowance}.
    function _allowance(StrategyData storage S, address _owner, address _spender) internal view returns (uint256) {
        return S.allowances[_owner][_spender];
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
    function approve(address spender, uint256 amount) external virtual returns (bool) {
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
    function transferFrom(address from, address to, uint256 amount) external virtual returns (bool) {}

    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing
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
        if (account == address(0)) revert TokenizedStrategy__MintToZeroAddress();

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
        if (account == address(0)) revert TokenizedStrategy__BurnFromZeroAddress();

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
    function _approve(StrategyData storage S, address _owner, address _spender, uint256 amount) internal {
        if (_owner == address(0)) revert TokenizedStrategy__ApproveFromZeroAddress();
        if (_spender == address(0)) revert TokenizedStrategy__ApproveToZeroAddress();

        S.allowances[_owner][_spender] = amount;
        emit Approval(_owner, _spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(StrategyData storage S, address _owner, address _spender, uint256 amount) internal {
        uint256 currentAllowance = _allowance(S, _owner, _spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert TokenizedStrategy__InsufficientAllowance();
            unchecked {
                _approve(S, _owner, _spender, currentAllowance - amount);
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
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external virtual {
        if (_deadline < block.timestamp) revert TokenizedStrategy__PermitDeadlineExpired();

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
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                _owner,
                                _spender,
                                _value,
                                _strategyStorage().nonces[_owner]++,
                                _deadline
                            )
                        )
                    )
                ),
                _v,
                _r,
                _s
            );

            if (recoveredAddress == address(0) || recoveredAddress != _owner) revert TokenizedStrategy__InvalidSigner();

            _approve(_strategyStorage(), recoveredAddress, _spender, _value);
        }
    }

    /**
     * @notice Returns the domain separator used in the encoding of the signature
     * for {permit}, as defined by {EIP712}.
     *
     * @return . The domain separator that will be used for any {permit} calls.
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
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

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _strategyStorage().asset = ERC20(address(1));
    }

    function _onlySelf() internal view {
        if (msg.sender != address(this)) revert TokenizedStrategy__NotSelf();
    }

    /**
     * @notice Sets up Hats Protocol integration for role management
     * @dev Can only be called by management
     * @param _hats The Hats Protocol contract address
     * @param _keeperHat The hat ID for keeper role
     * @param _managementHat The hat ID for management role
     * @param _emergencyAdminHat The hat ID for emergency admin role
     * @param _regenGovernanceHat The hat ID for regen governance role
     */
    function setupHatsProtocol(
        address _hats,
        uint256 _keeperHat,
        uint256 _managementHat,
        uint256 _emergencyAdminHat,
        uint256 _regenGovernanceHat
    ) external onlyManagement {
        StrategyData storage S = _strategyStorage();
        if (S.hatsInitialized) revert TokenizedStrategy__HatsAlreadyInitialized();
        if (_hats == address(0)) revert TokenizedStrategy__InvalidHatsAddress();

        S.HATS = IHats(_hats);
        S.KEEPER_HAT = _keeperHat;
        S.MANAGEMENT_HAT = _managementHat;
        S.EMERGENCY_ADMIN_HAT = _emergencyAdminHat;
        S.REGEN_GOVERNANCE_HAT = _regenGovernanceHat;
        S.hatsInitialized = true;

        emit HatsProtocolSetup(_hats, _keeperHat, _managementHat, _emergencyAdminHat, _regenGovernanceHat);
    }

    /**
     * @dev Base function to check if an address wears a specific hat
     * @param S Storage pointer
     * @param _wearer Address to check
     * @param _hatId Hat ID to verify
     * @return bool True if wearer has the hat, false otherwise
     */
    function _isHatsWearer(StrategyData storage S, address _wearer, uint256 _hatId) internal view returns (bool) {
        if (!S.hatsInitialized) return false;
        try S.HATS.isWearerOfHat(_wearer, _hatId) returns (bool isWearer) {
            return isWearer;
        } catch {
            return false;
        }
    }
}
