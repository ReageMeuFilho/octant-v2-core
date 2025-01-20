// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Dragon Test Token", "DTT") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    receive() external payable {}

    fallback() external payable {}
}
