// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { IAvatar } from "zodiac/interfaces/IAvatar.sol";
import { ZeroAddress, ReentrancyGuard__ReentrantCall, TokenizedStrategy__NotOperator, TokenizedStrategy__NotManagement, TokenizedStrategy__NotKeeperOrManagement, TokenizedStrategy__NotRegenGovernance, TokenizedStrategy__NotEmergencyAuthorized, TokenizedStrategy__AlreadyInitialized, TokenizedStrategy__DepositMoreThanMax, TokenizedStrategy__InvalidMaxLoss, TokenizedStrategy__MintToZeroAddress, TokenizedStrategy__BurnFromZeroAddress, TokenizedStrategy__ApproveFromZeroAddress, TokenizedStrategy__ApproveToZeroAddress, TokenizedStrategy__InsufficientAllowance, TokenizedStrategy__PermitDeadlineExpired, TokenizedStrategy__InvalidSigner, TokenizedStrategy__NotSelf, TokenizedStrategy__TransferFailed, TokenizedStrategy__NotPendingManagement, TokenizedStrategy__StrategyNotInShutdown, TokenizedStrategy__TooMuchLoss, TokenizedStrategy__HatsAlreadyInitialized, TokenizedStrategy__InvalidHatsAddress } from "src/errors.sol";

import { IBaseStrategy } from "src/zodiac-core/interfaces/IBaseStrategy.sol";
import { IHats } from "src/zodiac-core/interfaces/IHats.sol";
import { ITokenizedStrategy } from "src/zodiac-core/interfaces/ITokenizedStrategy.sol";
import { IERC4626Payable } from "src/zodiac-core/interfaces/IERC4626Payable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

