// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title ILinearAllowanceSingleton
/// @notice Interface for a module that allows to delegate spending allowances with linear accrual
interface ILinearAllowanceSingleton {
    /// @notice Structure defining an allowance with linear accrual
    struct LinearAllowance {
        uint192 dripRatePerDay;
        uint64 lastBookedAtInSeconds;
        uint256 totalUnspent;
        uint256 totalSpent;
    }

    /// @notice Emitted when an allowance is set for a delegate
    /// @param source The address of the source of the allowance
    /// @param delegate The delegate the allowance is set for
    /// @param token The token the allowance is set for
    /// @param dripRatePerDay The drip rate per day for the allowance
    event AllowanceSet(address indexed source, address indexed delegate, address indexed token, uint256 dripRatePerDay);

    /// @notice Emitted when an allowance transfer is executed
    /// @param source The address of the source of the allowance
    /// @param delegate The delegate who executed the transfer
    /// @param token The token that was transferred
    /// @param to The recipient of the transfer
    /// @param amount The amount that was transferred
    event AllowanceTransferred(
        address indexed source,
        address indexed delegate,
        address indexed token,
        address to,
        uint256 amount
    );

    /// @notice Emitted when an allowance is emergency revoked, clearing all accrued unspent amounts
    /// @param source The address of the source of the allowance
    /// @param delegate The delegate whose allowance was revoked
    /// @param token The token for which the allowance was revoked
    /// @param clearedAmount The amount of unspent allowance that was cleared
    event AllowanceEmergencyRevoked(
        address indexed source,
        address indexed delegate,
        address indexed token,
        uint256 clearedAmount
    );

    /// @notice Error thrown when trying to transfer with no available allowance
    /// @param source The address of the source of the allowance
    /// @param delegate The delegate attempting the transfer
    /// @param token The token being transferred
    error NoAllowanceToTransfer(address source, address delegate, address token);

    /// @notice Error thrown when a transfer fails
    /// @param source The address of the source of the allowance
    /// @param delegate The delegate attempting the transfer
    /// @param token The token being transferred
    error TransferFailed(address source, address delegate, address token);

    /// @notice Error thrown when trying to set allowance for zero address delegate
    error InvalidDelegate();

    /// @notice Error thrown when trying to transfer to zero address
    error InvalidRecipient();

    /// @notice Error thrown when trying to transfer zero amount
    error NoAmountToTransfer();

    /// @notice Set the allowance for a delegate. To revoke, set dripRatePerDay to 0. Revoking will not cancel any unspent allowance.
    /// @param delegate The delegate to set the allowance for
    /// @param token The token to set the allowance for. Use NATIVE_TOKEN for ETH
    /// @param dripRatePerDay The drip rate per day for the allowance
    function setAllowance(address delegate, address token, uint192 dripRatePerDay) external;

    /// @notice Emergency revocation that immediately zeros drip rate AND clears all accrued unspent allowance
    /// @dev This function provides immediate incident response capability for compromised delegates.
    /// Unlike setAllowance(delegate, token, 0) which preserves accrued amounts, this function
    /// completely revokes access by clearing both future accrual and existing unspent balances.
    /// @param delegate The delegate whose allowance should be emergency revoked
    /// @param token The token for which to revoke the allowance. Use NATIVE_TOKEN for ETH
    function emergencyRevokeAllowance(address delegate, address token) external;

    /// @notice Execute a transfer of the allowance
    /// @dev msg.sender is the delegate
    /// @param source The address of the source of the allowance
    /// @param token The address of the token. Use NATIVE_TOKEN for ETH
    /// @param to The address of the beneficiary
    /// @return The amount that was actually transferred
    function executeAllowanceTransfer(address source, address token, address payable to) external returns (uint256);

    /// @notice Get the allowance data for a token
    /// @param source The address of the source of the allowance
    /// @param delegate The address of the delegate
    /// @param token The address of the token
    /// @return dripRatePerDay The drip rate per day
    /// @return totalUnspent The total unspent allowance
    /// @return totalSpent The total spent allowance
    /// @return lastBookedAtInSeconds The last booked timestamp in seconds
    function getTokenAllowanceData(
        address source,
        address delegate,
        address token
    )
        external
        view
        returns (uint192 dripRatePerDay, uint256 totalUnspent, uint256 totalSpent, uint64 lastBookedAtInSeconds);

    /// @notice Get the total unspent allowance for a token as of now
    /// @param source The address of the source of the allowance
    /// @param delegate The address of the delegate
    /// @param token The address of the token
    /// @return The total unspent allowance as of now
    function getTotalUnspent(address source, address delegate, address token) external view returns (uint256);
}
