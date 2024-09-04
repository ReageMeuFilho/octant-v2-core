// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import {ICapitalTransformer} from "../interfaces/ICapitalTransformer.sol";
import {SplitV2Lib} from "@splits/splits-v2/libraries/SplitV2.sol";

/**
 * @author  .
 * @title   Split Transformer Interface
 * @dev     .
 * @notice  Split Transformer implementation is responsible for the logic of dividing an input amount
 * into an N of chunks and associated addresses
 */
 interface ISplitTransformer {
    function transform(uint256 amount, ICapitalTransformer[] calldata transformers, bytes[] calldata data) external returns (SplitV2Lib.Split memory);
 }