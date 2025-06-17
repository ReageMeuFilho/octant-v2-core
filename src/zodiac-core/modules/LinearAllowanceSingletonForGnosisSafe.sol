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
    function setAllowance(address delegate, address token, uint192 dripRatePerDay) external nonReentrant {
        if (delegate == address(0)) revert AddressZeroForArgument("delegate");

        // Cache storage struct in memory to save gas
        LinearAllowance memory a = allowances[msg.sender][delegate][token];

        // Update cached memory values
        a = _updateAllowance(a);
        a.dripRatePerDay = dripRatePerDay;

        // Write back to storage once
        allowances[msg.sender][delegate][token] = a;

        emit AllowanceSet(msg.sender, delegate, token, dripRatePerDay);
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
        if (safe == address(0)) revert AddressZeroForArgument("safe");
        if (to == address(0)) revert AddressZeroForArgument("to");

        // Cache storage in memory (single SLOAD)
        LinearAllowance memory a = allowances[safe][msg.sender][token];

        // Update cached memory values
        a = _updateAllowance(a);
        if (a.totalUnspent == 0) revert NoAllowanceToTransfer(safe, msg.sender, token);

        // Calculate transfer amount based on available allowance and safe balance
        uint256 transferAmount = _calculateTransferAmount(safe, token, a);
        if (transferAmount == 0) revert ZeroTransfer(safe, msg.sender, token);

        // Update bookkeeping and write to storage BEFORE external calls (effects)
        a.totalSpent += transferAmount;
        a.totalUnspent -= transferAmount;
        allowances[safe][msg.sender][token] = a;

        _executeTransfer(safe, token, to, transferAmount);

        emit AllowanceTransferred(safe, msg.sender, token, to, transferAmount);

        return transferAmount;
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

    function _executeTransfer(address safe, address token, address to, uint256 amount) internal {
        uint256 balanceBefore = _getTokenBalance(to, token);

        bool success;
        if (token == NATIVE_TOKEN) {
            success = ISafe(payable(safe)).execTransactionFromModule(to, amount, "", Enum.Operation.Call);
        } else {
            bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
            success = ISafe(payable(safe)).execTransactionFromModule(token, 0, data, Enum.Operation.Call);
        }

        if (!success) {
            revert TransferFailed(safe, msg.sender, token);
        }

        uint256 balanceAfter = _getTokenBalance(to, token);
        if (balanceAfter <= balanceBefore) {
            revert TransferFailed(safe, msg.sender, token);
        }
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
