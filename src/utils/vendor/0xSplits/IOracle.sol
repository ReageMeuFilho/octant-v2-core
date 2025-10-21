// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { QuoteParams } from "./LibQuotes.sol";

/**
 * @title IOracle
 * @author 0xSplits
 * @custom:vendor 0xSplits
 * @notice Oracle interface for price quotes
 */
interface IOracle {
    function getQuoteAmounts(QuoteParams[] calldata quoteParams_) external view returns (uint256[] memory);
}
