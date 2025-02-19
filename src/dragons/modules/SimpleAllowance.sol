// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleAllowance {
    struct Allowance {
        uint256 amount;
        uint256 spent;
        uint32 resetTimeMin;
        uint32 lastResetMin;
    }

    mapping(address => mapping(address => mapping(address => Allowance))) public allowances;
    mapping(address => mapping(address => bool)) public delegates;

    event AddDelegate(address indexed safe, address indexed delegate);
    event SetAllowance(
        address indexed safe,
        address indexed delegate,
        address indexed token,
        uint256 amount,
        uint32 resetTimeMin
    );

    function addDelegate(address delegate) external {
        delegates[msg.sender][delegate] = true;
        emit AddDelegate(msg.sender, delegate);
    }

    function setAllowance(
        address delegate,
        address token,
        uint256 amount,
        uint32 resetTimeMin,
        uint32 lastResetMin
    ) external {
        allowances[msg.sender][delegate][token] = Allowance(amount, 0, resetTimeMin, lastResetMin);
        emit SetAllowance(msg.sender, delegate, token, amount, resetTimeMin);
    }

    function executeAllowanceTransfer(address safe, address token, address payable to, uint256 amount) external {
        require(delegates[safe][msg.sender], "Caller not approved delegate");
        Allowance storage a = allowances[safe][msg.sender][token];

        // Check if allowance should reset
        uint256 currentMin = block.timestamp / 60;
        if (currentMin > a.lastResetMin + a.resetTimeMin) {
            a.spent = 0;
            a.lastResetMin = uint32(currentMin);
        }

        // Ensure transfer does not exceed allowance
        require(a.spent + amount <= a.amount, "Transfer exceeds allowance");

        // Update allowance usage
        a.spent += amount;

        // Handle native ETH or ERC20 token transfer
        if (token == address(0)) {
            // Execute ETH transfer through Safe
            bool ethSuccess = Safe(payable(safe)).execTransactionFromModule(to, amount, "", Enum.Operation.Call);
            require(ethSuccess, "ETH transfer failed");
        } else {
            // Execute ERC20 transfer through Safe
            bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", to, amount);
            bool tokenSuccess = Safe(payable(safe)).execTransactionFromModule(
                token, // Token contract address
                0,     // No value needed for ERC20
                data,
                Enum.Operation.Call
            );
            require(tokenSuccess, "Token transfer failed");
        }
    }

    function getTokenAllowance(address safe, address delegate, address token) public view returns (uint256[4] memory) {
        Allowance memory allowance = allowances[safe][delegate][token];
        return [allowance.amount, allowance.spent, allowance.resetTimeMin, allowance.lastResetMin];
    }
}
