// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./MockDragonRouter.sol";

contract MockStrategy is ERC20 {
    address public asset;

    uint256 constant SHARES_TO_MINT = 100 * 1e18;

    constructor(address _asset) ERC20("Mock Strategy Shares", "MSS") {
        asset = _asset;
    }

    function report() external returns (uint256) {
        // Mint 100 new shares to caller
        _mint(msg.sender, SHARES_TO_MINT);
        // call msg.sender addNewShares(SHARES_TO_MINT)
        MockDragonRouter(msg.sender).addNewShares(SHARES_TO_MINT);
        return SHARES_TO_MINT;
    }

    function unwrap(uint256 amount) external returns (uint256) {
        require(balanceOf(msg.sender) >= amount, "Insufficient shares");
        _burn(msg.sender, amount);
        // In real implementation would calculate ETH amount
        // For mock, we'll do 1:1
        // transfer the asset to the caller
        IERC20(asset).transfer(msg.sender, amount);
        return amount;
    }
}
