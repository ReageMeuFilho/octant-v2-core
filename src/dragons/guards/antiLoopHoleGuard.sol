// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import { BaseGuard } from "zodiac/guard/BaseGuard.sol";
import { Enum } from "zodiac/interfaces/IAvatar.sol";
import { FactoryFriendly } from "zodiac/factory/FactoryFriendly.sol";

error AntiLoopholeGuard__LockPeriodNotEnded();

contract AntiLoopholeGuard is FactoryFriendly, BaseGuard {
    uint256 public lockEndTime;
    uint256 public constant LOCK_DURATION = 25 days;
    bool public isDisabled;

    error DelegateCallNotAllowed();
    error ModuleAdditionNotAllowed();
    error GuardAlreadyDisabled();

    constructor(address _owner) {
        bytes memory initializeParams = abi.encode(_owner);
        setUp(initializeParams);
    }

    function setUp(bytes memory initializeParams) public override initializer {
        address _owner = abi.decode(initializeParams, (address));
        lockEndTime = block.timestamp + LOCK_DURATION;
        transferOwnership(_owner);
    }

    // solhint-disable
    function checkTransaction(
        address to,
        uint256,
        bytes memory data,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external view virtual override {
        if (isDisabled) {
            return;
        }
        if (to == address(0)) {
            return;
        }
        if (block.timestamp < lockEndTime) {
            if (operation == Enum.Operation.DelegateCall) {
                revert DelegateCallNotAllowed();
            }

            bytes4 functionSig = bytes4(data);
            if (functionSig == bytes4(keccak256("enableModule(address)"))) {
                // maybe whilelist some modules here
                revert ModuleAdditionNotAllowed();
            }
        }
    }

    // solhint-enable

    function checkAfterExecution(bytes32, bool) external view virtual override {
        // balance checks against Avatar go here, leave the function virtual and override
    }

    function disableGuard() external onlyOwner {
        require(block.timestamp >= lockEndTime, AntiLoopholeGuard__LockPeriodNotEnded());
        if (isDisabled) revert GuardAlreadyDisabled();
        isDisabled = true;
    }
}
