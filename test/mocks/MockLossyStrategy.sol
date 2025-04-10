// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { MockYieldStrategy } from "./MockYieldStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockLossyStrategy is MockYieldStrategy {
    uint256 public lossAmount;

    constructor(address _asset, address _vault) MockYieldStrategy(_asset, _vault) {}

    function setLoss(uint256 _lossAmount) external {
        // Store the loss amount without actually transferring funds
        lossAmount = _lossAmount;
    }

    // Override to simulate loss
    function totalAssets() public view override returns (uint256) {
        // Return balance minus the tracked loss amount
        uint256 balance = IERC20(asset).balanceOf(address(this));
        return balance > lossAmount ? balance - lossAmount : 0;
    }

    // Optional: Override the simulateLoss method to actually transfer funds when needed
    function simulateLoss(uint256 amount) external override {
        // First set the loss amount
        lossAmount = amount;
        // Then actually transfer the funds out if requested
        // This makes the physical state match the reported state
        IERC20(asset).transfer(msg.sender, amount);
    }
}
