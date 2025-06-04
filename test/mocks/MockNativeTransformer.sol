// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ITransformer } from "src/zodiac-core/interfaces/ITransformer.sol";

/**
 * @title MockNativeTransformer
 * @dev Mock contract for testing transformations with native ETH
 */
contract MockNativeTransformer is ITransformer {
    // This function will handle native ETH (msg.value)
    function transform(address, address, uint256) external payable override returns (uint256) {
        // Return a slightly lower amount to simulate slippage
        uint256 transformedAmount = (msg.value * 9) / 10;

        // Simply return the transformed amount
        return transformedAmount;
    }

    // Add a fallback function to handle receiving ETH
    receive() external payable {}
}
