// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";

/**
 * @title ERC20SafeLib
 * @notice Library with safe ERC20 operations that handle non-standard token implementations
 * @dev Provides safety wrappers for ERC20 operations that may not return a boolean
 */
library ERC20SafeLib {
    /**
     * @notice Safely approve ERC20 tokens, handling non-standard implementations
     * @param token The token to approve
     * @param spender The address to approve spending for
     * @param amount The amount to approve
     */
    function safeApprove(address token, address spender, uint256 amount) external {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert IMultistrategyVault.ApprovalFailed();
        }
    }

    /**
     * @notice Safely transfer ERC20 tokens from one address to another, handling non-standard implementations
     * @param token The token to transfer
     * @param sender The address to transfer from
     * @param receiver The address to transfer to
     * @param amount The amount to transfer
     */
    function safeTransferFrom(address token, address sender, address receiver, uint256 amount) external {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, sender, receiver, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert IMultistrategyVault.TransferFailed();
        }
    }

    /**
     * @notice Safely transfer ERC20 tokens, handling non-standard implementations
     * @param token The token to transfer
     * @param receiver The address to transfer to
     * @param amount The amount to transfer
     */
    function safeTransfer(address token, address receiver, uint256 amount) external {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, receiver, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert IMultistrategyVault.TransferFailed();
        }
    }
}
