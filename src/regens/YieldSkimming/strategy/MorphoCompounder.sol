// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import { BaseHealthCheck } from "../../periphery/BaseHealthCheck.sol";
import { UniswapV3Swapper } from "../../periphery/UniswapV3Swapper.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { WadRayMath } from "src/libraries/Maths/WadRay.sol";

/**
 * @title MorphoCompounder
 * @notice A strategy that manages deposits in a Morpho yield source and captures yield
 * @dev This strategy tracks the value of deposits and captures yield as the price per share increases
 */
contract MorphoCompounder is BaseHealthCheck, UniswapV3Swapper {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    /// @dev The exchange rate at the last harvest, scaled by 1e18
    uint256 internal lastReportedExchangeRate;

    /// @notice yearn governance
    address public constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }

    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress
    )
        BaseHealthCheck(
            _asset, // shares address
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress
        )
    {
        // Initialize the exchange rate on setup
        lastReportedExchangeRate = _getCurrentExchangeRate();
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance (onlyGovernance)
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external onlyGovernance {
        require(_token != address(asset), "!asset");
        IERC20(_token).safeTransfer(GOV, IERC20(_token).balanceOf(address(this)));
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
     * @notice Returns the last reported exchange rate
     * @return The last reported exchange rate
     */
    function getLastReportedExchangeRate() public view returns (uint256) {
        return lastReportedExchangeRate;
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

    function _executeHealthCheck(uint256 /*_newTotalAssets*/) internal override {
        if (!doHealthCheck) {
            doHealthCheck = true;
            return;
        }

        // // Get the current total assets from the implementation.
        // uint256 currentTotalAssets = TokenizedStrategy.totalAssets();

        // if (_newTotalAssets > currentTotalAssets) {
        //     require(
        //         ((_newTotalAssets - currentTotalAssets) <= (currentTotalAssets * uint256(_profitLimitRatio)) / MAX_BPS),
        //         "healthCheck"
        //     );
        // } else if (currentTotalAssets > _newTotalAssets) {
        //     require(
        //         (currentTotalAssets - _newTotalAssets <= ((currentTotalAssets * uint256(_lossLimitRatio)) / MAX_BPS)),
        //         "healthCheck"
        //     );
        // }
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
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        uint256 currentExchangeRate = _getCurrentExchangeRate();

        // Get the current balance of assets in the strategy
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));

        // Calculate the profit based on exchange rate difference
        uint256 deltaExchangeRate = currentExchangeRate > lastReportedExchangeRate
            ? currentExchangeRate - lastReportedExchangeRate
            : 0; // Only capture positive yield

        uint256 profitInValue = (assetBalance * deltaExchangeRate) / ERC20(asset).decimals();

        uint256 profitInYieldVaultShares = (profitInValue * ERC20(asset).decimals()) / currentExchangeRate;

        lastReportedExchangeRate = currentExchangeRate;

        return profitInYieldVaultShares;
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
        // Call the pricePerShare function on the yield vault
        return ITokenizedStrategy(address(asset)).pricePerShare();
    }

    /**
     * @notice Always returns false as no tending is needed
     * @return Always false as tending is not required
     */
    function _tendTrigger() internal pure override returns (bool) {
        return false;
    }
}
