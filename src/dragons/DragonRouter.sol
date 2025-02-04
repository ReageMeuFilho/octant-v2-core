// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { AccessControlUpgradeable } from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { ITransformer } from "src/interfaces/ITransformer.sol";
import "src/interfaces/ISplitChecker.sol";

/**
 * @title Dragon Router
 * @dev This contract manages the distribution of ERC20 tokens among shareholders,
 * with the ability to transform the split token into another token upon withdrawal,
 * and allows authorized pushers to directly distribute splits.
 */
contract DragonRouter is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant SPLIT_PRECISION = 1e18;
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("OCTANT_GOVERNANCE_ROLE");
    bytes32 public constant REGEN_GOVERNANCE_ROLE = keccak256("REGEN_GOVERNANCE_ROLE");
    bytes32 public constant SPLIT_DISTRIBUTOR_ROLE = keccak256("SPLIT_DISTRIBUTOR_ROLE");
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public DRAGON_SPLIT_COOLDOWN_PERIOD;
    uint256 public SPLIT_DELAY;
    ISplitChecker public splitChecker;
    address public opexVault;
    address public metapool;
    Split public split;
    uint256 public lastSetSplitTime;
    address[] public strategies;

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
                            MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address strategy => StrategyData data) public strategyData;
    mapping(address user => mapping(address strategy => UserData data)) public userData;

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
    event UserTransformerSet(address indexed user, address transformer, address targetToken);
    event SplitClaimed(address indexed user, address indexed strategy, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyAdded();
    error StrategyNotDefined();
    error InvalidAmount();
    error ZeroAddress();
    error NoShares();
    error CooldownPeriodNotPassed();
    error TransferFailed();
    error NotAllowed();

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @dev owner of this module will the safe multisig that calls setUp function
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public initializer {
        DRAGON_SPLIT_COOLDOWN_PERIOD = 30 days;
        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));

        (
            address[] memory _strategy,
            address[] memory _asset,
            address _governance,
            address _regen_governance,
            address _splitChecker,
            address _opexVault,
            address _metapool
        ) = abi.decode(data, (address[], address[], address, address, address, address, address));

        __AccessControl_init();
        __ReentrancyGuard_init();

        _setSplitChecker(_splitChecker);
        _setMetapool(_metapool);
        _setOpexVault(_opexVault);

        for (uint256 i = 0; i < _strategy.length; i++) {
            strategyData[_strategy[i]].asset = _asset[i];
            strategyData[_strategy[i]].totalShares = SPLIT_PRECISION;
            userData[_metapool][_strategy[i]].splitPerShare = SPLIT_PRECISION;
        }

        split.recipients = [_metapool];
        split.allocations = [SPLIT_PRECISION];
        split.totalAllocations = SPLIT_PRECISION;

        strategies = _strategy;
        _grantRole(OWNER_ROLE, _owner);
        _grantRole(GOVERNANCE_ROLE, _governance);
        _grantRole(REGEN_GOVERNANCE_ROLE, _regen_governance);
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new strategy to the router
     * @param _strategy Address of the strategy to add
     * @dev Only callable by accounts with OWNER_ROLE
     * @dev Strategy must not already be added
     */
    function addStrategy(address _strategy) external onlyRole(OWNER_ROLE) {
        StrategyData storage _stratData = strategyData[_strategy];
        if (_stratData.asset != address(0)) revert AlreadyAdded();

        for (uint256 i = 0; i < split.recipients.length; i++) {
            userData[split.recipients[i]][_strategy].splitPerShare = split.allocations[i];
        }

        _stratData.totalShares = split.totalAllocations;
        strategies.push(_strategy);

        emit StrategyAdded(_strategy);
    }

    /**
     * @notice Removes a strategy from the router
     * @param _strategy Address of the strategy to remove
     * @dev Only callable by accounts with OWNER_ROLE
     * @dev Strategy must exist in the router
     */
    function removeStrategy(address _strategy) external onlyRole(OWNER_ROLE) {
        StrategyData storage _stratData = strategyData[_strategy];
        if (_stratData.asset == address(0)) revert StrategyNotDefined();

        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == _strategy) {
                strategies[i] = strategies[strategies.length - 1];
                strategies.pop();
                break;
            }
        }

        for (uint256 i = 0; i < split.recipients.length; i++) {
            UserData storage _userData = userData[split.recipients[i]][_strategy];
            uint256 claimableAssets = _claimableAssets(_userData, _strategy);
            _userData.assets += claimableAssets;
            _userData.userAssetPerShare = 0;
            _userData.splitPerShare = 0;
        }

        delete strategyData[_strategy];

        emit StrategyRemoved(_strategy);
    }

    /**
     * @notice Updates the metapool address
     * @param _metapool New metapool address
     * @dev Only callable by accounts with GOVERNANCE_ROLE
     */
    function setMetapool(address _metapool) external onlyRole(GOVERNANCE_ROLE) {
        _setMetapool(_metapool);
    }

    /**
     * @notice Updates the opex vault address
     * @param _opexVault New opex vault address
     * @dev Only callable by accounts with OWNER_ROLE
     */
    function setOpexVault(address _opexVault) external onlyRole(OWNER_ROLE) {
        _setOpexVault(_opexVault);
    }

    /**
     * @notice Updates the split delay
     * @param _splitDelay New split delay in seconds
     * @dev Only callable by accounts with OWNER_ROLE
     */
    function setSplitDelay(uint256 _splitDelay) external onlyRole(OWNER_ROLE) {
        _setSplitDelay(_splitDelay);
    }

    /**
     * @notice Updates the split checker contract address
     * @param _splitChecker New split checker contract address
     * @dev Only callable by accounts with OWNER_ROLE
     */
    function setSplitChecker(address _splitChecker) external onlyRole(GOVERNANCE_ROLE) {
        _setSplitChecker(_splitChecker);
    }

    /**
     * @dev Allows a user to set their transformer for split withdrawals.
     * @param strategy The address of the strategy to set the transformer for.
     * @param transformer The address of the transformer contract.
     * @param targetToken The address of the token to transform into.
     */
    function setTransformer(address strategy, address transformer, address targetToken) external {
        if (balanceOf(msg.sender, strategy) == 0) revert NoShares();
        userData[msg.sender][strategy].transformer = Transformer(ITransformer(transformer), targetToken);

        emit UserTransformerSet(msg.sender, transformer, targetToken);
    }

    /**
     * @dev Allows a user to decide if claim function can be called on their behalf for a particular strategy.
     * @param strategy The address of the strategy to set the transformer for.
     * @param enable If false, only user will be able to call claim. If true, anyone will be able to do it.
     */
    function setClaimAutomation(address strategy, bool enable) external {
        userData[msg.sender][strategy].allowBotClaim = enable;
    }

    /**
     * @notice Updates the cooldown period
     * @param _cooldownPeriod New cooldown period in seconds
     * @dev Only callable by accounts with REGEN_GOVERNANCE_ROLE
     */
    function setCooldownPeriod(uint256 _cooldownPeriod) external onlyRole(REGEN_GOVERNANCE_ROLE) {
        _setCooldownPeriod(_cooldownPeriod);
    }

    /**
     * @notice Returns the balance of a user for a given strategy
     * @param _user The address of the user
     * @param _strategy The address of the strategy
     * @return The balance of the user for the strategy
     */
    function balanceOf(address _user, address _strategy) public view returns (uint256) {
        UserData memory _userData = userData[_user][_strategy];

        return _userData.assets + _claimableAssets(_userData, _strategy);
    }

    /**
     * @dev Distributes new splits to all shareholders.
     * @param amount The amount of tokens to distribute.
     */
    function fundFromSource(address strategy, uint256 amount) external onlyRole(SPLIT_DISTRIBUTOR_ROLE) nonReentrant {
        StrategyData storage data = strategyData[strategy];
        if (data.asset == address(0)) revert ZeroAddress();

        ITokenizedStrategy(strategy).withdraw(amount, address(this), address(this), 0);

        data.assetPerShare += (amount * SPLIT_PRECISION) / data.totalShares;
        data.totalAssets += amount;
    }

    /**
     * @notice Sets the split for the router
     * @param _split The split to set
     * @dev Only callable by accounts with OWNER_ROLE
     */
    function setSplit(Split memory _split) external onlyRole(OWNER_ROLE) {
        if (block.timestamp - lastSetSplitTime < DRAGON_SPLIT_COOLDOWN_PERIOD) revert CooldownPeriodNotPassed();
        splitChecker.checkSplit(_split, opexVault, metapool);

        for (uint256 i = 0; i < strategies.length; i++) {
            StrategyData storage data = strategyData[strategies[i]];

            /// @dev updates old splitters
            for (uint256 j = 0; j < split.recipients.length; j++) {
                UserData storage _userData = userData[split.recipients[j]][strategies[i]];
                uint256 claimableAssets = _claimableAssets(_userData, strategies[i]);
                _userData.assets += claimableAssets;
                _userData.userAssetPerShare = 0;
                _userData.splitPerShare = 0;
            }

            /// @dev assign to new splitters
            for (uint256 j = 0; j < _split.recipients.length; j++) {
                userData[_split.recipients[j]][strategies[i]].splitPerShare = _split.allocations[j];
            }

            data.assetPerShare = 0;
            data.totalAssets = 0;
            data.totalShares = _split.totalAllocations;
        }

        split = _split;
        lastSetSplitTime = block.timestamp;
    }

    /**
     * @dev Allows a user to claim their available split, optionally transforming it.
     * @param _strategy The address of the strategy to claim from
     * @param _amount The amount of split to claim
     */
    function claimSplit(address _user, address _strategy, uint256 _amount) external nonReentrant {
        if (_amount == 0 || balanceOf(_user, _strategy) < _amount) revert InvalidAmount();
        if (!(userData[_user][_strategy].allowBotClaim || msg.sender == _user)) revert NotAllowed();

        _updateUserSplit(_user, _strategy, _amount);

        _transferSplit(_user, _strategy, _amount);

        emit SplitClaimed(_user, _strategy, _amount);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to update a user's split
     * @param _user The address of the user
     * @param _strategy The address of the strategy
     * @param _amount The amount of split to update
     */
    function _updateUserSplit(address _user, address _strategy, uint256 _amount) internal {
        UserData storage _userData = userData[msg.sender][_strategy];
        _userData.assets = balanceOf(_user, _strategy) - _amount;
        _userData.userAssetPerShare = strategyData[_strategy].assetPerShare;
    }

    /**
     * @notice Internal function to calculate the claimable assets for a user from a split
     * @param _userData The user data
     * @param _strategy The strategy address
     * @return The claimable assets
     */
    function _claimableAssets(UserData memory _userData, address _strategy) internal view returns (uint256) {
        StrategyData memory _stratData = strategyData[_strategy];
        return
            (_userData.splitPerShare *
                _stratData.totalShares *
                (_stratData.assetPerShare - _userData.userAssetPerShare)) / SPLIT_PRECISION;
    }

    /**
     * @notice Internal function to set the cooldown period
     * @param _cooldownPeriod New cooldown period in seconds
     */
    function _setCooldownPeriod(uint256 _cooldownPeriod) internal {
        emit CooldownPeriodUpdated(DRAGON_SPLIT_COOLDOWN_PERIOD, _cooldownPeriod);
        DRAGON_SPLIT_COOLDOWN_PERIOD = _cooldownPeriod;
    }

    /**
     * @notice Internal function to set the split checker contract
     * @param _splitChecker New split checker contract address
     * @dev Validates the new address is not zero
     */
    function _setSplitChecker(address _splitChecker) internal {
        if (_splitChecker == address(0)) revert ZeroAddress();
        emit SplitCheckerUpdated(address(splitChecker), _splitChecker);
        splitChecker = ISplitChecker(_splitChecker);
    }

    /**
     * @notice Internal function to set the metapool address
     * @param _metapool New metapool address
     * @dev Validates the new address is not zero
     */
    function _setMetapool(address _metapool) internal {
        if (_metapool == address(0)) revert ZeroAddress();
        emit MetapoolUpdated(metapool, _metapool);

        metapool = _metapool;
    }

    /**
     * @notice Internal function to set the split delay
     * @param _splitDelay New split delay in seconds
     */
    function _setSplitDelay(uint256 _splitDelay) internal {
        emit SplitDelayUpdated(SPLIT_DELAY, _splitDelay);
        SPLIT_DELAY = _splitDelay;
    }

    /**
     * @notice Internal function to set the opex vault address
     * @param _opexVault New opex vault address
     * @dev Validates the new address is not zero
     */
    function _setOpexVault(address _opexVault) internal {
        if (_opexVault == address(0)) revert ZeroAddress();
        emit OpexVaultUpdated(opexVault, _opexVault);

        opexVault = _opexVault;
    }

    /**
     * @notice Internal function to transfer split to a user, applying transformation if set.
     * @param _user The address of the user to receive the split.
     * @param _strategy The address of the strategy whose assets to transform
     * @param _amount The amount of split to transfer.
     */
    function _transferSplit(address _user, address _strategy, uint256 _amount) internal {
        Transformer memory userTransformer = userData[_user][_strategy].transformer;
        address _asset = strategyData[_strategy].asset;
        if (address(userTransformer.transformer) != address(0)) {
            IERC20(_asset).approve(address(userTransformer.transformer), _amount);
            uint256 _transformedAmount = _asset == NATIVE_TOKEN
                ? userTransformer.transformer.transform{ value: _amount }(_asset, userTransformer.targetToken, _amount)
                : userTransformer.transformer.transform(_asset, userTransformer.targetToken, _amount);
            if (userTransformer.targetToken == NATIVE_TOKEN) {
                (bool success, ) = _user.call{ value: _transformedAmount }("");
                if (!success) revert TransferFailed();
            } else {
                IERC20(userTransformer.targetToken).safeTransfer(_user, _transformedAmount);
            }
        } else {
            if (_asset == NATIVE_TOKEN) {
                (bool success, ) = _user.call{ value: _amount }("");
                if (!success) revert TransferFailed();
            } else {
                IERC20(_asset).safeTransfer(_user, _amount);
            }
        }
    }
}
