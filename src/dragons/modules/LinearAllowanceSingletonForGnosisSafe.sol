// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { NATIVE_TOKEN } from "../../constants.sol";
import { ILinearAllowanceSingletonForGnosisSafe } from "../../interfaces/ILinearAllowanceSingletonForGnosisSafe.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface ISafe {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success);
}

event AllowanceSet(address indexed safe, address indexed delegate, address indexed token, uint256 dripRatePerDay);
event AllowanceTransferred(
    address indexed safe,
    address indexed delegate,
    address indexed token,
    address to,
    uint256 amount
);

error NoAllowanceToTransfer(address safe, address delegate, address token);
error TransferFailed(address safe, address delegate, address token);

/// @title LinearAllowanceSingletonForGnosisSafe
/// @notice See ILinearAllowanceSingletonForGnosisSafe
contract LinearAllowanceSingletonForGnosisSafe is ILinearAllowanceSingletonForGnosisSafe, ReentrancyGuard {
    using SafeCast for uint256;
    using SafeCast for uint192;
    using SafeCast for uint160;
    using SafeCast for uint128;
    using SafeCast for uint32;

    // Packed struct to use storage slots efficiently
    struct LinearAllowance {
        uint128 dripRatePerDay; // Max value is 3.40e+38 approximately.
        uint160 totalUnspent; // Max value is 1.46e+48 approximately.
        uint192 totalSpent; // Max value is 6.27e+57 approximately
        uint32 lastBookedAtInSeconds; // Overflows in 2106.
    }

    mapping(address => mapping(address => mapping(address => LinearAllowance))) public allowances; // safe -> delegate -> token -> allowance

    function updateAllowance(LinearAllowance memory a) internal view returns (LinearAllowance memory) {
        if (a.lastBookedAtInSeconds != 0) {
            uint256 timeElapsed = block.timestamp - a.lastBookedAtInSeconds;
            uint256 daysElapsed = timeElapsed / 1 days;
            a.totalUnspent += (daysElapsed * a.dripRatePerDay).toUint160();
        }

        a.lastBookedAtInSeconds = block.timestamp.toUint32();
        return a;
    }

    /// @inheritdoc ILinearAllowanceSingletonForGnosisSafe
    function setAllowance(address delegate, address token, uint128 dripRatePerDay) external {
        // Cache storage struct in memory to save gas
        LinearAllowance memory a = allowances[msg.sender][delegate][token];

        // Update cached memory values
        a = updateAllowance(a);
        a.dripRatePerDay = dripRatePerDay;

        // Write back to storage once
        allowances[msg.sender][delegate][token] = a;

        emit AllowanceSet(msg.sender, delegate, token, dripRatePerDay);
    }

    /// @inheritdoc ILinearAllowanceSingletonForGnosisSafe
    function executeAllowanceTransfer(
        address safe,
        address token,
        address payable to
    ) external nonReentrant returns (uint256) {
        // Cache storage in memory (single SLOAD)
        LinearAllowance memory a = allowances[safe][msg.sender][token];

        // Update cached memory values
        a = updateAllowance(a);

        if (a.totalUnspent == 0) revert NoAllowanceToTransfer(safe, msg.sender, token);

        uint160 transferAmount;

        if (token == NATIVE_TOKEN) {
            // For ETH transfers, get the minimum of totalUnspent and safe balance
            uint256 safeBalance = address(safe).balance;
            transferAmount = a.totalUnspent <= safeBalance.toUint160() ? a.totalUnspent : safeBalance.toUint160();

            if (transferAmount > 0) {
                bool success = ISafe(payable(safe)).execTransactionFromModule(
                    to,
                    transferAmount,
                    "",
                    Enum.Operation.Call
                );
                if (!success) revert TransferFailed(safe, msg.sender, token);
            }
        } else {
            // For ERC20 transfers
            try IERC20(token).balanceOf(safe) returns (uint256 tokenBalance) {
                transferAmount = a.totalUnspent <= tokenBalance.toUint160() ? a.totalUnspent : tokenBalance.toUint160();

                if (transferAmount > 0) {
                    bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, transferAmount);
                    bool success = ISafe(payable(safe)).execTransactionFromModule(token, 0, data, Enum.Operation.Call);
                    if (!success) revert TransferFailed(safe, msg.sender, token);
                }
            } catch {
                revert TransferFailed(safe, msg.sender, token);
            }
        }

        // Update bookkeeping in memory
        a.totalSpent += transferAmount;
        a.totalUnspent -= transferAmount;

        // Write back to storage once
        allowances[safe][msg.sender][token] = a;

        emit AllowanceTransferred(safe, msg.sender, token, to, transferAmount);

        return transferAmount;
    }

    /// @inheritdoc ILinearAllowanceSingletonForGnosisSafe
    function getTokenAllowanceData(
        address safe,
        address delegate,
        address token
    )
        public
        view
        returns (uint128 dripRatePerDay, uint160 totalUnspent, uint192 totalSpent, uint32 lastBookedAtInSeconds)
    {
        LinearAllowance memory allowance = allowances[safe][delegate][token];
        return (
            allowance.dripRatePerDay,
            allowance.totalUnspent,
            allowance.totalSpent,
            allowance.lastBookedAtInSeconds
        );
    }

    /// @inheritdoc ILinearAllowanceSingletonForGnosisSafe
    function getTotalUnspent(address safe, address delegate, address token) public view returns (uint256) {
        // Cache the storage value in memory (single SLOAD)
        LinearAllowance memory allowance = allowances[safe][delegate][token];

        // Handle uninitialized allowance (lastBookedAtInSeconds == 0)
        if (allowance.lastBookedAtInSeconds == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - allowance.lastBookedAtInSeconds;
        uint256 daysElapsed = timeElapsed / 1 days;

        return allowance.totalUnspent + allowance.dripRatePerDay * daysElapsed;
    }
}
