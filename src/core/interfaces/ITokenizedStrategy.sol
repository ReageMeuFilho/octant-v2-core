// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title Yearn V3 Tokenized Strategy Interface
 * @author yearn.finance
 * @notice Interface that implements the 4626 standard and the implementation functions
 * for the TokenizedStrategy contract.
 */
interface ITokenizedStrategy is IERC4626, IERC20Permit {
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
     * @notice Emitted when the 'pendingManagement' address is updated to 'newPendingManagement'.
     */
    event UpdatePendingManagement(address indexed newPendingManagement);

    /**
     * @notice Emitted when the dragon router address is updated.
     */
    event UpdateDragonRouter(address indexed newDragonRouter);

    /**
     * @notice Emitted when a pending dragon router change is initiated.
     */
    event PendingDragonRouterChange(address indexed newDragonRouter, uint256 effectiveTimestamp);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Used to initialize storage for a newly deployed strategy.
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
    ) external;

    /*//////////////////////////////////////////////////////////////
                        NON-STANDARD 4626 OPTIONS
    //////////////////////////////////////////////////////////////*/

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
    function withdraw(uint256 assets, address receiver, address owner, uint256 maxLoss) external returns (uint256);

    /**
     * @notice Redeems exactly `shares` from `owner` and
     * sends `assets` of underlying tokens to `receiver`.
     * @dev This includes an added parameter to allow for losses.
     * @param shares The amount of shares burnt.
     * @param receiver The address to receive `assets`.
     * @param owner The address whose shares are burnt.
     * @param maxLoss The amount of acceptable loss in Basis points.
     * @return The actual amount of underlying withdrawn.
     */
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss) external returns (uint256);

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxWithdraw(address owner, uint256 /*maxLoss*/) external view returns (uint256);

    /**
     * @notice Variable `maxLoss` is ignored.
     * @dev Accepts a `maxLoss` variable in order to match the multi
     * strategy vaults ABI.
     */
    function maxRedeem(address owner, uint256 /*maxLoss*/) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          MODIFIER HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Require a caller is `management`.
     * @param _sender The original msg.sender.
     */
    function requireManagement(address _sender) external view;

    /**
     * @notice Require a caller is the `keeper` or `management`.
     * @param _sender The original msg.sender.
     */
    function requireKeeperOrManagement(address _sender) external view;

    /**
     * @notice Require a caller is the `management` or `emergencyAdmin`.
     * @param _sender The original msg.sender.
     */
    function requireEmergencyAuthorized(address _sender) external view;

    /*//////////////////////////////////////////////////////////////
                          KEEPERS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice For a 'keeper' to 'tend' the strategy if a custom
     * tendTrigger() is implemented.
     */
    function tend() external;

    /**
     * @notice Function for keepers to call to harvest and record all
     * profits accrued.
     * @return _profit The notional amount of gain if any since the last
     * report in terms of `asset`.
     * @return _loss The notional amount of loss if any since the last
     * report in terms of `asset`.
     */
    function report() external returns (uint256 _profit, uint256 _loss);

    /*//////////////////////////////////////////////////////////////
                              GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the API version for this TokenizedStrategy.
     * @return The API version for this TokenizedStrategy
     */
    function apiVersion() external view returns (string memory);

    /**
     * @notice Get the price per share.
     * @return The price per share.
     */
    function pricePerShare() external view returns (uint256);

    /**
     * @notice Get the current address that controls the strategy.
     * @return Address of management
     */
    function management() external view returns (address);

    /**
     * @notice Get the current pending management address if any.
     * @return Address of pendingManagement
     */
    function pendingManagement() external view returns (address);

    /**
     * @notice Get the current address that can call tend and report.
     * @return Address of the keeper
     */
    function keeper() external view returns (address);

    /**
     * @notice Get the current address that can shutdown and emergency withdraw.
     * @return Address of the emergencyAdmin
     */
    function emergencyAdmin() external view returns (address);

    /**
     * @notice Get the current dragon router address that will receive minted shares.
     * @return Address of dragonRouter
     */
    function dragonRouter() external view returns (address);

    /**
     * @notice Get the pending dragon router address if any.
     * @return Address of the pending dragon router
     */
    function pendingDragonRouter() external view returns (address);

    /**
     * @notice Get the timestamp when dragon router change was initiated.
     * @return Timestamp of the dragon router change initiation
     */
    function dragonRouterChangeTimestamp() external view returns (uint256);

    /**
     * @notice The timestamp of the last time protocol fees were charged.
     * @return The last report.
     */
    function lastReport() external view returns (uint256);

    /**
     * @notice To check if the strategy has been shutdown.
     * @return Whether or not the strategy is shutdown.
     */
    function isShutdown() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                              SETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Step one of two to set a new address to be in charge of the strategy.
     * @param _management New address to set `pendingManagement` to.
     */
    function setPendingManagement(address _management) external;

    /**
     * @notice Step two of two to set a new 'management' of the strategy.
     */
    function acceptManagement() external;

    /**
     * @notice Sets a new address to be in charge of tend and reports.
     * @param _keeper New address to set `keeper` to.
     */
    function setKeeper(address _keeper) external;

    /**
     * @notice Sets a new address to be able to shutdown the strategy.
     * @param _emergencyAdmin New address to set `emergencyAdmin` to.
     */
    function setEmergencyAdmin(address _emergencyAdmin) external;

    /**
     * @notice Initiates a change to a new dragon router address with a cooldown period.
     * @param _dragonRouter New address to set as pending `dragonRouter`.
     */
    function setDragonRouter(address _dragonRouter) external;

    /**
     * @notice Finalizes the dragon router change after the cooldown period.
     */
    function finalizeDragonRouterChange() external;

    /**
     * @notice Cancels a pending dragon router change.
     */
    function cancelDragonRouterChange() external;

    /**
     * @notice Updates the name for the strategy.
     * @param _newName The new name for the strategy.
     */
    function setName(string calldata _newName) external;

    /**
     * @notice Used to shutdown the strategy preventing any further deposits.
     */
    function shutdownStrategy() external;

    /**
     * @notice To manually withdraw funds from the yield source after a
     * strategy has been shutdown.
     * @param _amount The amount of asset to attempt to free.
     */
    function emergencyWithdraw(uint256 _amount) external;
}
