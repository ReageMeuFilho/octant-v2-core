// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseHealthCheck } from "src/strategies/periphery/BaseHealthCheck.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MorphoCompounderStrategy
/// @author [Golem Foundation](https://golem.foundation)
/// @custom:security-contact security@golem.foundation
/// @notice Yearn v3 Strategy that donates rewards.
contract MorphoCompounderStrategy is BaseHealthCheck {
    using SafeERC20 for IERC20;

    // morpho vault
    address public immutable compounderVault;

    /**
     * @param _compounderVault Address of the Morpho vault this strategy compounds into
     * @param _asset Address of the underlying asset of the Morpho vault
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _compounderVault,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseHealthCheck(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        // make sure asset is Morpho's asset
        require(ITokenizedStrategy(_compounderVault).asset() == _asset, "Asset mismatch with compounder vault");
        IERC20(_asset).forceApprove(_compounderVault, type(uint256).max);
        compounderVault = _compounderVault;
    }

    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        uint256 vaultLimit = ITokenizedStrategy(compounderVault).maxDeposit(address(this));
        uint256 idleBalance = IERC20(asset).balanceOf(address(this));
        return vaultLimit > idleBalance ? vaultLimit - idleBalance : 0;
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this)) + ITokenizedStrategy(compounderVault).maxWithdraw(address(this));
    }

    function _deployFunds(uint256 _amount) internal override {
        ITokenizedStrategy(compounderVault).deposit(_amount, address(this));
    }

    function _freeFunds(uint256 _amount) internal override {
        // set max loss to 10 000 to avoid too much loss error
        ITokenizedStrategy(compounderVault).withdraw(_amount, address(this), address(this), 10_000);
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }

    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // get strategy's balance in the vault
        uint256 shares = ITokenizedStrategy(compounderVault).balanceOf(address(this));
        uint256 vaultAssets = ITokenizedStrategy(compounderVault).convertToAssets(shares);

        // include idle funds as per BaseStrategy specification
        uint256 idleAssets = IERC20(asset).balanceOf(address(this));

        _totalAssets = vaultAssets + idleAssets;

        return _totalAssets;
    }
}
