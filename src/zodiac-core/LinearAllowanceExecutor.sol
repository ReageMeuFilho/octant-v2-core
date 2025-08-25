// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LinearAllowanceSingletonForGnosisSafe } from "src/zodiac-core/modules/LinearAllowanceSingletonForGnosisSafe.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";

/// @title LinearAllowanceExecutor
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Abstract base contract for executing linear allowance transfers from Gnosis Safe modules
/// @dev This contract provides the core functionality for interacting with LinearAllowanceSingletonForGnosisSafe
/// while leaving withdrawal mechanisms to be implemented by derived contracts. The contract can receive
/// both ETH and ERC20 tokens from allowance transfers, but the specific withdrawal logic must be defined
/// by inheriting contracts to ensure proper access control and business logic implementation.
///
/// Assumptions and security model:
/// - This executor contract instance is configured as the delegate in the LinearAllowance module.
/// - A module whitelist may be set via `setModuleWhitelist`; `_validateModule` enforces it on calls.
/// - If `moduleWhitelist` is unset (address(0)), `_validateModule` skips checks and allows any module.
abstract contract LinearAllowanceExecutor {
    /// @notice Whitelist contract for allowance modules to prevent arbitrary external calls
    IWhitelist public moduleWhitelist;

    /// @notice Error thrown when attempting to use a non-whitelisted module
    error ModuleNotWhitelisted(address module);

    /// @notice Emitted when the module whitelist is updated
    event ModuleWhitelistSet(IWhitelist indexed whitelist);

    /// @notice External function to configure the module whitelist used by this executor.
    /// @dev Implementing contracts MUST restrict access (e.g., onlyOwner or governance).
    /// Setting to address(0) unsets the whitelist in this executor; `_validateModule` then skips checks.
    /// @param whitelist The whitelist contract address; set to address(0) to unset in this executor.
    function setModuleWhitelist(IWhitelist whitelist) external virtual;

    /// @notice Internal helper that updates the whitelist reference and emits an event.
    /// @dev Does not perform access control; call from a restricted external setter.
    /// @param whitelist The whitelist contract address; address(0) unsets it so `_validateModule` skips checks.
    function _setModuleWhitelist(IWhitelist whitelist) internal {
        moduleWhitelist = whitelist;
        emit ModuleWhitelistSet(whitelist);
    }

    /// @notice Validate that a module is permitted to interact with this executor.
    /// @dev If no whitelist is configured (moduleWhitelist == address(0)), any module is allowed.
    /// Reverts with ModuleNotWhitelisted when a whitelist is set and the module is not listed.
    /// @param module The allowance module address to validate.
    function _validateModule(address module) internal view {
        if (address(moduleWhitelist) != address(0) && !moduleWhitelist.isWhitelisted(module)) {
            revert ModuleNotWhitelisted(module);
        }
    }

    /// @notice Accept ETH sent by allowance executions.
    /// @dev Required so ETH transfers from a Safe succeed when this contract is the recipient.
    receive() external payable virtual;

    /// @notice Pull available allowance from a Safe into this contract.
    /// @dev Validates the module via `_validateModule`. The module uses msg.sender as the delegate,
    /// which means THIS contract instance must be configured as the delegate for the given Safe.
    /// Funds are always sent to address(this) and remain here until `withdraw` is called.
    /// Reverts if the underlying module call fails or no allowance is available.
    /// @param allowanceModule The allowance module to interact with.
    /// @param safe The Safe that is the source of the allowance.
    /// @param token The token to transfer; use NATIVE_TOKEN for ETH.
    /// @return transferredAmount The amount actually transferred to this contract.
    function executeAllowanceTransfer(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address safe,
        address token
    ) external returns (uint256) {
        _validateModule(address(allowanceModule));
        // Execute the allowance transfer, sending funds to this contract
        return allowanceModule.executeAllowanceTransfer(safe, token, payable(address(this)));
    }

    /// @notice Pull allowance from multiple Safes into this contract.
    /// @dev For each transfer, the module treats msg.sender as the delegate (this contract).
    /// Destinations are forced to address(this) to prevent parameter-injection attacks.
    /// Reverts if any underlying module call fails.
    /// @param allowanceModule The allowance module to interact with.
    /// @param safes Safe addresses that are the sources of allowances.
    /// @param tokens Token addresses to transfer; use NATIVE_TOKEN for ETH.
    /// @return transferAmounts Amounts transferred for each operation.
    function executeAllowanceTransfers(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address[] calldata safes,
        address[] calldata tokens
    ) external returns (uint256[] memory transferAmounts) {
        _validateModule(address(allowanceModule));
        address[] memory tos = new address[](safes.length);
        for (uint256 i = 0; i < safes.length; i++) {
            tos[i] = address(this);
        }
        return allowanceModule.executeAllowanceTransfers(safes, tokens, tos);
    }

    /// @notice Get the total unspent allowance for this executor as delegate.
    /// @dev Pure view into module bookkeeping for this delegate; does not read this contract's balance.
    /// @param allowanceModule The allowance module to query.
    /// @param safe The Safe that is the source of the allowance.
    /// @param token The token address; use NATIVE_TOKEN for ETH.
    /// @return totalAllowanceAsOfNow The unspent allowance at the time of the call.
    function getTotalUnspent(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address safe,
        address token
    ) external view returns (uint256) {
        // Query the allowance module for this contract's unspent allowance
        return allowanceModule.getTotalUnspent(safe, address(this), token);
    }

    /// @notice Withdraw funds that have been pulled into this contract.
    /// @dev Must be implemented by derived contracts with appropriate access control and safeguards.
    /// Implementations should validate `to`, consider pausing/emergency paths, and apply business rules.
    /// This function transfers funds already resident in this contract, not from the Safe directly.
    /// @param token The token to withdraw; use NATIVE_TOKEN for ETH.
    /// @param amount The amount to withdraw from this contract's balance.
    /// @param to The recipient address for the withdrawn funds.
    function withdraw(address token, uint256 amount, address payable to) external virtual;

    /// @notice Get the maximum amount currently withdrawable for this delegate.
    /// @dev Delegates to the module; computed as the minimum of unspent allowance and the Safe's
    /// current token balance at call time.
    /// @param allowanceModule The allowance module to query.
    /// @param safe The Safe that is the source of the allowance.
    /// @param token The token address; use NATIVE_TOKEN for ETH.
    /// @return maxWithdrawableAmount The maximum withdrawable amount right now.
    function getMaxWithdrawableAmount(
        LinearAllowanceSingletonForGnosisSafe allowanceModule,
        address safe,
        address token
    ) external view returns (uint256) {
        return allowanceModule.getMaxWithdrawableAmount(safe, address(this), token);
    }
}
