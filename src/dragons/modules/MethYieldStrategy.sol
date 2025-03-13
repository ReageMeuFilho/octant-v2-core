// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import { DragonBaseStrategy } from "src/dragons/vaults/DragonBaseStrategy.sol";
import { IERC4626Payable } from "src/interfaces/IERC4626Payable.sol";
import { IMantleStaking } from "src/interfaces/IMantleStaking.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { IMethYieldStrategy } from "src/interfaces/IMethYieldStrategy.sol";
import { IYieldBearingDragonTokenizedStrategy } from "src/interfaces/IYieldBearingDragonTokenizedStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MethYieldStrategy
 * @notice A strategy that manages mETH (Mantle liquid staked ETH) and captures yield from its appreciation
 * @dev This strategy tracks the ETH value of mETH deposits and captures yield as mETH appreciates
 */
contract MethYieldStrategy is DragonBaseStrategy, IMethYieldStrategy {
    /// @dev The Mantle staking contract that provides exchange rate information
    IMantleStaking public immutable MANTLE_STAKING = IMantleStaking(0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f);

    /// @dev The ETH value of 1 mETH at the last harvest, scaled by 1e18
    uint256 public lastExchangeRate;

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @dev owner of this module will the safe multisig that calls setUp function
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

        // The asset is mETH from Mantle
        address _asset = _mETH;

        __Ownable_init(msg.sender);
        string memory _name = "Octant mETH Yield Strategy";
        __BaseStrategy_init(
            _tokenizedStrategyImplementation,
            _asset,
            _owner,
            _management,
            _keeper,
            _dragonRouter,
            _maxReportDelay,
            _name,
            _regenGovernance
        );

        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);

        // Initialize the exchange rate
        lastExchangeRate = _getCurrentExchangeRate();
    }

    /**
     * @inheritdoc IMethYieldStrategy
     */
    function getCurrentExchangeRate() public view returns (uint256) {
        return _getCurrentExchangeRate();
    }

    /**
     * @dev No funds deployment needed as mETH already generates yield
     * @param _amount Amount to deploy (ignored in this strategy)
     */
    function _deployFunds(uint256 _amount) internal override {
        // No action needed - mETH is already a yield-bearing asset
        // This function is required by the interface but doesn't need implementation
    }

    /**
     * @dev Emergency withdrawal is just transferring mETH tokens
     * @param _amount Amount of mETH to withdraw in emergency
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        // Transfer the mETH tokens to the emergency admin
        address emergencyAdmin = ITokenizedStrategy(address(this)).emergencyAdmin();
        asset.transfer(emergencyAdmin, _amount);
    }

    /**
     * @dev No funds to free as we're just transferring mETH tokens
     * @param _amount Amount to free (ignored in this strategy)
     */
    function _freeFunds(uint256 _amount) internal override {
        // No action needed - we just need to transfer mETH tokens
        // Withdrawal is handled by the TokenizedStrategy layer
    }

    /**
     * @dev Gets the current exchange rate from the Mantle staking contract
     * @return The current exchange rate (mETH to ETH ratio, scaled by 1e18)
     */
    function _getCurrentExchangeRate() internal view virtual returns (uint256) {
        // Calculate the exchange rate by determining how much ETH 1e18 mETH is worth
        return MANTLE_STAKING.mETHToETH(1e18);
    }

    /**
     * @dev Captures yield by calculating the increase in ETH value of our mETH holdings
     * @return totalAssets The total mETH balance after accounting for yield
     */
    function _harvestAndReport() internal virtual override returns (uint256) {
        // Get current exchange rate
        uint256 currentExchangeRate = _getCurrentExchangeRate();

        // fetch available yield
        uint256 availableYield = IYieldBearingDragonTokenizedStrategy(address(this)).availableYield();

        address assetAddress = IERC4626Payable(address(this)).asset();

        // Get actual mETH balance
        uint256 mEthBalance = IERC20(assetAddress).balanceOf(address(this)) - availableYield;

        uint256 accountingBalance = IERC4626Payable(address(this)).totalAssets();

        // Calculate the adjusted balance that accounts for value appreciation
        uint256 adjustedBalance;
        if (currentExchangeRate > lastExchangeRate) {
            // 1. Calculate the ETH value at current and previous rates
            uint256 currentEthValue = (mEthBalance * currentExchangeRate) / 1e18;
            uint256 previousEthValue = (mEthBalance * lastExchangeRate) / 1e18;

            // 2. The profit in ETH terms is the difference
            uint256 profitInEth = currentEthValue - previousEthValue;

            // 3. Convert this profit to mETH at the current exchange rate
            uint256 profitInMEth = (profitInEth * 1e18) / currentExchangeRate;

            // 4. Add this profit to the ACCOUNTING balance (not just the raw token balance)
            adjustedBalance = accountingBalance + profitInMEth;
        } else {
            // No appreciation or depreciation
            adjustedBalance = accountingBalance;
        }

        // Update the exchange rate for next time
        lastExchangeRate = currentExchangeRate;

        // Return the adjusted balance which includes the profit
        return adjustedBalance;
    }

    /**
     * @dev No tending needed as mETH already generates yield
     */
    function _tend(uint256 /*_idle*/) internal override {
        // No action needed - mETH is already a yield-bearing asset
    }

    /**
     * @dev Always returns false as no tending is needed
     * @return Always false as tending is not required
     */
    function _tendTrigger() internal pure override returns (bool) {
        return false;
    }
}
