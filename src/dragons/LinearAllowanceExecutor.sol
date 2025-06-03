// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { LinearAllowanceSingletonForGnosisSafe } from "src/dragons/modules/LinearAllowanceSingletonForGnosisSafe.sol";

contract LinearAllowanceExecutor {
    // Add payable receive function otherwise it will revert on ETH transfers
    receive() external payable virtual {}

    // @notice Execute a transfer of the allowance.
    /// @param allowanceModule The allowance module to use.
    /// @param safe The address of the safe.
    /// @param token The address of the token.
    /// @return transferredAmount The amount that was actually transferred
    function executeAllowanceTransfer(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address safe,
        address token
    ) external returns (uint256) {
        return allowanceModule.executeAllowanceTransfer(safe, token, payable(address(this)));
    }

    // @notice Get the total unspent allowance for a token.
    /// @param allowanceModule The allowance module to use.
    /// @param safe The address of the safe.
    /// @param token The address of the token.
    /// @return totalAllowanceAsOfNow The total unspent allowance as of now.
    function getTotalUnspent(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address safe,
        address token
    ) external view returns (uint256) {
        return allowanceModule.getTotalUnspent(safe, address(this), token);
    }
}
