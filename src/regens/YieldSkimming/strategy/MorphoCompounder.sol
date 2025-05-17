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

    /// @dev The yield vault that provides exchange rate information
    address public immutable yieldVault;

    /// @dev The exchange rate at the last harvest, scaled by 1e18
    uint256 internal lastReportedExchangeRate;

    /// @notice yearn governance
    address public constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    uint256 private constant ASSET_DUST = 100;

    constructor(
        address _yieldVault,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress
    )
        BaseHealthCheck(
            address(ITokenizedStrategy(_yieldVault)), // shares address
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress
        )
    {
        yieldVault = _yieldVault;

        // Initialize the exchange rate on setup
        lastReportedExchangeRate = _getCurrentExchangeRate();

        // Approve the yield vault to spend the asset
        IERC20(asset).forceApprove(yieldVault, type(uint256).max);
    }

    /**
     * @notice Deposits available funds into the yield vault
     * @param _amount Amount to deploy
     */
    function _deployFunds(uint256 _amount) internal override {
        if (_amount > ASSET_DUST) {
            IERC20(asset).safeTransfer(yieldVault, _amount);
        }
    }

    /**
     * @notice Emergency withdrawal function to transfer tokens to emergency admin
     * @param _amount Amount to withdraw in emergency
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        // Transfer tokens directly to the emergency admin
        address emergencyAdmin = ITokenizedStrategy(address(this)).emergencyAdmin();
        IERC20(asset).safeTransfer(emergencyAdmin, _amount);
    }

    /**
     * @notice Withdraws funds from the yield vault
     * @param _amount Amount to free
     */
    function _freeFunds(uint256 _amount) internal override {
        // Withdraw the needed amount from the yield vault
        if (_amount > ASSET_DUST) {
            // The TokenizedStrategy layer will handle the withdrawal
            ITokenizedStrategy(yieldVault).withdraw(_amount, address(this), address(this));
        }
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

        uint256 profitInUSDC = (assetBalance * deltaExchangeRate) / ERC20(asset).decimals();

        uint256 profitInShares = (profitInUSDC * ERC20(yieldVault).decimals()) / currentExchangeRate;

        lastReportedExchangeRate = currentExchangeRate;

        return profitInShares;
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
        return ITokenizedStrategy(yieldVault).pricePerShare();
    }

    /**
     * @notice Always returns false as no tending is needed
     * @return Always false as tending is not required
     */
    function _tendTrigger() internal pure override returns (bool) {
        return false;
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
        return IERC20(yieldVault).balanceOf(address(this));
    }

    /**
     * @notice Returns the last reported exchange rate
     * @return The last reported exchange rate
     */
    function getLastReportedExchangeRate() public view returns (uint256) {
        return lastReportedExchangeRate;
    }

    /*//////////////////////////////////////////////////////////////
                GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    /// @notice Sweep of non-asset ERC20 tokens to governance (onlyGovernance)
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external onlyGovernance {
        require(_token != address(asset), "!asset");
        IERC20(_token).safeTransfer(GOV, IERC20(_token).balanceOf(address(this)));
    }

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }
}
