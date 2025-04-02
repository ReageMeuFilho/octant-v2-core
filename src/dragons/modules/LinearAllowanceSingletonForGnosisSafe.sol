// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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

/// @title LinearAllowance
/// @notice A module that allows a delegate to transfer allowances from a safe to a recipient.
contract LinearAllowanceSingletonForGnosisSafe is ReentrancyGuard {
    struct LinearAllowance {
        uint256 dripRatePerDay;
        uint256 totalUnspent;
        uint256 totalSpent;
        uint256 lastBookedAt; // 0 is a special case for uninitialized allowance
    }

    mapping(address => mapping(address => mapping(address => LinearAllowance))) public allowances; // safe -> delegate -> token -> allowance

    function updateAllowance(LinearAllowance storage a) internal {
        if (a.lastBookedAt != 0) {
            uint256 timeElapsed = block.timestamp - a.lastBookedAt;
            uint256 daysElapsed = timeElapsed / 1 days;
            a.totalUnspent += daysElapsed * a.dripRatePerDay;
            a.lastBookedAt = block.timestamp;
        } else {
            // Special case for uninitialized allowance
            a.lastBookedAt = block.timestamp;
        }
    }

    /// @notice Set the allowance for a delegate. To revoke, set dripRatePerDay to 0. Revoking will not cancel any unspent allowance.
    /// @param delegate The delegate to set the allowance for.
    /// @param token The token to set the allowance for. 0x0 is ETH.
    /// @param dripRatePerDay The drip rate per day for the allowance.
    function setAllowance(address delegate, address token, uint256 dripRatePerDay) external {
        LinearAllowance storage a = allowances[msg.sender][delegate][token];
        updateAllowance(a);
        a.dripRatePerDay = dripRatePerDay;
        emit AllowanceSet(msg.sender, delegate, token, dripRatePerDay);
    }

    /// @notice Execute a transfer of the allowance.
    /// @dev msg.sender is the delegate.
    /// @param safe The address of the safe.
    /// @param token The address of the token.
    /// @param to The address of the beneficiary.
    /// @return amount The amount that was actually transferred
    function executeAllowanceTransfer(
        address safe,
        address token,
        address payable to
    ) external nonReentrant returns (uint256) {
        LinearAllowance storage a = allowances[safe][msg.sender][token];
        updateAllowance(a);

        require(a.totalUnspent > 0, NoAllowanceToTransfer(safe, msg.sender, token));

        uint256 transferAmount;

        if (token == address(0)) {
            // For ETH transfers, get the minimum of totalUnspent and safe balance
            transferAmount = a.totalUnspent <= address(safe).balance ? a.totalUnspent : address(safe).balance;

            if (transferAmount > 0) {
                require(
                    ISafe(payable(safe)).execTransactionFromModule(to, transferAmount, "", Enum.Operation.Call),
                    TransferFailed(safe, msg.sender, token)
                );
            }
        } else {
            // For ERC20 transfers
            try IERC20(token).balanceOf(safe) returns (uint256 tokenBalance) {
                transferAmount = a.totalUnspent <= tokenBalance ? a.totalUnspent : tokenBalance;

                if (transferAmount > 0) {
                    bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, transferAmount);
                    require(
                        ISafe(payable(safe)).execTransactionFromModule(token, 0, data, Enum.Operation.Call),
                        TransferFailed(safe, msg.sender, token)
                    );
                }
            } catch {
                revert TransferFailed(safe, msg.sender, token);
            }
        }

        // Update bookkeeping
        a.totalSpent += transferAmount;
        a.totalUnspent -= transferAmount;

        emit AllowanceTransferred(safe, msg.sender, token, to, transferAmount);

        return transferAmount;
    }

    /// @notice Get the allowance data for a token.
    /// @param safe The address of the safe.
    /// @param delegate The address of the delegate.
    /// @param token The address of the token.
    /// @return allowanceData [dripRatePerDay, totalUnspent, totalSpent, lastBookedAt]
    function getTokenAllowanceData(
        address safe,
        address delegate,
        address token
    ) public view returns (uint256[4] memory allowanceData) {
        LinearAllowance memory allowance = allowances[safe][delegate][token];
        allowanceData = [
            allowance.dripRatePerDay,
            allowance.totalUnspent,
            allowance.totalSpent,
            allowance.lastBookedAt
        ];
    }

    /// @notice Get the total unspent allowance for a token.
    /// @param safe The address of the safe.
    /// @param delegate The address of the delegate.
    /// @param token The address of the token.
    /// @return totalAllowanceAsOfNow The total unspent allowance as of now.
    function getTotalUnspent(address safe, address delegate, address token) public view returns (uint256) {
        LinearAllowance memory allowance = allowances[safe][delegate][token];

        // Handle uninitialized allowance (lastBookedAt == 0)
        if (allowance.lastBookedAt == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - allowance.lastBookedAt;
        uint256 daysElapsed = timeElapsed / 1 days;
        uint256 totalAllowanceAsOfNow = allowance.totalUnspent + allowance.dripRatePerDay * daysElapsed;

        return totalAllowanceAsOfNow;
    }
}
