// SPDX-License-Identifier: UNLICENSED
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
        if (delegate == address(0)) revert InvalidDelegate();

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
    function emergencyRevokeAllowance(address delegate, address token) external {
        if (delegate == address(0)) revert InvalidDelegate();

        // Cache storage struct in memory to save gas
        LinearAllowance memory a = allowances[msg.sender][delegate][token];

        // Calculate the amount that would have been cleared (for event emission)
        // This includes both existing unspent amount and any newly accrued amount
        uint256 clearedAmount = 0;
        if (a.lastBookedAtInSeconds != 0) {
            uint256 timeElapsed = block.timestamp - a.lastBookedAtInSeconds;
            // Calculate total amount that would be available (existing + newly accrued)
            clearedAmount = a.totalUnspent + ((a.dripRatePerDay * timeElapsed) / 1 days);
        } else {
            // If never initialized, only clear existing unspent (should be 0)
            clearedAmount = a.totalUnspent;
        }

        // Emergency revocation: immediately zero drip rate and clear all unspent amounts
        // This provides true incident response capability for compromised delegates
        a.dripRatePerDay = 0;
        a.totalUnspent = 0;
        a.lastBookedAtInSeconds = block.timestamp.toUint32();
        // TODO: should we keep the totalSpent?

        // Write back to storage once
        allowances[msg.sender][delegate][token] = a;

        emit AllowanceEmergencyRevoked(msg.sender, delegate, token, clearedAmount);
    }

    /// @inheritdoc ILinearAllowanceSingleton
    /// @param safe The address of the safe which is the source of the allowance
    function executeAllowanceTransfer(
        address safe,
        address token,
        address payable to
    ) external nonReentrant returns (uint256) {
        if (to == address(0)) revert InvalidRecipient();

        // Cache storage in memory (single SLOAD)
        LinearAllowance memory a = allowances[safe][msg.sender][token];

        // Update cached memory values
        a = _updateAllowance(a);
        //slither-disable-next-line incorrect-equality
        if (a.totalUnspent == 0) revert NoAllowanceToTransfer(safe, msg.sender, token);

        // Calculate transfer amount based on available allowance and safe balance
        uint256 transferAmount = _calculateTransferAmount(safe, token, a);

        // Handle zero-amount transfers with specific error types
        _validateTransferAmount(transferAmount, a, safe, token);

        // Update bookkeeping and write to storage BEFORE external calls (effects)
        a.totalSpent += transferAmount;
        a.totalUnspent -= transferAmount;
        allowances[safe][msg.sender][token] = a;

        // Execute transfer and verify actual amount transferred
        uint256 actualTransferred = _executeAndVerifyTransfer(safe, token, to, transferAmount);

        // Handle non-compliant tokens and precision loss: verify actual transfer occurred
        if (actualTransferred == 0) {
            revert NoAmountToTransfer();
        }

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

    /// @notice Validate that the transfer amount is valid
    /// @param transferAmount The amount to transfer
    /// @param a The current allowance data
    /// @param safe The safe address (source of allowance)
    /// @param token The token address
    function _validateTransferAmount(
        uint256 transferAmount,
        LinearAllowance memory a,
        address safe,
        address token
    ) internal view {
        if (transferAmount == 0) {
            //slither-disable-next-line incorrect-equality
            if (a.totalUnspent == 0 && a.dripRatePerDay == 0) {
                // True no allowance case: no drip rate set
                revert NoAllowanceToTransfer(safe, msg.sender, token);
            } else {
                // Precision loss or insufficient balance case
                revert NoAmountToTransfer();
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

    /// @notice Execute transfer and verify the actual amount transferred
    /// @param safe The safe address
    /// @param token The token address
    /// @param to The recipient address
    /// @param transferAmount The amount to transfer
    /// @return actualTransferred The actual amount transferred
    function _executeAndVerifyTransfer(
        address safe,
        address token,
        address to,
        uint256 transferAmount
    ) internal returns (uint256 actualTransferred) {
        // Get balance before transfer
        uint256 balanceBefore = _getTokenBalance(safe, token);

        // Execute transfer via Safe
        bool success = _executeTransfer(safe, token, to, transferAmount);
        if (!success) {
            revert TransferFailed(safe, msg.sender, token);
        }

        // Get balance after transfer and calculate actual transferred amount
        uint256 balanceAfter = _getTokenBalance(safe, token);
        actualTransferred = balanceBefore - balanceAfter;
    }

    /// @notice Execute a transfer via the Safe module
    /// @param safe The safe address
    /// @param token The token address
    /// @param to The recipient address
    /// @param amount The amount to transfer
    /// @return success Whether the transfer was successful
    function _executeTransfer(address safe, address token, address to, uint256 amount) internal returns (bool success) {
        if (token == NATIVE_TOKEN) {
            // Execute ETH transfer via Safe
            success = ISafe(payable(safe)).execTransactionFromModule(to, amount, "", Enum.Operation.Call);
        } else {
            // Execute ERC20 transfer via Safe
            bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
            success = ISafe(payable(safe)).execTransactionFromModule(token, 0, data, Enum.Operation.Call);
        }
    }

    /// @inheritdoc ILinearAllowanceSingleton
    /// @param safe The address of the safe which is the source of the allowance
    function getTokenAllowanceData(
        address safe,
        address delegate,
        address token
    )
        public
        view
        returns (uint192 dripRatePerDay, uint256 totalUnspent, uint256 totalSpent, uint64 lastBookedAtInSeconds)
    {
        LinearAllowance memory allowance = allowances[safe][delegate][token];
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
