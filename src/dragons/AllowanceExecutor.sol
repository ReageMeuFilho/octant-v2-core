// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { AllowanceModule } from "src/dragons/modules/Allowance.sol";
import { ISafe } from "src/dragons/modules/Allowance.sol";
import { SimpleAllowance } from "src/dragons/modules/SimpleAllowance.sol";
import { LinearAllowance } from "src/dragons/modules/LinearAllowance.sol";

contract AllowanceExecutor {
    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;
    AllowanceModule public allowanceModule;

    constructor(address _allowanceModule) {
        allowanceModule = AllowanceModule(_allowanceModule);
    }

    // Add payable receive function
    receive() external payable {}

    /// @dev Linear allowance transfer - in house allowance module
    function executeTransferLinear(address safe, address token) external {
        LinearAllowance(address(allowanceModule)).executeAllowanceTransfer(
            safe,
            token,
            payable(address(this))
        );
    }

    /// @dev Allowance transfer using AllowanceModule by Gnosis Safe
    function executeTransfer(address safe, address token, uint256 amount) external {
        allowanceModule.executeAllowanceTransfer(
            ISafe(safe),
            token,
            payable(address(this)),
            uint96(amount),
            address(0),
            0,
            address(this),
            "" // handled by eip-1271
        );
    }

    /// @dev Simple allowance transfer - in house allowance module
    function executeTransferSimple(address safe, address token, uint256 amount) external {
        SimpleAllowance(address(allowanceModule)).executeAllowanceTransfer(safe, token, payable(address(this)), amount);
    }

    /// @dev EIP-1271 compatible signature validation
    function isValidSignature(bytes32 _hash, bytes memory) external view returns (bytes4) {
        // Authorize any hash for testing
        return MAGIC_VALUE;
    }
}
