// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { NATIVE_TOKEN } from "src/constants.sol";
import { ILinearAllowanceSingleton } from "src/zodiac-core/interfaces/ILinearAllowanceSingleton.sol";
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
/// @author [Golem Foundation](https://golem.foundation)
/// @notice See ILinearAllowanceSingletonForGnosisSafe
contract LinearAllowanceSingletonForGnosisSafe is ILinearAllowanceSingleton, ReentrancyGuard {
    using SafeCast for uint256;

    mapping(address => mapping(address => mapping(address => LinearAllowance))) public allowances; // safe -> delegate -> token -> allowance

    /// @inheritdoc ILinearAllowanceSingleton
    function setAllowance(address delegate, address token, uint192 dripRatePerDay) external nonReentrant {
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
    ) external nonReentrant {
        uint256 length = delegates.length;
        require(
            length == tokens.length && length == dripRatesPerDay.length,
            ArrayLengthsMismatch(length, tokens.length, dripRatesPerDay.length)
        );

        for (uint256 i = 0; i < length; i++) {
            _setAllowance(msg.sender, delegates[i], tokens[i], dripRatesPerDay[i]);
        }
    }

    /// @inheritdoc ILinearAllowanceSingleton
    function revokeAllowance(address delegate, address token) external nonReentrant {
        _revokeAllowance(msg.sender, delegate, token);
    }

    /// @inheritdoc ILinearAllowanceSingleton
    function revokeAllowances(address[] calldata delegates, address[] calldata tokens) external nonReentrant {
        uint256 length = delegates.length;
        require(length == tokens.length, ArrayLengthsMismatch(delegates.length, tokens.length, 0));

        for (uint256 i = 0; i < length; i++) {
            _revokeAllowance(msg.sender, delegates[i], tokens[i]);
        }
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
        require(
            length == tokens.length && length == tos.length,
            ArrayLengthsMismatch(length, tokens.length, tos.length)
        );

        transferAmounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            transferAmounts[i] = _executeAllowanceTransfer(safes[i], msg.sender, tokens[i], payable(tos[i]));
        }

        return transferAmounts;
    }

    /// @inheritdoc ILinearAllowanceSingleton
    /// @param safe The address of the safe which is the source of the allowance
    function getTotalUnspent(address safe, address delegate, address token) public view returns (uint256) {
        LinearAllowance memory allowance = allowances[safe][delegate][token];
        uint256 newAccrued = _calculateNewAccrued(allowance);
        return allowance.totalUnspent + newAccrued;
    }

    /// @notice Get the token balance of a safe
    /// @param account The account address
    /// @param token The token address (use NATIVE_TOKEN for ETH)
    /// @return balance The token balance
    function getBalance(address account, address token) public view returns (uint256 balance) {
        if (token == NATIVE_TOKEN) {
            balance = address(account).balance;
        } else {
            balance = IERC20(token).balanceOf(account);
        }
    }

    /// @inheritdoc ILinearAllowanceSingleton
    /// @param safe The address of the safe which is the source of the allowance
    function getMaxWithdrawableAmount(address safe, address delegate, address token) public view returns (uint256) {
        uint256 totalUnspent = getTotalUnspent(safe, delegate, token);
        if (totalUnspent == 0) return 0;

        uint256 safeBalance = getBalance(safe, token);

        return totalUnspent <= safeBalance ? totalUnspent : safeBalance;
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

        a = _calculateCurrentAllowance(a);
        a = _updateDripRatePerDay(a, dripRatePerDay);

        allowances[safe][delegate][token] = a;

        emit AllowanceSet(safe, delegate, token, dripRatePerDay);
    }

    /// @notice Internal function to revoke a single allowance
    /// @param safe The safe address that is revoking the allowance
    /// @param delegate The delegate address whose allowance is being revoked
    /// @param token The token address for the allowance
    function _revokeAllowance(address safe, address delegate, address token) internal {
        if (delegate == address(0)) revert AddressZeroForArgument("delegate");

        LinearAllowance memory allowance = allowances[safe][delegate][token];
        allowance = _calculateCurrentAllowance(allowance);

        emit AllowanceRevoked(safe, delegate, token, allowance.totalUnspent);

        allowance = _updateDripRatePerDay(allowance, 0);
        allowance.totalUnspent = 0;

        allowances[safe][delegate][token] = allowance;
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

        // Calculate current allowance values
        a = _calculateCurrentAllowance(a);
        if (a.totalUnspent == 0) revert NoAllowanceToTransfer(safe, delegate, token);

        // Calculate transfer amount based on available allowance and safe balance
        transferAmount = getMaxWithdrawableAmount(safe, delegate, token);
        if (transferAmount == 0) revert ZeroTransfer(safe, delegate, token);

        // Update bookkeeping and write to storage BEFORE external calls (effects)
        a.totalSpent += transferAmount;
        a.totalUnspent -= transferAmount;
        allowances[safe][delegate][token] = a;

        emit AllowanceTransferred(safe, delegate, token, to, transferAmount);

        _executeTransfer(safe, delegate, token, to, transferAmount);

        return transferAmount;
    }

    /// @notice Execute a transfer from the safe to the recipient
    /// @dev Uses beneficiary balance to check if the transfer was successful; fee-charging tokens are not supported.
    /// @param safe The safe address executing the transfer
    /// @param delegate The delegate executing the transfer (for error reporting)
    /// @param token The token address to transfer
    /// @param to The recipient address
    /// @param amount The amount to transfer
    function _executeTransfer(address safe, address delegate, address token, address to, uint256 amount) internal {
        uint256 beneficiaryPreBalance = getBalance(to, token);

        bool success;
        if (token == NATIVE_TOKEN) {
            success = ISafe(payable(safe)).execTransactionFromModule(to, amount, "", Enum.Operation.Call);
        } else {
            bytes memory data = abi.encodeCall(IERC20.transfer, (to, amount));
            success = ISafe(payable(safe)).execTransactionFromModule(token, 0, data, Enum.Operation.Call);
        }

        // Explicit success check for defense-in-depth
        if (!success) revert SafeTransactionFailed();

        // Maintain existing balance verification as primary security control
        uint256 beneficiaryPostBalance = getBalance(to, token);
        require(beneficiaryPostBalance - beneficiaryPreBalance >= amount, TransferFailed(safe, delegate, token));
    }

    function _updateDripRatePerDay(
        LinearAllowance memory a,
        uint192 dripRatePerDay
    ) internal view returns (LinearAllowance memory) {
        a.dripRatePerDay = dripRatePerDay;
        a.lastBookedAtInSeconds = block.timestamp.toUint64();
        return a;
    }

    function _calculateCurrentAllowance(LinearAllowance memory a) internal view returns (LinearAllowance memory) {
        uint256 newAccrued = _calculateNewAccrued(a);

        if (newAccrued > 0) {
            a.totalUnspent += newAccrued;
            a.lastBookedAtInSeconds = block.timestamp.toUint64();
        }

        return a;
    }

    function _calculateNewAccrued(LinearAllowance memory allowance) internal view returns (uint256) {
        if (allowance.lastBookedAtInSeconds == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - allowance.lastBookedAtInSeconds;
        uint256 newAccrued = (timeElapsed * allowance.dripRatePerDay) / 1 days;

        return newAccrued;
    }
}
