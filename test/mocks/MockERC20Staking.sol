// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { IERC20Delegates } from "staker/interfaces/IERC20Delegates.sol";

contract MockERC20Staking is ERC20, IERC20Staking {
    mapping(address => address) private _delegates;
    uint8 private _decimals;

    constructor(uint8 decimals_) ERC20("Mock Staking Token", "MST") {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // IERC20Delegates implementation
    function delegate(address delegatee) external {
        address delegator = msg.sender;
        _delegates[delegator] = delegatee;
    }

    function delegateBySig(
        address delegator,
        address delegatee,
        uint256 /* nonce */,
        uint256 /* expiry */,
        uint8 /* v */,
        bytes32 /* r */,
        bytes32 /* s */
    ) external {
        // Mock implementation - just set the delegate without signature verification
        _delegates[delegator] = delegatee;
    }

    function delegates(address account) external view returns (address) {
        return _delegates[account];
    }

    // IERC20Permit implementation
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 /* deadline */,
        uint8 /* v */,
        bytes32 /* r */,
        bytes32 /* s */
    ) external {
        // Mock implementation - just approve without signature verification
        _approve(owner, spender, value);
    }

    function nonces(address /* owner */) external pure returns (uint256) {
        return 0; // Mock implementation
    }

    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        return bytes32(0); // Mock implementation
    }

    // Additional utility functions
    receive() external payable {}

    fallback() external payable {}
}
