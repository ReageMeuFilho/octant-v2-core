// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

import { ITransformer } from "./ITransformer.sol";
import { ISplitChecker } from "./ISplitChecker.sol";
/**
 * @dev     In charge of splitting yield profits from dragon strategy, in case of a loss strategy burns shares owned by the dragon module
 * @notice  Interface for the Dragon Router Contract
 */
interface IDragonRouter {
    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct StrategyData {
        address asset;
        uint256 assetPerShare;
        uint256 totalAssets;
        uint256 totalShares;
    }

    struct UserData {
        uint256 assets;
        uint256 userAssetPerShare;
        uint256 splitPerShare;
        Transformer transformer;
        bool allowBotClaim;
    }

    struct Transformer {
        ITransformer transformer;
        address targetToken;
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event MetapoolUpdated(address oldMetapool, address newMetapool);
    event OpexVaultUpdated(address oldOpexVault, address newOpexVault);
    event CooldownPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event SplitDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event SplitCheckerUpdated(address oldChecker, address newChecker);
    event UserTransformerSet(address indexed user, address indexed strategy, address transformer, address targetToken);
    event SplitClaimed(address indexed caller, address indexed owner, address indexed strategy, uint256 amount);
    event ClaimAutomationSet(address indexed user, address indexed strategy, bool enabled);
    event Funded(address indexed strategy, uint256 assetPerShare, uint256 totalAssets);
    event UserSplitUpdated(
        address indexed recipient,
        address indexed strategy,
        uint256 assets,
        uint256 userAssetPerShare,
        uint256 splitPerShare
    );
    event SplitSet(uint256 assetPerShare, uint256 totalAssets, uint256 totalShares, uint256 lastSetSplitTime);

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyAdded();
    error StrategyNotDefined();
    error InvalidAmount();
    error ZeroAddress();
    error ZeroAssetAddress();
    error NoShares();
    error CooldownPeriodNotPassed();
    error TransferFailed();
    error NotAllowed();

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new strategy to the router
     * @param _strategy Address of the strategy to add
     */
    function addStrategy(address _strategy) external;

    /**
     * @notice Removes a strategy from the router
     * @param _strategy Address of the strategy to remove
     */
    function removeStrategy(address _strategy) external;

    /**
     * @notice Updates the metapool address
     * @param _metapool New metapool address
     */
    function setMetapool(address _metapool) external;

    /**
     * @notice Updates the opex vault address
     * @param _opexVault New opex vault address
     */
    function setOpexVault(address _opexVault) external;

    /**
     * @notice Updates the split delay
     * @param _splitDelay New split delay in seconds
     */
    function setSplitDelay(uint256 _splitDelay) external;

    /**
     * @notice Updates the split checker contract address
     * @param _splitChecker New split checker contract address
     */
    function setSplitChecker(address _splitChecker) external;

    /**
     * @dev Allows a user to set their transformer for split withdrawals.
     * @param strategy The address of the strategy to set the transformer for.
     * @param transformer The address of the transformer contract.
     * @param targetToken The address of the token to transform into.
     */
    function setTransformer(address strategy, address transformer, address targetToken) external;

    /**
     * @dev Allows a user to decide if claim function can be called on their behalf for a particular strategy.
     * @param strategy The address of the strategy to set the transformer for.
     * @param enable If false, only user will be able to call claim. If true, anyone will be able to do it.
     */
    function setClaimAutomation(address strategy, bool enable) external;

    /**
     * @notice Updates the cooldown period
     * @param _cooldownPeriod New cooldown period in seconds
     */
    function setCooldownPeriod(uint256 _cooldownPeriod) external;

    /**
     * @dev Distributes new splits to all shareholders.
     * @param strategy The strategy address to fund from
     * @param amount The amount of tokens to distribute.
     */
    function fundFromSource(address strategy, uint256 amount) external;

    /**
     * @notice Sets the split for the router
     * @param _split The split to set
     */
    function setSplit(ISplitChecker.Split memory _split) external;

    /**
     * @notice Initializer function, triggered when a new proxy is deployed
     * @param initializeParams Parameters of initialization encoded
     */
    function setUp(bytes memory initializeParams) external;

    /**
     * @dev Allows a user to claim their available split, optionally transforming it.
     * @param _user The address of the user to claim for
     * @param _strategy The address of the strategy to claim from
     * @param _amount The amount of split to claim
     */
    function claimSplit(address _user, address _strategy, uint256 _amount) external;

    /**
     * @notice Returns the balance of a user for a given strategy
     * @param _user The address of the user
     * @param _strategy The address of the strategy
     * @return The balance of the user for the strategy
     */
    function balanceOf(address _user, address _strategy) external view returns (uint256);
}
