// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626Payable } from "./IERC4626Payable.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IHats } from "./IHats.sol";

// Interface that implements the 4626 Payable and Permit standard and the implementation functions
interface ITokenizedStrategy is IERC4626Payable, IERC20Permit {
    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
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
        uint256 minimumLockupDuration;
        uint256 rageQuitCooldownPeriod;
        address REGEN_GOVERNANCE;
        // Hats protocol integration
        IHats HATS;
        uint256 KEEPER_HAT;
        uint256 MANAGEMENT_HAT;
        uint256 EMERGENCY_ADMIN_HAT;
        uint256 REGEN_GOVERNANCE_HAT;
        bool hatsInitialized; // Flag for Hats Protocol initialization
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event StrategyShutdown();

    event NewTokenizedStrategy(address indexed strategy, address indexed asset, string apiVersion);

    event Reported(uint256 profit, uint256 loss, uint256 protocolFees, uint256 performanceFees);

    event UpdateKeeper(address indexed newKeeper);

    event UpdateManagement(address indexed newManagement);

    event UpdateEmergencyAdmin(address indexed newEmergencyAdmin);

    event UpdatePendingManagement(address indexed newPendingManagement);

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
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address _asset,
        string memory _name,
        address _owner,
        address _management,
        address _keeper,
        address _dragonRouter,
        address _regenGovernance
    ) external;

    /*//////////////////////////////////////////////////////////////
                        KEEPERS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows keeper to maintain the strategy
     * @dev Can be used for operations like compounding or regular maintenance
     */
    function tend() external;

    /**
     * @notice Reports profit or loss for the strategy
     * @return _profit Amount of profit generated
     * @return _loss Amount of loss incurred
     */
    function report() external returns (uint256 _profit, uint256 _loss);

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets a new pending management address
     * @param _pendingManagement The new pending management address
     */
    function setPendingManagement(address _pendingManagement) external;

    /**
     * @notice Allows pending management to accept and become active management
     */
    function acceptManagement() external;

    /**
     * @notice Sets a new keeper address
     * @param _keeper The new keeper address
     */
    function setKeeper(address _keeper) external;

    /**
     * @notice Sets a new emergency admin address
     * @param _emergencyAdmin The new emergency admin address
     */
    function setEmergencyAdmin(address _emergencyAdmin) external;

    /**
     * @notice Updates the strategy token name
     * @param _newName The new name for the strategy token
     */
    function setName(string calldata _newName) external;

    /**
     * @notice Shuts down the strategy, preventing further deposits
     */
    function shutdownStrategy() external;

    /**
     * @notice Allows emergency withdrawal of assets from yield source
     * @param _amount The amount of assets to withdraw
     */
    function emergencyWithdraw(uint256 _amount) external;

    /*//////////////////////////////////////////////////////////////
                            HATS PROTOCOL
    //////////////////////////////////////////////////////////////*/

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
    ) external;

    /*//////////////////////////////////////////////////////////////
                    NON-STANDARD 4626 OPTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraws assets from the strategy, allowing a specified maximum loss
     * @param assets The amount of assets to withdraw
     * @param receiver The address receiving the assets
     * @param owner The owner of the shares being burned
     * @param maxLoss The maximum acceptable loss in basis points (10000 = 100%)
     * @return The actual amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner, uint256 maxLoss) external returns (uint256);

    /**
     * @notice Redeems shares from the strategy, allowing a specified maximum loss
     * @param shares The amount of shares to redeem
     * @param receiver The address receiving the assets
     * @param owner The owner of the shares being burned
     * @param maxLoss The maximum acceptable loss in basis points (10000 = 100%)
     * @return The actual amount of assets withdrawn
     */
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss) external returns (uint256);

    /**
     * @notice Gets the maximum amount of assets that can be withdrawn
     * @param owner The address of the owner
     * @param maxLoss The maximum acceptable loss in basis points
     * @return The maximum amount of assets that can be withdrawn
     */
    function maxWithdraw(address owner, uint256 maxLoss) external view returns (uint256);

    /**
     * @notice Gets the maximum amount of shares that can be redeemed
     * @param owner The address of the owner
     * @param maxLoss The maximum acceptable loss in basis points
     * @return The maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner, uint256 maxLoss) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        MODIFIER HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if the sender is authorized as management
     * @param _sender The address to check
     */
    function requireManagement(address _sender) external view;

    /**
     * @notice Checks if the sender is authorized as keeper or management
     * @param _sender The address to check
     */
    function requireKeeperOrManagement(address _sender) external view;

    /**
     * @notice Checks if the sender is authorized for emergency actions
     * @param _sender The address to check
     */
    function requireEmergencyAuthorized(address _sender) external view;

    /**
     * @notice Require a caller is `regenGovernance`.
     * @dev Is left public so that it can be used by the Strategy.
     *
     * When the Strategy calls this the msg.sender would be the
     * address of the strategy so we need to specify the sender.
     *
     * @param _sender The original msg.sender.
     */
    function requireRegenGovernance(address _sender) external view;

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the API version of the strategy implementation
     * @return String representing the API version
     */
    function apiVersion() external view returns (string memory);

    /**
     * @notice Returns the current price per share
     * @return Price per share value
     */
    function pricePerShare() external view returns (uint256);

    /**
     * @notice Returns the operator address for the strategy
     * @return The operator address
     */
    function operator() external view returns (address);

    /**
     * @notice Returns the Dragon Router address
     * @return The Dragon Router address
     */
    function dragonRouter() external view returns (address);

    /**
     * @notice Returns the current management address
     * @return The management address
     */
    function management() external view returns (address);

    /**
     * @notice Returns the name of the strategy
     * @return The name of the strategy
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the pending management address
     * @return The pending management address
     */
    function pendingManagement() external view returns (address);

    /**
     * @notice Returns the current keeper address
     * @return The keeper address
     */
    function keeper() external view returns (address);

    /**
     * @notice Returns the emergency admin address
     * @return The emergency admin address
     */
    function emergencyAdmin() external view returns (address);

    /**
     * @notice Returns the timestamp of the last report
     * @return The last report timestamp
     */
    function lastReport() external view returns (uint256);

    /**
     * @notice Returns the Hats Protocol address
     * @return The Hats Protocol address
     */
    function hats() external view returns (address);

    /**
     * @notice Returns the keeper hat ID
     * @return The keeper hat ID
     */
    function keeperHat() external view returns (uint256);

    /**
     * @notice Returns the management hat ID
     * @return The management hat ID
     */
    function managementHat() external view returns (uint256);

    /**
     * @notice Returns the emergency admin hat ID
     * @return The emergency admin hat ID
     */
    function emergencyAdminHat() external view returns (uint256);

    /**
     * @notice Returns the regen governance hat ID
     * @return The regen governance hat ID
     */
    function regenGovernanceHat() external view returns (uint256);

    /**
     * @notice Checks if the strategy is currently shutdown
     * @return True if the strategy is shutdown, false otherwise
     */
    function isShutdown() external view returns (bool);
}
