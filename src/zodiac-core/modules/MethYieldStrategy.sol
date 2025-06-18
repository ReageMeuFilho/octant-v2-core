// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import { DragonBaseStrategy } from "src/zodiac-core/vaults/DragonBaseStrategy.sol";
import { YieldSkimmingHarvestReporter } from "src/zodiac-core/mixins/YieldSkimmingHarvestReporter.sol";
import { IERC4626Payable } from "src/zodiac-core/interfaces/IERC4626Payable.sol";
import { IMantleStaking } from "src/zodiac-core/interfaces/IMantleStaking.sol";
import { ITokenizedStrategy } from "src/zodiac-core/interfaces/ITokenizedStrategy.sol";
import { IMethYieldStrategy } from "src/zodiac-core/interfaces/IMethYieldStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { BaseYieldSkimmingHealthCheck } from "src/strategies/periphery/BaseYieldSkimmingHealthCheck.sol";

/**
 * @title MethYieldStrategy
 * @notice A strategy that manages mETH (Mantle liquid staked ETH) and captures yield from its appreciation
 * @dev This strategy tracks the ETH value of mETH deposits and captures yield as mETH appreciates in value.
 *      The strategy works with YieldSkimmingDragonTokenizedStrategy to properly handle the yield accounting.
 */
contract MethYieldStrategy is DragonBaseStrategy, IMethYieldStrategy, YieldSkimmingHarvestReporter {
    using SafeERC20 for IERC20;

    /// @dev The Mantle staking contract that provides exchange rate information
    IMantleStaking public immutable MANTLE_STAKING = IMantleStaking(0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f);

    /// @dev The ETH value of 1 mETH at the last harvest, scaled by 1e18
    uint256 internal _lastReportedExchangeRate;

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public override initializer {
        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));

        (
            address _tokenizedStrategyImplementation,
            address _management,
            address _keeper,
            address _dragonRouter,
            uint256 _maxReportDelay,
            address _regenGovernance,
            address _mETH
        ) = abi.decode(data, (address, address, address, address, uint256, address, address));
        // Effects
        __Ownable_init(msg.sender);
        string memory _name = "Octant mETH Yield Strategy";

        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);

        // Initialize the exchange rate on setup
        _lastReportedExchangeRate = _getCurrentExchangeRate();

        // Interactions
        __BaseStrategy_init(
            _tokenizedStrategyImplementation,
            _mETH,
            _owner,
            _management,
            _keeper,
            _dragonRouter,
            _maxReportDelay,
            _name,
            _regenGovernance
        );
    }

    /**
     * @inheritdoc IMethYieldStrategy
     */
    function getLastReportedExchangeRate() public view returns (uint256) {
        return _lastReportedExchangeRate;
    }

    /**
     * @notice Get the current balance of the asset
     * @return The asset balance in this contract
     */
    function balanceOfAsset() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /**
     * @notice Get the current balance of shares in the yield vault
     * @return The yield vault share balance
     */
    function balanceOfShares() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /**
     * @notice Deposits available funds into the yield vault
     * @param _amount Amount to deploy
     */
    function _deployFunds(uint256 _amount) internal override {
        // no action needed
    }

    /**
     * @notice Emergency withdrawal function to transfer tokens to emergency admin
     * @param _amount Amount to withdraw in emergency
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        // nothing to do here as assets are always held in the strategy
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
     * @return deltaAtNewRate The current delta of the strategy at the new exchange rate
     * @return deltaAtOldRate The current delta of the strategy at the old exchange rate
     */
    function _harvestAndReport() internal override returns (int256 deltaAtNewRate, int256 deltaAtOldRate) {
        uint256 currentExchangeRate = _getCurrentExchangeRate();

        // Get the current balance of assets in the strategy (not using totalSupply so that it goes to profit)
        uint256 assetBalance = ITokenizedStrategy(address(this)).totalAssets();

        // Calculate the profit based on exchange rate difference
        int256 deltaExchangeRate = int256(currentExchangeRate) - int256(_lastReportedExchangeRate);

        int256 deltaInValue = int256(assetBalance) * deltaExchangeRate;

        // Use high-precision division to avoid precision loss for small yields
        if (deltaInValue >= 0) {
            // For positive yields, use mulDiv with rounding up to preserve small yields
            deltaAtOldRate = int256(
                Math.mulDiv(uint256(deltaInValue), 1, _lastReportedExchangeRate, Math.Rounding.Ceil)
            );
            deltaAtNewRate = int256(Math.mulDiv(uint256(deltaInValue), 1, currentExchangeRate, Math.Rounding.Ceil));
        } else if (deltaInValue < 0) {
            // For losses, use mulDiv with rounding down (more conservative for losses)
            uint256 absDeltaInValue = uint256(-deltaInValue);
            deltaAtOldRate = -int256(Math.mulDiv(absDeltaInValue, 1, _lastReportedExchangeRate, Math.Rounding.Floor));
            deltaAtNewRate = -int256(Math.mulDiv(absDeltaInValue, 1, currentExchangeRate, Math.Rounding.Floor));
        }

        _lastReportedExchangeRate = currentExchangeRate;
    }

    /**
     * @notice No tending needed
     */
    function _tend(uint256 /*_idle*/) internal override {
        // No action needed
    }

    /**
     * @notice Gets the current exchange rate from the yield vault
     * @return The current price per share
     */
    function _getCurrentExchangeRate() internal view virtual returns (uint256) {
        // Calculate the exchange rate by determining how much ETH 1e18 mETH is worth
        return MANTLE_STAKING.mETHToETH(1e18);
    }

    /**
     * @notice Always returns false as no tending is needed
     * @return Always false as tending is not required
     */
    function _tendTrigger() internal pure override returns (bool) {
        return false;
    }
}
