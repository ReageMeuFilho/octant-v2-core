// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/**
 * @title LibQuotes
 * @author 0xSplits
 * @custom:vendor 0xSplits
 * @notice Quote parameter types for swap operations
 */

struct QuoteParams {
    QuotePair quotePair;
    uint128 baseAmount;
    bytes data;
}

struct QuotePair {
    address base;
    address quote;
}
