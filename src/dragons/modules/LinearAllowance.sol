// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LinearAllowance {
    struct Allowance {
        uint256 dripRatePerDay;
        uint256 totalUnspent;
        uint256 totalSpent;
        uint256 lastBookedAt;
    }

    mapping(address => mapping(address => mapping(address => Allowance))) public allowances;
    mapping(address => mapping(address => bool)) public delegates;

    function addDelegate(address delegate) external {
        delegates[msg.sender][delegate] = true;
    }

    function setAllowance(address delegate, address token, uint256 dripRatePerDay) external {
        Allowance storage a = allowances[msg.sender][delegate][token];

        // Calculate spendable tokens since last bookkeeping
        if (a.lastBookedAt != 0) {
            uint256 timeElapsed = block.timestamp - a.lastBookedAt;
            uint256 daysElapsed = timeElapsed / 1 days;
            a.totalUnspent += daysElapsed * a.dripRatePerDay;
        }
        a.lastBookedAt = block.timestamp;
        a.dripRatePerDay = dripRatePerDay;
    }

    function executeAllowanceTransfer(address safe, address token, address payable to) external {
        require(delegates[safe][msg.sender], "Caller not approved delegate");
        Allowance storage a = allowances[safe][msg.sender][token];

        // Calculate spendable tokens since last bookkeeping
        if (a.lastBookedAt != 0) {
            uint256 timeElapsed = block.timestamp - a.lastBookedAt;
            uint256 daysElapsed = timeElapsed / 1 days;
            a.totalUnspent += daysElapsed * a.dripRatePerDay;
        }

        // Update allowance usage
        a.totalSpent += a.totalUnspent;
        uint256 toTransfer = a.totalUnspent;
        a.totalUnspent = 0;

        // Handle native ETH or ERC20 token transfer
        if (token == address(0)) {
            // Execute ETH transfer through Safe
            bool ethSuccess = Safe(payable(safe)).execTransactionFromModule(to, toTransfer, "", Enum.Operation.Call);
            require(ethSuccess, "ETH transfer failed");
        } else {
            // Execute ERC20 transfer through Safe
            bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", to, toTransfer);
            bool tokenSuccess = Safe(payable(safe)).execTransactionFromModule(token, 0, data, Enum.Operation.Call);
            require(tokenSuccess, "Token transfer failed");
        }
    }

    function getTokenAllowance(address safe, address delegate, address token) public view returns (uint256[4] memory) {
        Allowance memory allowance = allowances[safe][delegate][token];
        return [allowance.dripRatePerDay, allowance.totalUnspent, allowance.totalSpent, allowance.lastBookedAt];
    }
}
