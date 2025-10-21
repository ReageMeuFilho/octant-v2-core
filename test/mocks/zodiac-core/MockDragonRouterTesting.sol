// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "src/zodiac-core/DragonRouter.sol";
import { IDragonRouter } from "src/zodiac-core/interfaces/IDragonRouter.sol";
import { ITransformer } from "src/zodiac-core/interfaces/ITransformer.sol";

/**
 * @title DragonRouterTesting
 * @dev Extension of DragonRouter that exposes internal functions for testing
 */
contract MockDragonRouterTesting is DragonRouter {
    /**
     * @dev Exposes the internal _updateUserSplit function for testing
     */
    function exposed_updateUserSplit(address _user, address _strategy, uint256 _amount) external {
        _updateUserSplit(_user, _strategy, _amount);
    }
    /**
     * @dev Exposes the internal _transferSplit function for testing
     */
    function exposed_transferSplit(address _user, address _strategy, uint256 _amount) external {
        _transferSplit(_user, _strategy, _amount);
    }
    /**
     * @dev Exposes the internal _claimableAssets function for testing
     */
    function exposed_claimableAssets(address _user, address _strategy) external view returns (uint256) {
        UserData memory _userData = userData[_user][_strategy];
        return _claimableAssets(_userData, _strategy);
    }

    /**
     * @dev Allows direct manipulation of userData storage for testing purposes
     * @param _user The user address
     * @param _strategy The strategy address
     * @param _assets The assets amount to set
     * @param _userAssetPerShare The userAssetPerShare to set
     * @param _splitPerShare The splitPerShare to set
     * @param _transformer The transformer to set
     * @param _allowBotClaim Whether to allow bot claims
     */
    function setUserDataForTest(
        address _user,
        address _strategy,
        uint256 _assets,
        uint256 _userAssetPerShare,
        uint256 _splitPerShare,
        IDragonRouter.Transformer memory _transformer,
        bool _allowBotClaim
    ) external {
        UserData storage data = userData[_user][_strategy];
        data.assets = _assets;
        data.userAssetPerShare = _userAssetPerShare;
        data.splitPerShare = _splitPerShare;
        data.transformer = _transformer;
        data.allowBotClaim = _allowBotClaim;
    }
    /**
     * @dev Allows direct manipulation of strategyData storage for testing purposes
     * @param _strategy The strategy address
     * @param _asset The asset address
     * @param _assetPerShare The assetPerShare value
     * @param _totalAssets The totalAssets value
     * @param _totalShares The totalShares value
     */
    function setStrategyDataForTest(
        address _strategy,
        address _asset,
        uint256 _assetPerShare,
        uint256 _totalAssets,
        uint256 _totalShares
    ) external {
        StrategyData storage data = strategyData[_strategy];
        data.asset = _asset;
        data.assetPerShare = _assetPerShare;
        data.totalAssets = _totalAssets;
        data.totalShares = _totalShares;
    }

    /**
     * @dev Implementation of setTransformer for testing purposes with a different name
     * to avoid override issues with the non-virtual function in DragonRouter
     */
    function setTransformerForTest(address strategy, address transformer, address targetToken) external {
        if (balanceOf(msg.sender, strategy) == 0) revert NoShares();
        userData[msg.sender][strategy].transformer = IDragonRouter.Transformer(ITransformer(transformer), targetToken);

        emit UserTransformerSet(msg.sender, strategy, transformer, targetToken);
    }
}
