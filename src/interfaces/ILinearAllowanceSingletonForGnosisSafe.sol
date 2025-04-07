// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title ILinearAllowanceSingletonForGnosisSafe
/// @notice Interface for a module that allows a delegate to transfer allowances from a safe to a recipient.
interface ILinearAllowanceSingletonForGnosisSafe {
    /// @notice Set the allowance for a delegate. To revoke, set dripRatePerDay to 0. Revoking will not cancel any unspent allowance.
    /// @param delegate The delegate to set the allowance for.
    /// @param token The token to set the allowance for. 0x0 is ETH.
    /// @param dripRatePerDay The drip rate per day for the allowance.
    function setAllowance(address delegate, address token, uint128 dripRatePerDay) external;

    /// @notice Execute a transfer of the allowance.
    /// @dev msg.sender is the delegate.
    /// @param safe The address of the safe.
    /// @param token The address of the token.
    /// @param to The address of the beneficiary.
    /// @return amount The amount that was actually transferred
    function executeAllowanceTransfer(address safe, address token, address payable to) external returns (uint256);

    /// @notice Get the allowance data for a token.
    /// @param safe The address of the safe.
    /// @param delegate The address of the delegate.
    /// @param token The address of the token.
    /// @return dripRatePerDay The drip rate per day.
    /// @return totalUnspent The total unspent allowance.
    /// @return totalSpent The total spent allowance.
    /// @return lastBookedAtInSeconds The last booked at timestamp in seconds.
    function getTokenAllowanceData(
        address safe,
        address delegate,
        address token
    )
        external
        view
        returns (uint128 dripRatePerDay, uint160 totalUnspent, uint192 totalSpent, uint32 lastBookedAtInSeconds);

    /// @notice Get the total unspent allowance for a token.
    /// @param safe The address of the safe.
    /// @param delegate The address of the delegate.
    /// @param token The address of the token.
    /// @return totalAllowanceAsOfNow The total unspent allowance as of now.
    function getTotalUnspent(address safe, address delegate, address token) external view returns (uint256);
}
