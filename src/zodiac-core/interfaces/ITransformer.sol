// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface ITransformer {
    function transform(address fromToken, address toToken, uint256 amount) external payable returns (uint256);
}
