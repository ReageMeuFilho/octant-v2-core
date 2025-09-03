// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseHealthCheck } from "src/strategies/periphery/BaseHealthCheck.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MorphoCompounderStrategy
/// @author Octant
/// @notice Yearn v3 Strategy that donates rewards.
contract MorphoCompounderStrategy is BaseHealthCheck {
    using SafeERC20 for IERC20;

    // morpho vault
    address public immutable compounderVault;

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
        require(IERC4626(_compounderVault).asset() == _asset, "Asset mismatch with compounder vault");
        IERC20(_asset).forceApprove(_compounderVault, type(uint256).max);
        compounderVault = _compounderVault;
    }

    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        uint256 vaultLimit = IERC4626(compounderVault).maxDeposit(address(this));
        uint256 idleBalance = IERC20(asset).balanceOf(address(this));
        return vaultLimit > idleBalance ? vaultLimit - idleBalance : 0;
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this)) + IERC4626(compounderVault).maxWithdraw(address(this));
    }

    function _deployFunds(uint256 _amount) internal override {
        IERC4626(compounderVault).deposit(_amount, address(this));
    }

    function _freeFunds(uint256 _amount) internal override {
        IERC4626(compounderVault).withdraw(_amount, address(this), address(this));
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }

    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // get strategy's balance in the vault
        uint256 shares = IERC4626(compounderVault).balanceOf(address(this));
        uint256 vaultAssets = IERC4626(compounderVault).convertToAssets(shares);

        // include idle funds as per BaseStrategy specification
        uint256 idleAssets = IERC20(asset).balanceOf(address(this));

        _totalAssets = vaultAssets + idleAssets;

        return _totalAssets;
    }
}
