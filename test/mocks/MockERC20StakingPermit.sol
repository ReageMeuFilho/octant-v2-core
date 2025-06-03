// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit, IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

// This mock is primarily for ERC20 and EIP-2612 Permit functionality.
// It does not need to fully implement IERC20Staking if RegenStaker only uses permit on it.
contract MockERC20StakingPermit is ERC20, ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Functions permit(), nonces(), and DOMAIN_SEPARATOR() are inherited directly from ERC20Permit.
    // No explicit override needed here unless there was a conflict from another base,
    // which is not the case after removing IERC20Staking.
}
