// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ILinearAllowanceSingleton
/// @author [Golem Foundation](https://golem.foundation)
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
    event AllowanceSet(address indexed source, address indexed delegate, address indexed token, uint192 dripRatePerDay);

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

    /// @notice Emitted when an allowance is revoked, clearing all accrued unspent amounts
    /// @param source The address of the source of the allowance
    /// @param delegate The delegate whose allowance was revoked
    /// @param token The token for which the allowance was revoked
    /// @param clearedAmount The amount of unspent allowance that was cleared
    event AllowanceRevoked(
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

    /// @notice Error thrown when a transfer is attempted with zero amount
    /// @param source The address of the source of the allowance
    /// @param delegate The delegate attempting the transfer
    /// @param token The token being transferred
    error ZeroTransfer(address source, address delegate, address token);

    /// @notice Error thrown when an argument is the zero address
    /// @param argumentName The name of the argument
    error AddressZeroForArgument(string argumentName);

    /// @notice Error thrown when array lengths do not match
    /// @param lengthOne The length of the first array
    /// @param lengthTwo The length of the second array
    /// @param lengthThree The length of the third array
    error ArrayLengthsMismatch(uint256 lengthOne, uint256 lengthTwo, uint256 lengthThree);

    /// @notice Error thrown when a Safe transaction execution fails
    error SafeTransactionFailed();

    /// @notice Set the allowance for a delegate. To revoke, set dripRatePerDay to 0. Revoking will not cancel any unspent allowance.
    /// @param delegate The delegate to set the allowance for
    /// @param token The token to set the allowance for. Use NATIVE_TOKEN for ETH
    /// @param dripRatePerDay The drip rate per day for the allowance
    function setAllowance(address delegate, address token, uint192 dripRatePerDay) external;

    /// @notice Set multiple allowances in a single transaction
    /// @param delegates Array of delegate addresses
    /// @param tokens Array of token addresses
    /// @param dripRatesPerDay Array of drip rates per day
    function setAllowances(
        address[] calldata delegates,
        address[] calldata tokens,
        uint192[] calldata dripRatesPerDay
    ) external;

    /// @notice Revocation that immediately zeros drip rate AND clears all accrued unspent allowance
    /// @dev This function provides immediate incident response capability for compromised delegates.
    /// Unlike setAllowance(delegate, token, 0) which preserves accrued amounts, this function
    /// completely revokes access by clearing both future accrual and existing unspent balances.
    /// @param delegate The delegate whose allowance should be revoked
    /// @param token The token for which to revoke the allowance. Use NATIVE_TOKEN for ETH
    function revokeAllowance(address delegate, address token) external;

    /// @notice Revoke multiple allowances in a single transaction
    /// @param delegates Array of delegate addresses
    /// @param tokens Array of token addresses
    function revokeAllowances(address[] calldata delegates, address[] calldata tokens) external;

    /// @notice Execute a transfer of the allowance
    /// @dev msg.sender is the delegate
    /// @param source The address of the source of the allowance
    /// @param token The address of the token. Use NATIVE_TOKEN for ETH
    /// @param to The address of the beneficiary
    /// @return The amount that was actually transferred
    function executeAllowanceTransfer(address source, address token, address payable to) external returns (uint256);

    /// @notice Execute a batch of transfers of the allowance
    /// @dev msg.sender is the delegate
    /// @param safes The addresses of the safes that are the source of the allowance
    /// @param tokens The addresses of the tokens to transfer
    /// @param tos The addresses of the beneficiaries
    function executeAllowanceTransfers(
        address[] calldata safes,
        address[] calldata tokens,
        address[] calldata tos
    ) external returns (uint256[] memory transferAmounts);

    /// @notice Get the total unspent allowance for a token as of now
    /// @param source The address of the source of the allowance
    /// @param delegate The address of the delegate
    /// @param token The address of the token
    /// @return The total unspent allowance as of now
    function getTotalUnspent(address source, address delegate, address token) external view returns (uint256);

    /// @notice Get the maximum withdrawable amount for a token, considering both allowance and Safe balance
    /// @param source The address of the source of the allowance (Safe)
    /// @param delegate The address of the delegate
    /// @param token The address of the token. Use NATIVE_TOKEN for ETH
    /// @return The maximum amount that can be withdrawn, which is min(allowance, Safe balance)
    function getMaxWithdrawableAmount(address source, address delegate, address token) external view returns (uint256);
}
