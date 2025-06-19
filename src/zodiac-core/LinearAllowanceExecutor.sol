// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LinearAllowanceSingletonForGnosisSafe } from "src/zodiac-core/modules/LinearAllowanceSingletonForGnosisSafe.sol";

/// @title LinearAllowanceExecutor
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Abstract base contract for executing linear allowance transfers from Gnosis Safe modules
/// @dev This contract provides the core functionality for interacting with LinearAllowanceSingletonForGnosisSafe
/// while leaving withdrawal mechanisms to be implemented by derived contracts. The contract can receive
/// both ETH and ERC20 tokens from allowance transfers, but the specific withdrawal logic must be defined
/// by inheriting contracts to ensure proper access control and business logic implementation.
abstract contract LinearAllowanceExecutor {
    /// @notice Enables the contract to receive ETH transfers from allowance executions
    /// @dev Required for ETH allowance transfers to succeed when this contract is the recipient
    receive() external payable virtual;

    /// @notice Execute a transfer of the allowance from a Safe to this contract
    /// @dev This function calls the allowance module to transfer available allowance to this contract.
    /// The transferred funds remain in this contract until withdrawn via the withdraw function.
    /// @param allowanceModule The allowance module contract to interact with
    /// @param safe The address of the Safe that holds the allowance funds
    /// @param token The address of the token to transfer (use NATIVE_TOKEN for ETH)
    /// @return transferredAmount The actual amount that was transferred to this contract
    function executeAllowanceTransfer(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address safe,
        address token
    ) external returns (uint256) {
        // Execute the allowance transfer, sending funds to this contract
        return allowanceModule.executeAllowanceTransfer(safe, token, payable(address(this)));
    }

    /// @notice Execute a batch of allowance transfers from multiple Safes to this contract
    /// @dev All transfers are sent to this contract (address(this)) for security purposes.
    /// This prevents parameter injection attacks that could redirect funds to arbitrary addresses.
    /// @param allowanceModule The allowance module contract to interact with
    /// @param safes Array of Safe addresses that are the source of the allowances
    /// @param tokens Array of token addresses to transfer (use NATIVE_TOKEN for ETH)
    /// @return transferAmounts Array of amounts transferred for each operation
    function executeAllowanceTransfers(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address[] calldata safes,
        address[] calldata tokens
    ) external returns (uint256[] memory transferAmounts) {
        address[] memory tos = new address[](safes.length);
        for (uint256 i = 0; i < safes.length; i++) {
            tos[i] = address(this);
        }
        return allowanceModule.executeAllowanceTransfers(safes, tokens, tos);
    }

    /// @notice Get the total unspent allowance for a token
    /// @param allowanceModule The allowance module to use
    /// @param safe The address of the safe
    /// @param token The address of the token
    /// @return totalAllowanceAsOfNow The total unspent allowance as of now
    function getTotalUnspent(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address safe,
        address token
    ) external view returns (uint256) {
        // Query the allowance module for this contract's unspent allowance
        return allowanceModule.getTotalUnspent(safe, address(this), token);
    }

    /// @notice Withdraw accumulated funds from this contract
    /// @dev This function must be implemented by derived contracts to define withdrawal logic.
    /// Implementations should include proper access control, destination validation, and any
    /// business logic specific to the use case. Consider implementing emergency withdrawal
    /// mechanisms and multi-signature requirements for high-value operations.
    /// @param token The address of the token to withdraw (use NATIVE_TOKEN for ETH)
    /// @param amount The amount to withdraw from this contract's balance
    /// @param to The destination address to send the withdrawn funds
    function withdraw(address token, uint256 amount, address payable to) external virtual;

    /// @notice Get the maximum withdrawable amount for a token, considering both allowance and Safe balance
    /// @param allowanceModule The allowance module to use
    /// @param safe The address of the safe
    /// @param token The address of the token
    /// @return maxWithdrawableAmount The maximum amount that can be withdrawn
    function getMaxWithdrawableAmount(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address safe,
        address token
    ) external view returns (uint256) {
        return allowanceModule.getMaxWithdrawableAmount(safe, address(this), token);
    }
}
