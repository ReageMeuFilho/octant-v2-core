// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseHealthCheck } from "../../periphery/BaseHealthCheck.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title Morpho
/// @author octant.finance
/// @notice Strategy for integrating with Morpho ERC-4626 vaults in the YieldSkimming framework
contract Morpho is BaseHealthCheck {
    using SafeERC20 for ERC20;

    // The Morpho vault address (ERC-4626 compliant)
    address public immutable morphoVault;

    // Tracks the total assets deployed to Morpho
    uint256 public virtualAssetsBalance;

    constructor(
        address _morphoVault,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress
    ) BaseHealthCheck(IERC4626(_morphoVault).asset(), _name, _management, _keeper, _emergencyAdmin, _donationAddress) {
        morphoVault = _morphoVault;

        // Approve Morpho vault to spend our assets
        ERC20(address(asset)).forceApprove(_morphoVault, type(uint256).max);
    }

    /// @notice Deploy funds to the Morpho vault
    /// @param _amount Amount of assets to deploy
    function _deployFunds(uint256 _amount) internal override {
        // Deposit assets into the Morpho vault
        IERC4626(morphoVault).deposit(_amount, address(this));

        // Update our tracking variable to account for new deposits
        virtualAssetsBalance += _amount;
    }

    /// @notice Withdraw funds from the Morpho vault
    /// @param _amount Amount of assets to withdraw
    function _freeFunds(uint256 _amount) internal override {
        IERC4626(morphoVault).withdraw(_amount, address(this), address(this));

        // Update our tracking variable to account for withdrawals
        virtualAssetsBalance -= _amount;
    }

    /// @notice Calculate profit and update tracking variables
    /// @return _totalAssets The total assets managed by this strategy
    function _harvestAndReport() internal override returns (uint256) {
        // Get the current value of our position in Morpho
        uint256 currentMorphoBalance = IERC4626(morphoVault).previewRedeem(
            IERC4626(morphoVault).balanceOf(address(this))
        );

        uint256 profit = currentMorphoBalance - virtualAssetsBalance;
        virtualAssetsBalance = currentMorphoBalance;

        return profit;
    }

    /// @notice Emergency withdraw from Morpho vault
    /// @param _amount The amount to try to withdraw
    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 withdrawAmount = _min(_amount, virtualAssetsBalance);
        _freeFunds(withdrawAmount);
    }

    /// @notice Get the balance of assets in the Morpho vault
    /// @return Balance of assets in Morpho vault
    function balanceOfMorpho() public view returns (uint256) {
        return IERC4626(morphoVault).previewRedeem(IERC4626(morphoVault).balanceOf(address(this)));
    }

    /// @notice Get the balance of assets in this contract
    /// @return Balance of assets in this contract
    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice Returns the minimum of two values
    /// @param a First value
    /// @param b Second value
    /// @return Minimum of a and b
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Check if the Morpho vault accepts deposits
    /// @return Deposit limit (max uint256 if available, 0 if not)
    function availableDepositLimit(address /*_owner*/) public pure override returns (uint256) {
        return type(uint256).max;
    }
}
