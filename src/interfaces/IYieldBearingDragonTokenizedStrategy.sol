// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import { IDragonTokenizedStrategy } from "./IDragonTokenizedStrategy.sol";

/**
 * @title IYieldBearingDragonTokenizedStrategy
 * @notice Interface for accessing yield-bearing strategy specific functions
 */
interface IYieldBearingDragonTokenizedStrategy is IDragonTokenizedStrategy {
    struct YieldBearingStorage {
        /// @notice Total ETH value of all deposits (in wei)
        uint256 totalEthValueDeposited;
        /// @notice Total yield available for withdrawal (in mETH token units)
        uint256 availableYield;
        /// @notice Current exchange rate between the yield-bearing token and ETH
        uint256 currentExchangeRate;
    }

    /// @dev Events for tracking state changes
    event YieldWithdrawn(address indexed receiver, uint256 amount);
    event TotalEthValueUpdated(uint256 previousValue, uint256 newValue);
    event AvailableYieldUpdated(uint256 previousYield, uint256 newYield);

    // errors
    error InsufficientYieldAvailable();
    error CannotWithdrawToZeroAddress();

    /**
     * @notice Returns the total ETH value deposited (principal)
     * @return The total ETH value deposited, in wei
     */
    function totalEthValueDeposited() external view returns (uint256);

    /**
     * @notice Returns the total yield available for withdrawal (in mETH)
     * @return The total yield available, in mETH token units
     */
    function availableYield() external view returns (uint256);

    /**
     * @notice Withdraw available yield and send it to the specified receiver
     * @param amount Amount of yield to withdraw (in mETH token units)
     * @param receiver Address to receive the withdrawn yield
     * @param owner Address that owns the shares
     * @param maxLoss Maximum acceptable loss as BPS of assets withdrawn
     * @return The actual amount of yield withdrawn
     */
    function withdrawYield(uint256 amount, address receiver, address owner, uint256 maxLoss) external returns (uint256);

    /**
     * @notice Redeem available yield shares and send tokens to the specified receiver
     * @param amount Amount of shares to redeem
     * @param receiver Address to receive the withdrawn tokens
     * @param owner Address that owns the shares
     * @param maxLoss Maximum acceptable loss as BPS of assets withdrawn
     * @return The actual amount of assets received
     */
    function redeemYield(uint256 amount, address receiver, address owner, uint256 maxLoss) external returns (uint256);
}
