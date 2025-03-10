// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { DragonTokenizedStrategy } from "./DragonTokenizedStrategy.sol";

import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { IMethYieldStrategy } from "src/interfaces/IMethYieldStrategy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYieldBearingDragonTokenizedStrategy } from "src/interfaces/IYieldBearingDragonTokenizedStrategy.sol";

/**
 * @title YieldBearingDragonTokenizedStrategy
 * @notice A specialized version of DragonTokenizedStrategy designed for yield-bearing tokens
 * like mETH whose value in ETH terms appreciates over time.
 *
 * @dev This strategy implements storage isolation, yield tracking, and ETH value accounting
 * to handle yield-bearing tokens in a secure and efficient manner.
 *
 * Key features:
 * 1. Storage Isolation: Uses dedicated storage slots to prevent collisions in proxy patterns
 * 2. ETH Value Tracking: Maintains accurate accounting of ETH value of deposits independent
 *    of token exchange rate fluctuations
 * 3. Yield Management: Separates principal from yield, allowing yield to be withdrawn separately
 * 4. Automatic Reporting: Ensures exchange rates are updated before critical operations
 *
 * The strategy tracks both the total ETH value of deposits and the available yield, enabling
 * accurate yield attribution while maintaining the ETH value of users' principal deposits
 * regardless of exchange rate changes.
 */
