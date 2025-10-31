// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit, IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

// This mock implements IERC20Permit but NOT IERC20Staking (no delegation functionality)
contract MockERC20Permit is ERC20, ERC20Permit {
    constructor(uint8 decimals) ERC20("MockERC20Permit", "MOCK") ERC20Permit("MockERC20Permit") {
        _mint(msg.sender, 1000000 * 10 ** decimals);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Functions permit(), nonces(), and DOMAIN_SEPARATOR() are inherited directly from ERC20Permit.
}
