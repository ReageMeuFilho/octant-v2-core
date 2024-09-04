// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import {ISplitTransformer} from "../interfaces/ISplitTransformer.sol";
import {ICapitalTransformer} from "../interfaces/ICapitalTransformer.sol";
import {SplitV2Lib} from "@splits/splits-v2/libraries/SplitV2.sol";

contract OctantSplitTransformer is ISplitTransformer {
    using SplitV2Lib for SplitV2Lib.Split;

    function transform(uint256 amount, ICapitalTransformer[] calldata transformers, bytes[] calldata data) external returns (SplitV2Lib.Split memory) {
        // check if transformers an data sizes are equal
        uint256[] memory allocations = new uint256[](transformers.length);
        address[] memory recipients = new address[](transformers.length);
        uint256 totalCalculatedAmount = 0;

        for (uint256 i = 0; i < transformers.length; i++) {
            allocations[i] = transformers[i].transform(amount, data[i]);
            recipients[i] = transformers[i].receiver();
            totalCalculatedAmount += allocations[i];
        }

        // check if totalCalculatedAmount is equal to amount
        return SplitV2Lib.Split(recipients, allocations, amount, 0);
    }
}