contract YieldBearingDragonTokenizedStrategy is DragonTokenizedStrategy, IYieldBearingDragonTokenizedStrategy {
    using Math for uint256;

    // Use fixed storage slots to avoid collisions in the proxy pattern
    bytes32 private constant YIELD_BEARING_STORAGE_POSITION = keccak256("dragon.yield-bearing.storage");

    /**
     * @inheritdoc IYieldBearingDragonTokenizedStrategy
     */
    function withdrawYield(
        uint256 amount,
        address receiver,
        address owner,
        uint256 maxLoss
    ) external returns (uint256) {
        YieldBearingStorage storage s = _yieldBearingStorage();

        // Check if there's enough yield available
        if (amount > s.availableYield) revert InsufficientYieldAvailable();
        if (receiver == address(0)) revert CannotWithdrawToZeroAddress();

        // Subtract from available yield
        uint256 previousYield = s.availableYield;
        s.availableYield -= amount;

        // Transfer the yield-bearing tokens to the receiver
        uint256 shares = super.withdraw(amount, receiver, owner, maxLoss);

        emit YieldWithdrawn(receiver, amount);
        emit AvailableYieldUpdated(previousYield, s.availableYield);

        return shares;
    }

    /**
     * @inheritdoc IYieldBearingDragonTokenizedStrategy

     */
    function redeemYield(uint256 amount, address receiver, address owner, uint256 maxLoss) external returns (uint256) {
        YieldBearingStorage storage s = _yieldBearingStorage();

        // Subtract from available yield
        uint256 previousYield = s.availableYield;

        // Transfer the yield-bearing tokens to the receiver
        uint256 assets = super.redeem(amount, receiver, owner, maxLoss);

        // reduce the yield available by the assets withdrawn
        s.availableYield -= assets;

        emit YieldWithdrawn(receiver, amount);
        emit AvailableYieldUpdated(previousYield, s.availableYield);

        return assets;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     * @dev Override redeem to automatically report before redemption and update total ETH value.
     * This implementation:
     * 1. Calls report() to ensure the latest exchange rate and yield state
     * 2. Gets and stores the current exchange rate
     * 3. Calculates the ETH value being withdrawn based on assets and exchange rate
     * 4. Updates the total ETH value deposited after redemption
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public override(DragonTokenizedStrategy, ITokenizedStrategy) returns (uint256 assets) {
        YieldBearingStorage storage s = _yieldBearingStorage();

        // First report to ensure we have the latest state
        ITokenizedStrategy(address(this)).report();

        // Get the current exchange rate
        uint256 exchangeRate = _getCurrentExchangeRate();
        s.currentExchangeRate = exchangeRate;

        // Determine how many assets these shares represent
        assets = _convertToAssets(super._strategyStorage(), shares, Math.Rounding.Floor);

        // Calculate the ETH value of these assets
        uint256 ethValueWithdrawn = (assets * exchangeRate) / 1e18;

        // Perform the redemption with parent implementation
        assets = super.redeem(shares, receiver, owner, maxLoss);

        uint256 previousTotalEthValue = s.totalEthValueDeposited;
        s.totalEthValueDeposited -= ethValueWithdrawn;

        emit TotalEthValueUpdated(previousTotalEthValue, s.totalEthValueDeposited);

        return assets;
    }

    /**
     * @inheritdoc ITokenizedStrategy
     * @dev Override report to update totalEthValueDeposited and track available yield.
     * This implementation:
     * 1. Gets and stores the current exchange rate
     * 2. Calls the parent implementation for profit/loss calculation
     * 3. If profit is generated, adds it to availableYield
     * 4. Recalculates the total ETH value based on current balance excluding yield
     */
    function report()
        public
        override(DragonTokenizedStrategy, ITokenizedStrategy)
        returns (uint256 profit, uint256 loss)
    {
        YieldBearingStorage storage s = _yieldBearingStorage();

        // Get current exchange rate and update it
        uint256 exchangeRate = _getCurrentExchangeRate();
        s.currentExchangeRate = exchangeRate;

        // Call parent implementation for actual reporting logic
        (profit, loss) = super.report();

        // If we have profit, update available yield
        if (profit > 0) {
            uint256 previousYield = s.availableYield;
            s.availableYield += profit;
            emit AvailableYieldUpdated(previousYield, s.availableYield);

            // Total token balance minus the yield balance
            uint256 totalTokenBalance = super._strategyStorage().asset.balanceOf(address(this));
            uint256 principalBalance = totalTokenBalance - s.availableYield;

            // update total eth value deposited with new exchange rate
            uint256 previousTotalEthValue = s.totalEthValueDeposited;
            s.totalEthValueDeposited = (principalBalance * exchangeRate) / 1e18;
            emit TotalEthValueUpdated(previousTotalEthValue, s.totalEthValueDeposited);
        }

        return (profit, loss);
    }

    /**
     * @inheritdoc ITokenizedStrategy
     * @dev Override withdraw to automatically report before withdrawal and update total ETH value.
     * This implementation:
     * 1. Calls report() to ensure the latest exchange rate and yield state
     * 2. Gets and stores the current exchange rate
     * 3. Calculates the ETH value being withdrawn based on assets and exchange rate
     * 4. Updates the total ETH value deposited after withdrawal
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public override(DragonTokenizedStrategy, ITokenizedStrategy) returns (uint256 shares) {
        YieldBearingStorage storage s = _yieldBearingStorage();

        ITokenizedStrategy(address(this)).report();

        // Get the current exchange rate
        uint256 exchangeRate = _getCurrentExchangeRate();
        s.currentExchangeRate = exchangeRate;

        // Calculate what portion of total ETH value this withdrawal represents
        uint256 ethValueWithdrawn = (assets * exchangeRate) / 1e18;

        // Perform the withdrawal with parent implementation
        shares = super.withdraw(assets, receiver, owner, maxLoss);

        uint256 previousTotalEthValue = s.totalEthValueDeposited;
        s.totalEthValueDeposited -= ethValueWithdrawn;
        emit TotalEthValueUpdated(previousTotalEthValue, s.totalEthValueDeposited);

        return shares;
    }

    /**
     * @inheritdoc IYieldBearingDragonTokenizedStrategy
     * @dev Returns the total ETH value of all deposits, excluding yield.
     * This represents the principal amount in ETH terms.
     */
    function totalEthValueDeposited() external view returns (uint256) {
        return _yieldBearingStorage().totalEthValueDeposited;
    }

    /**
     * @inheritdoc IYieldBearingDragonTokenizedStrategy
     * @dev Returns the total yield available for withdrawal in token units.
     * This represents profits from exchange rate appreciation.
     */
    function availableYield() external view returns (uint256) {
        return _yieldBearingStorage().availableYield;
    }

    /**
     * @dev Override _depositWithLockup to track the ETH value of deposits using exchange rates.
     * This implementation:
     * 1. Gets and stores the current exchange rate
     * 2. Calculates the ETH value of the deposit based on assets and exchange rate
     * 3. Updates the total ETH value tracking
     * 4. Calls the parent implementation for the actual deposit logic
     */
    function _depositWithLockup(
        uint256 assets,
        address receiver,
        uint256 lockupDuration
    ) internal override returns (uint256 shares) {
        YieldBearingStorage storage s = _yieldBearingStorage();

        // Get the current exchange rate before deposit
        uint256 exchangeRate = _getCurrentExchangeRate();
        s.currentExchangeRate = exchangeRate;

        // Calculate ETH value of this deposit
        uint256 depositEthValue = (assets * exchangeRate) / 1e18;

        // Add to the total ETH value
        uint256 previousTotalEthValue = s.totalEthValueDeposited;
        s.totalEthValueDeposited += depositEthValue;

        // Call the parent implementation for the actual deposit
        shares = super._depositWithLockup(assets, receiver, lockupDuration);

        emit TotalEthValueUpdated(previousTotalEthValue, s.totalEthValueDeposited);

        return shares;
    }

    /**
     * @dev Helper function to get the current exchange rate from the strategy.
     * Gets the exchange rate by calling getCurrentExchangeRate on the IMethYieldStrategy interface.
     * @return The current exchange rate between the yield-bearing token and ETH, scaled by 1e18
     */
    function _getCurrentExchangeRate() internal view returns (uint256) {
        // Get the exchange rate from the MethYieldStrategy
        // This requires casting address(this) to IMethYieldStrategy
        return IMethYieldStrategy(address(this)).getCurrentExchangeRate();
    }

    /**
     * @dev Returns the storage struct for yield bearing data from a dedicated storage slot.
     * Uses assembly to access a specific storage slot determined by YIELD_BEARING_STORAGE_POSITION
     * to prevent storage collisions in the proxy pattern.
     * @return s The YieldBearingStorage struct from the dedicated storage slot
     */
    function _yieldBearingStorage() private pure returns (YieldBearingStorage storage s) {
        bytes32 position = YIELD_BEARING_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
