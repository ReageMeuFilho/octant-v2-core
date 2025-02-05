// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { ISwapRouter } from "../uniswap/ISwapRouter.sol";
import { QuoteParams } from "./LibQuotes.sol";
import { ISwapperImpl } from "./SwapperImpl.sol";
import { ISwapperFlashCallback } from "./ISwapperFlashCallback.sol";

interface IUniV3Swap is ISwapperFlashCallback {
    error Unauthorized();
    error InsufficientFunds();

    struct InitFlashParams {
        QuoteParams[] quoteParams;
        FlashCallbackData flashCallbackData;
    }

    struct FlashCallbackData {
        ISwapRouter.ExactInputParams[] exactInputParams;
        address excessRecipient;
    }

    function initFlash(ISwapperImpl, InitFlashParams calldata) external payable;
}
