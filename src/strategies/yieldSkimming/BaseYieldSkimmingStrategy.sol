// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import { BaseYieldSkimmingHealthCheck } from "src/strategies/periphery/BaseYieldSkimmingHealthCheck.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title BaseYieldSkimmingStrategy
 * @notice Abstract base contract for yield skimming strategies that track exchange rate changes
 * @dev This contract provides common logic for strategies that capture yield from appreciating assets.
 *      Derived contracts only need to implement _getCurrentExchangeRate() for their specific yield source.
 */
abstract contract BaseYieldSkimmingStrategy is BaseYieldSkimmingHealthCheck {
    using SafeERC20 for IERC20;

    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseYieldSkimmingHealthCheck(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {}

    /**
     * @notice Get the current balance of the asset
     * @return The asset balance in this contract
     */
    function balanceOfAsset() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function getCurrentExchangeRate() public view returns (uint256) {
        return _getCurrentExchangeRate();
    }

    function decimalsOfExchangeRate() public view virtual returns (uint256);

    /**
     * @notice Deposits available funds into the yield vault
     * @param _amount Amount to deploy
     */
    function _deployFunds(uint256 _amount) internal override {
        // no action needed
    }

    /**
     * @notice Withdraws funds from the yield vault
     * @param _amount Amount to free
     */
    function _freeFunds(uint256 _amount) internal override {
        // no action needed
    }

    /**
     * @notice Captures yield by calculating the increase in value based on exchange rate changes
     * @return _totalAssets The current total assets of the strategy
     */
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // Return the actual balance of assets held by this strategy
        _totalAssets = IERC4626(address(this)).totalAssets();
    }

    /**
     * @notice Gets the current exchange rate from the yield vault
     * @return The current price per share
     */
    function _getCurrentExchangeRate() internal view virtual returns (uint256);
}
