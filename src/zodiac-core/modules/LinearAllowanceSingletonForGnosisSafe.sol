// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Enum } from "lib/safe-smart-account/contracts/libraries/Enum.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { NATIVE_TOKEN } from "../../constants.sol";
import { ILinearAllowanceSingleton } from "../interfaces/ILinearAllowanceSingleton.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface ISafe {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success);
}

/// @title LinearAllowanceSingletonForGnosisSafe
/// @notice See ILinearAllowanceSingletonForGnosisSafe
contract LinearAllowanceSingletonForGnosisSafe is ILinearAllowanceSingleton, ReentrancyGuard {
    using SafeCast for uint256;
    using SafeCast for uint160;
    using SafeCast for uint32;
    using SafeCast for uint64;

    mapping(address => mapping(address => mapping(address => LinearAllowance))) public allowances; // safe -> delegate -> token -> allowance

    /// @inheritdoc ILinearAllowanceSingleton
    function setAllowance(address delegate, address token, uint192 dripRatePerDay) external {
        _setAllowance(msg.sender, delegate, token, dripRatePerDay);
    }

    /// @notice Set multiple allowances in a single transaction
    /// @param delegates Array of delegate addresses
    /// @param tokens Array of token addresses
    /// @param dripRatesPerDay Array of drip rates per day
    function setAllowances(
        address[] calldata delegates,
        address[] calldata tokens,
        uint192[] calldata dripRatesPerDay
    ) external {
        uint256 length = delegates.length;
        if (length != tokens.length || length != dripRatesPerDay.length) {
            revert("Array lengths must match");
        }

        for (uint256 i = 0; i < length; i++) {
            _setAllowance(msg.sender, delegates[i], tokens[i], dripRatesPerDay[i]);
        }
    }

    /// @inheritdoc ILinearAllowanceSingleton
    function emergencyRevokeAllowance(address delegate, address token) external nonReentrant {
        if (delegate == address(0)) revert AddressZeroForArgument("delegate");

        LinearAllowance memory allowance = allowances[msg.sender][delegate][token];
        allowance = _updateAllowance(allowance);

        emit AllowanceEmergencyRevoked(msg.sender, delegate, token, allowance.totalUnspent);

        allowance.dripRatePerDay = 0;
        allowance.totalUnspent = 0;

        allowances[msg.sender][delegate][token] = allowance;
    }

    /// @inheritdoc ILinearAllowanceSingleton
    /// @param safe The address of the safe which is the source of the allowance
    function executeAllowanceTransfer(
        address safe,
        address token,
        address payable to
    ) external nonReentrant returns (uint256) {
        return _executeAllowanceTransfer(safe, msg.sender, token, to);
    }

    /// @notice Execute multiple allowance transfers in a single transaction
    /// @param safes Array of safe addresses that are the source of allowances
    /// @param tokens Array of token addresses to transfer
    /// @param tos Array of recipient addresses
    /// @return transferAmounts Array of amounts transferred for each operation
    function executeAllowanceTransfers(
        address[] calldata safes,
        address[] calldata tokens,
        address[] calldata tos
    ) external nonReentrant returns (uint256[] memory transferAmounts) {
        uint256 length = safes.length;
        if (length != tokens.length || length != tos.length) {
            revert("Array lengths must match");
        }

        transferAmounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            transferAmounts[i] = _executeAllowanceTransfer(safes[i], msg.sender, tokens[i], payable(tos[i]));
        }

        return transferAmounts;
    }

    /// @inheritdoc ILinearAllowanceSingleton
    function getTokenAllowanceData(
        address source,
        address delegate,
        address token
    )
        external
        view
        returns (uint192 dripRatePerDay, uint256 totalUnspent, uint256 totalSpent, uint64 lastBookedAtInSeconds)
    {
        LinearAllowance memory allowance = allowances[source][delegate][token];
        return (
            allowance.dripRatePerDay,
            allowance.totalUnspent,
            allowance.totalSpent,
            allowance.lastBookedAtInSeconds
        );
    }

    /// @inheritdoc ILinearAllowanceSingleton
    /// @param safe The address of the safe which is the source of the allowance
    function getTotalUnspent(address safe, address delegate, address token) public view returns (uint256) {
        // Cache the storage value in memory (single SLOAD)
        LinearAllowance memory allowance = allowances[safe][delegate][token];

        // Handle uninitialized allowance (lastBookedAtInSeconds == 0)
        if (allowance.lastBookedAtInSeconds == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - allowance.lastBookedAtInSeconds;

        return allowance.totalUnspent + ((allowance.dripRatePerDay * timeElapsed) / 1 days);
    }

    /// @inheritdoc ILinearAllowanceSingleton
    /// @param safe The address of the safe which is the source of the allowance
    function getMaxWithdrawableAmount(address safe, address delegate, address token) public view returns (uint256) {
        // Get current total unspent allowance
        uint256 totalUnspent = getTotalUnspent(safe, delegate, token);

        // If no allowance, return 0
        if (totalUnspent == 0) return 0;

        if (token == NATIVE_TOKEN) {
            // For ETH transfers, get the minimum of totalUnspent and safe balance
            uint256 safeBalance = address(safe).balance;
            return totalUnspent <= safeBalance ? totalUnspent : safeBalance;
        } else {
            // For ERC20 transfers
            try IERC20(token).balanceOf(safe) returns (uint256 tokenBalance) {
                return totalUnspent <= tokenBalance ? totalUnspent : tokenBalance;
            } catch {
                // If balance call fails, return 0 to indicate no withdrawal possible
                return 0;
            }
        }
    }

    /// @notice Get the token balance of a safe
    /// @param safe The safe address
    /// @param token The token address (use NATIVE_TOKEN for ETH)
    /// @return balance The token balance
    function _getTokenBalance(address safe, address token) internal view returns (uint256 balance) {
        if (token == NATIVE_TOKEN) {
            balance = address(safe).balance;
        } else {
            balance = IERC20(token).balanceOf(safe);
        }
    }

    /// @notice Execute a transfer from the safe to the recipient
    /// @param safe The safe address executing the transfer
    /// @param delegate The delegate executing the transfer (for error reporting)
    /// @param token The token address to transfer
    /// @param to The recipient address
    /// @param amount The amount to transfer
    function _executeTransfer(address safe, address delegate, address token, address to, uint256 amount) internal {
        bool success;
        if (token == NATIVE_TOKEN) {
            success = ISafe(payable(safe)).execTransactionFromModule(to, amount, "", Enum.Operation.Call);
        } else {
            bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
            success = ISafe(payable(safe)).execTransactionFromModule(token, 0, data, Enum.Operation.Call);
        }

        if (!success) {
            revert TransferFailed(safe, delegate, token);
        }
    }

    /// @notice Calculate the transfer amount based on allowance and safe balance
    /// @param safe The safe address
    /// @param token The token address
    /// @param a The current allowance data
    /// @return transferAmount The amount to transfer
    function _calculateTransferAmount(
        address safe,
        address token,
        LinearAllowance memory a
    ) internal view returns (uint256 transferAmount) {
        uint256 safeBalance = _getTokenBalance(safe, token);
        transferAmount = a.totalUnspent <= safeBalance ? a.totalUnspent : safeBalance;
    }

    /// @notice Internal function to set a single allowance
    /// @param safe The safe address that is setting the allowance
    /// @param delegate The delegate address receiving the allowance
    /// @param token The token address for the allowance
    /// @param dripRatePerDay The drip rate per day for the allowance
    function _setAllowance(address safe, address delegate, address token, uint192 dripRatePerDay) internal {
        // Cache storage struct in memory to save gas
        if (delegate == address(0)) revert AddressZeroForArgument("delegate");
        LinearAllowance memory a = allowances[safe][delegate][token];

        // Update cached memory values
        a = _updateAllowance(a);
        a.dripRatePerDay = dripRatePerDay;

        // Write back to storage once
        allowances[safe][delegate][token] = a;

        emit AllowanceSet(safe, delegate, token, dripRatePerDay);
    }

    /// @notice Internal function to execute a single allowance transfer
    /// @param safe The safe address that is the source of the allowance
    /// @param delegate The delegate address executing the transfer
    /// @param token The token address to transfer
    /// @param to The recipient address
    /// @return transferAmount The amount transferred
    function _executeAllowanceTransfer(
        address safe,
        address delegate,
        address token,
        address payable to
    ) internal returns (uint256 transferAmount) {
        if (safe == address(0)) revert AddressZeroForArgument("safe");
        if (to == address(0)) revert AddressZeroForArgument("to");

        // Cache storage in memory (single SLOAD)
        LinearAllowance memory a = allowances[safe][delegate][token];

        // Update cached memory values
        a = _updateAllowance(a);
        if (a.totalUnspent == 0) revert NoAllowanceToTransfer(safe, delegate, token);

        // Calculate transfer amount based on available allowance and safe balance
        transferAmount = _calculateTransferAmount(safe, token, a);
        if (transferAmount == 0) revert ZeroTransfer(safe, delegate, token);

        // Update bookkeeping and write to storage BEFORE external calls (effects)
        a.totalSpent += transferAmount;
        a.totalUnspent -= transferAmount;
        allowances[safe][delegate][token] = a;

        // Execute the transfer
        _executeTransfer(safe, delegate, token, to, transferAmount);

        emit AllowanceTransferred(safe, delegate, token, to, transferAmount);

        return transferAmount;
    }

    function _updateAllowance(LinearAllowance memory a) internal view returns (LinearAllowance memory) {
        if (a.lastBookedAtInSeconds != 0) {
            uint256 timeElapsed = block.timestamp - a.lastBookedAtInSeconds;
            //slither-disable-next-line incorrect-equality
            a.totalUnspent += (timeElapsed * a.dripRatePerDay) / 1 days;
        }

        a.lastBookedAtInSeconds = block.timestamp.toUint64();
        return a;
    }
}
