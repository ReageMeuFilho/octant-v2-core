pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";

/**
 * @title ERC20SafeApproveLib
 * @notice Library with safe ERC20 approve operations that handle non-standard token implementations
 * @dev Provides safety wrappers for ERC20 approve operations that may not return a boolean
 */
library ERC20SafeApproveLib {
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
}
