// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract MockIntentProtocol {
    struct Intent {
        address fromToken;
        address toToken;
        uint256 amount;
        uint256 minOut;
        uint256 deadline;
        address recipient;
        address dragonRouter;
    }

    mapping(bytes32 => Intent) public intents;

    event IntentCreated(bytes32 indexed intentId, Intent intent);
    event IntentExecuted(bytes32 indexed intentId, uint256 amountOut);

    function createIntent(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 minOut,
        uint256 deadline,
        address recipient,
        address dragonRouter
    ) external returns (bytes32) {
        bytes32 intentId = keccak256(
            abi.encodePacked(fromToken, toToken, amount, minOut, deadline, recipient, block.timestamp)
        );

        intents[intentId] = Intent({
            fromToken: fromToken,
            toToken: toToken,
            amount: amount,
            minOut: minOut,
            deadline: deadline,
            recipient: recipient,
            dragonRouter: dragonRouter
        });

        emit IntentCreated(intentId, intents[intentId]);
        return intentId;
    }

    function executeIntent(bytes32 intentId, uint256 amountOut) external {
        Intent memory intent = intents[intentId];
        require(block.timestamp <= intent.deadline, "Intent expired");
        require(amountOut >= intent.minOut, "Insufficient output amount");

        // Mock the token swap
        IERC20(intent.fromToken).transferFrom(intent.dragonRouter, address(this), intent.amount);

        IERC20(intent.toToken).transfer(intent.recipient, amountOut);

        delete intents[intentId];
        emit IntentExecuted(intentId, amountOut);
    }
}
