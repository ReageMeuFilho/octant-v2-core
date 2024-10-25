// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITokenizedStrategy} from "src/interfaces/ITokenizedStrategy.sol";
import "src/interfaces/ISplitChecker.sol";
import {ITransformer} from "src/interfaces/ITransformer.sol";

/**
 * @title Advanced Non-Transferable Single Token Split Vault
 * @dev This contract manages the distribution of a single ERC20 token among shareholders,
 * with the ability to transform the split token into another token upon withdrawal,
 * and allows authorized pushers to directly distribute splits.
 */
contract DragonRouter is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // --- Constants ---
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant SPLIT_DISTRIBUTOR_ROLE = keccak256("SPLIT_DISTRIBUTOR_ROLE");
    bytes32 public constant SPLIT_PUSHER_ROLE = keccak256("SPLIT_PUSHER_ROLE");
    uint256 private constant SPLIT_PRECISION = 1e18;

    // --- State Variables ---

    /// @dev octant goverance can change this
    uint256 public COOL_DOWN_PERIOD = 30 days;
    uint256 public SPLIT_DELAY; // TODO
    ISplitChecker public splitChecker;
    address public opexVault;
    address public metapool;
    Split public split;
    uint256 public lastSetSplitTime;
    address[] public strategies;
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // --- Structs ---

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
    }

    struct Transformer {
        ITransformer transformer;
        address targetToken;
    }

    // --- Mappings ---
    mapping(address strategy => StrategyData data) public strategyData;

    mapping(address user => mapping(address strategy => UserData data)) public userData;

    // --- Events ---
    event SplitDistributed(uint256 amount);
    event SplitClaimed(address indexed user, uint256 amount, address token);
    event SharesMinted(address indexed user, uint256 amount);
    event SharesBurned(address indexed user, uint256 amount);
    event UserTransformerSet(address indexed user, address transformer, address targetToken);
    event SplitPushed(address indexed user, uint256 amount, address token);

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @dev owner of this module will the safe multisig that calls setUp function
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public initializer {
        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));

        (
            address[] memory _strategy,
            address[] memory _asset,
            address _splitChecker,
            address _opexVault,
            address _metapool
        ) = abi.decode(data, (address[], address[], address, address, address));

        __AccessControl_init();
        __ReentrancyGuard_init();

        require(_splitChecker != address(0));
        splitChecker = ISplitChecker(_splitChecker);
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
    }

    // TODO: add way for dragon to set more strategies.
    function addStrategy(address _strategy) external onlyRole(OWNER_ROLE) {
        StrategyData storage _stratData = strategyData[_strategy];
        require(_stratData.asset == address(0), "Already Added");

        for (uint256 i = 0; i < split.recipients.length; i++) {
            userData[split.recipients[i]][_strategy].splitPerShare = split.allocations[i];
        }

        _stratData.totalShares = split.totalAllocations;
        strategies.push(_strategy);

        // Emit
    }

    function removeStrategy(address _strategy) external onlyRole(OWNER_ROLE) {
        StrategyData storage _stratData = strategyData[_strategy];
        require(_stratData.asset != address(0), "Strategy not defined");

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
            /// TODO check for precision loss
            _userData.userAssetPerShare = 0;
            _userData.splitPerShare = 0;
        }

        _stratData.asset = address(0);
        _stratData.assetPerShare = 0;
        _stratData.totalAssets = 0;
        _stratData.totalShares = 0;

        // Emit
    }

    function setMetapool(address _metapool) external onlyRole(OWNER_ROLE) {
        _setMetapool(_metapool);
    }

    function _setMetapool(address _metapool) internal {
        require(_metapool != address(0));
        // emit MetapoolUpdated(metapool, _metapool);

        metapool = _metapool;
    }

    function setOpexVault(address _opexVault) external onlyRole(OWNER_ROLE) {
        _setOpexVault(_opexVault);
    }

    function _setOpexVault(address _opexVault) internal {
        require(_opexVault != address(0));
        // emit OpexVaultUpdated(opexVault, _opexVault);

        opexVault = _opexVault;
    }

    /**
     * @dev Allows a user to set their transformer for split withdrawals.
     * @param strategy The address of the strategy to set the transformer for.
     * @param transformer The address of the transformer contract.
     * @param targetToken The address of the token to transform into.
     */
    function setTransformer(address strategy, address transformer, address targetToken) external {
        require(balanceOf(msg.sender, strategy) > 0, "Must have shares to set transformer");
        userData[msg.sender][strategy].transformer = Transformer(ITransformer(transformer), targetToken);
    }

    function _claimableAssets(UserData memory _userData, address _strategy) internal view returns (uint256) {
        StrategyData memory _stratData = strategyData[_strategy];
        return _userData.splitPerShare * _stratData.totalShares
            * (_stratData.assetPerShare - _userData.userAssetPerShare) / SPLIT_PRECISION;
    }

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
        require(data.asset != address(0));

        ITokenizedStrategy(strategy).withdraw(amount, address(this), address(this), 0);

        data.assetPerShare += (amount * SPLIT_PRECISION) / data.totalShares;
        data.totalAssets += amount;
    }

    function setSplit(Split memory _split) external onlyRole(OWNER_ROLE) {
        require(block.timestamp - lastSetSplitTime >= COOL_DOWN_PERIOD);
        splitChecker.checkSplit(_split, opexVault, metapool);

        for (uint256 i = 0; i < strategies.length; i++) {
            StrategyData storage data = strategyData[strategies[i]];

            /// @dev update old splitters
            for (uint256 j = 0; j < split.recipients.length; j++) {
                UserData storage _userData = userData[split.recipients[j]][strategies[i]];
                uint256 claimableAssets = _claimableAssets(_userData, strategies[i]);
                _userData.assets += claimableAssets;
                /// TODO check for precision loss
                _userData.userAssetPerShare = 0;
                _userData.splitPerShare = 0;
            }

            /// @dev assign to new splitters
            for (uint256 j = 0; j < _split.recipients.length; j++) {
                userData[_split.recipients[j]][strategies[i]].splitPerShare = _split.allocations[j];
            }

            data.assetPerShare = 0;
            data.totalAssets = 0;
            /// TODO check for precision loss
            data.totalShares = _split.totalAllocations;
        }

        split = _split;
        lastSetSplitTime = block.timestamp;
    }

    function _updateUserSplit(address _user, address _strategy, uint256 _amount) internal {
        UserData storage _userData = userData[msg.sender][_strategy];
        _userData.assets = balanceOf(_user, _strategy) - _amount;
        _userData.userAssetPerShare = strategyData[_strategy].assetPerShare;
    }

    /**
     * @dev Allows a user to claim their available split, optionally transforming it.
     */
    function claimSplit(address _strategy, uint256 _amount) external nonReentrant {
        require(_amount > 0 && balanceOf(msg.sender, _strategy) >= _amount, "Invalid Amount");
        _updateUserSplit(msg.sender, _strategy, _amount);

        _transferSplit(msg.sender, _strategy, _amount);
    }

    /**
     * @dev Internal function to transfer split to a user, applying transformation if set.
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
                ? userTransformer.transformer.transform{value: _amount}(_asset, userTransformer.targetToken, _amount)
                : userTransformer.transformer.transform(_asset, userTransformer.targetToken, _amount);
            if (userTransformer.targetToken == NATIVE_TOKEN) {
                (bool success,) = _user.call{value: _transformedAmount}("");
                require(success);
            } else {
                IERC20(userTransformer.targetToken).safeTransfer(_user, _transformedAmount);
            }
        } else {
            if (_asset == NATIVE_TOKEN) {
                (bool success,) = _user.call{value: _amount}("");
                require(success);
            } else {
                IERC20(_asset).safeTransfer(_user, _amount);
            }
        }
    }

    receive() external payable {}
}