abstract contract TokenizedStrategy is ITokenizedStrategy {
    using Math for uint256;
    using SafeERC20 for ERC20;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // using this address to represent native ETH

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

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _strategyStorage().asset = ERC20(address(1));
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /**
     * @inheritdoc ITokenizedStrategy
     */
    function initialize(
        address _asset,
        string memory _name,
        address _owner,
        address _management,
        address _keeper,
        address _dragonRouter,
        address _regenGovernance
    ) external virtual {
        // Initialize the strategy
        __TokenizedStrategy_init(_asset, _name, _owner, _management, _keeper, _dragonRouter, _regenGovernance);
    }

    /*//////////////////////////////////////////////////////////////
                      ERC4626 WRITE METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IERC4626Payable
     */
    function deposit(
        uint256 assets,
        address receiver
    ) external payable virtual nonReentrant onlyOperator returns (uint256 shares) {}

    /**
     * @inheritdoc IERC4626Payable
     */
    function mint(
        uint256 shares,
        address receiver
    ) external payable virtual nonReentrant onlyOperator returns (uint256 assets) {}

    /**
     * @inheritdoc IERC4626Payable
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        return withdraw(assets, receiver, owner, 0);
    }

    /// @inheritdoc IERC4626Payable
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        // We default to not limiting a potential loss.
        return redeem(shares, receiver, owner, MAX_BPS);
    }

    /*//////////////////////////////////////////////////////////////
                        PROFIT REPORTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function report() external virtual nonReentrant onlyKeepers returns (uint256 profit, uint256 loss) {}

    /*//////////////////////////////////////////////////////////////
                            TENDING
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizedStrategy
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
     * @inheritdoc ITokenizedStrategy
     */
    function shutdownStrategy() external onlyEmergencyAuthorized {
        _strategyStorage().shutdown = true;

        emit StrategyShutdown();
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function emergencyWithdraw(uint256 amount) external nonReentrant onlyEmergencyAuthorized {
        // Make sure the strategy has been shutdown.
        if (!_strategyStorage().shutdown) revert TokenizedStrategy__StrategyNotInShutdown();

        // Withdraw from the yield source.
        IBaseStrategy(address(this)).shutdownWithdraw(amount);
    }

    /*//////////////////////////////////////////////////////////////
                        SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function setPendingManagement(address _management) external onlyManagement {
        if (_management == address(0)) revert ZeroAddress();
        _strategyStorage().pendingManagement = _management;

        emit UpdatePendingManagement(_management);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function acceptManagement() external {
        StrategyData storage S = _strategyStorage();
        if (msg.sender != S.pendingManagement) revert TokenizedStrategy__NotPendingManagement();
        S.management = msg.sender;
        S.pendingManagement = address(0);

        emit UpdateManagement(msg.sender);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function setKeeper(address _keeper) external onlyManagement {
        _strategyStorage().keeper = _keeper;

        emit UpdateKeeper(_keeper);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function setEmergencyAdmin(address _emergencyAdmin) external onlyManagement {
        _strategyStorage().emergencyAdmin = _emergencyAdmin;

        emit UpdateEmergencyAdmin(_emergencyAdmin);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function setName(string calldata _name) external virtual onlyManagement {
        _strategyStorage().name = _name;
    }

    /**
     * @inheritdoc ITokenizedStrategy
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
     * @inheritdoc IERC20Permit
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
     * @inheritdoc IERC20
     */
    function approve(address spender, uint256 amount) external virtual returns (bool) {
        _approve(_strategyStorage(), msg.sender, spender, amount);
        return true;
    }

    /**
     * @inheritdoc IERC20
     */
    function transferFrom(address from, address to, uint256 amount) external virtual returns (bool) {}

    /**
     * @inheritdoc IERC20
     */
    function transfer(address to, uint256 amount) external virtual returns (bool) {}

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL 4626 VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IERC4626Payable
     */
    function totalAssets() external view returns (uint256) {
        return _totalAssets(_strategyStorage());
    }

    /**
     * @inheritdoc IERC20
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply(_strategyStorage());
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function convertToShares(uint256 assets) external view returns (uint256) {
        return _convertToShares(_strategyStorage(), assets, Math.Rounding.Floor);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _convertToAssets(_strategyStorage(), shares, Math.Rounding.Floor);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return _convertToShares(_strategyStorage(), assets, Math.Rounding.Floor);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function previewMint(uint256 shares) external view returns (uint256) {
        return _convertToAssets(_strategyStorage(), shares, Math.Rounding.Ceil);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return _convertToShares(_strategyStorage(), assets, Math.Rounding.Ceil);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function previewRedeem(uint256 shares) external view returns (uint256) {
        return _convertToAssets(_strategyStorage(), shares, Math.Rounding.Floor);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function maxDeposit(address receiver) external view returns (uint256) {
        return _maxDeposit(_strategyStorage(), receiver);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function maxMint(address receiver) external view returns (uint256) {
        return _maxMint(_strategyStorage(), receiver);
    }

    /**
     * @inheritdoc IERC4626Payable
     */
    function maxWithdraw(address owner) external view virtual returns (uint256) {}

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function maxWithdraw(address owner, uint256 /*maxLoss*/) external view virtual override returns (uint256) {}

    /**
     * @inheritdoc IERC4626Payable
     */
    function maxRedeem(address owner) external view returns (uint256) {
        return _maxRedeem(_strategyStorage(), owner);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function maxRedeem(address owner, uint256 /*maxLoss*/) external view returns (uint256) {
        return _maxRedeem(_strategyStorage(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                        GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IERC4626Payable
     */
    function asset() external view returns (address) {
        return address(_strategyStorage().asset);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function management() external view returns (address) {
        return _strategyStorage().management;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function pendingManagement() external view returns (address) {
        return _strategyStorage().pendingManagement;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function operator() external view returns (address) {
        return _strategyStorage().operator;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function dragonRouter() external view returns (address) {
        return _strategyStorage().dragonRouter;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function keeper() external view returns (address) {
        return _strategyStorage().keeper;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function emergencyAdmin() external view returns (address) {
        return _strategyStorage().emergencyAdmin;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function lastReport() external view returns (uint256) {
        return uint256(_strategyStorage().lastReport);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function hats() external view returns (address) {
        return address(_strategyStorage().HATS);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function keeperHat() external view returns (uint256) {
        return _strategyStorage().KEEPER_HAT;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function managementHat() external view returns (uint256) {
        return _strategyStorage().MANAGEMENT_HAT;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function emergencyAdminHat() external view returns (uint256) {
        return _strategyStorage().EMERGENCY_ADMIN_HAT;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function regenGovernanceHat() external view returns (uint256) {
        return _strategyStorage().REGEN_GOVERNANCE_HAT;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function pricePerShare() external view returns (uint256) {
        StrategyData storage S = _strategyStorage();
        return _convertToAssets(S, 10 ** S.decimals, Math.Rounding.Floor);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function isShutdown() external view returns (bool) {
        return _strategyStorage().shutdown;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IERC20Metadata
     */
    function name() external view returns (string memory) {
        return _strategyStorage().name;
    }

    /**
     * @inheritdoc IERC20Metadata
     */
    function symbol() external view returns (string memory) {
        return string(abi.encodePacked("dgn", _strategyStorage().asset.symbol()));
    }

    /**
     * @inheritdoc IERC20Metadata
     */
    function decimals() external view returns (uint8) {
        return _strategyStorage().decimals;
    }

    /**
     * @inheritdoc IERC20
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf(_strategyStorage(), account);
    }

    /**
     * @inheritdoc IERC20
     */
    function allowance(address _owner, address _spender) external view returns (uint256) {
        return _allowance(_strategyStorage(), _owner, _spender);
    }

    /**
     * @inheritdoc IERC20Permit
     */
    function nonces(address _owner) external view returns (uint256) {
        return _strategyStorage().nonces[_owner];
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function apiVersion() external pure returns (string memory) {
        return API_VERSION;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public virtual nonReentrant returns (uint256 shares) {}

    /// @inheritdoc ITokenizedStrategy
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public virtual nonReentrant returns (uint256) {}

    /*//////////////////////////////////////////////////////////////
                        MODIFIER HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizedStrategy
     */
    function requireManagement(address _sender) public view {
        StrategyData storage S = _strategyStorage();
        if (_sender != S.management && !_isHatsWearer(S, _sender, S.MANAGEMENT_HAT)) {
            revert TokenizedStrategy__NotManagement();
        }
    }

    /**
     * @inheritdoc ITokenizedStrategy
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
     * @inheritdoc ITokenizedStrategy
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
     * @inheritdoc ITokenizedStrategy
     */
    function requireRegenGovernance(address _sender) public view {
        StrategyData storage S = _strategyStorage();
        if (_sender != S.REGEN_GOVERNANCE && !_isHatsWearer(S, _sender, S.REGEN_GOVERNANCE_HAT)) {
            revert TokenizedStrategy__NotRegenGovernance();
        }
    }

    /**
     * @inheritdoc IERC20Permit
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

    /**
     * @dev Internal initialization function
     */
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
        S.minimumLockupDuration = 90 days;
        S.rageQuitCooldownPeriod = 90 days;

        // Emit event to signal a new strategy has been initialized.
        emit NewTokenizedStrategy(address(this), _asset, API_VERSION);
    }

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
            uint256 previousBalance;
            if (address(_asset) == ETH) {
                previousBalance = address(this).balance;
                IAvatar(target).execTransactionFromModule(address(this), assets, "", Enum.Operation.Call);
                //slither-disable-next-line incorrect-equality
                require(address(this).balance == previousBalance + assets, TokenizedStrategy__DepositMoreThanMax());
            } else {
                previousBalance = _asset.balanceOf(address(this));
                IAvatar(target).execTransactionFromModule(
                    address(_asset),
                    0,
                    abi.encodeWithSignature("transfer(address,uint256)", address(this), assets),
                    Enum.Operation.Call
                );
                //slither-disable-next-line incorrect-equality
                require(
                    _asset.balanceOf(address(this)) == previousBalance + assets,
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
        uint256 loss = 0;
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

    /// @dev Internal implementation of {allowance}.
    function _allowance(StrategyData storage S, address _owner, address _spender) internal view returns (uint256) {
        return S.allowances[_owner][_spender];
    }

    /// @dev Internal implementation of {balanceOf}.
    function _balanceOf(StrategyData storage S, address account) internal view returns (uint256) {
        return S.balances[account];
    }

    function _onlySelf() internal view {
        if (msg.sender != address(this)) revert TokenizedStrategy__NotSelf();
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

    /*//////////////////////////////////////////////////////////////
                            STORAGE GETTER
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal implementation of {maxRedeem}.
    function _maxRedeem(StrategyData storage S, address _owner) internal view virtual returns (uint256 maxRedeem_) {}

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
}
