// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { ISwapRouter } from "src/utils/vendor/uniswap/ISwapRouter.sol";
import { QuoteParams } from "./LibQuotes.sol";
import { ISwapperImpl } from "./SwapperImpl.sol";
import { ISwapperFlashCallback } from "./ISwapperFlashCallback.sol";

/**
 * @title IUniV3Swap
 * @author 0xSplits
 * @custom:vendor 0xSplits
 * @notice Uniswap V3 swap integration interface
 */
interface IUniV3Swap is ISwapperFlashCallback {
    struct InitFlashParams {
        QuoteParams[] quoteParams;
        FlashCallbackData flashCallbackData;
    }

    struct FlashCallbackData {
        ISwapRouter.ExactInputParams[] exactInputParams;
        address excessRecipient;
    }

    error Unauthorized();
    error InsufficientFunds();

    function initFlash(ISwapperImpl, InitFlashParams calldata) external payable;
}
