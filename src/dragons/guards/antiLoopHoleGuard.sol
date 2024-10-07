pragma solidity ^0.8.23;

import { BaseGuard } from "zodiac/guard/BaseGuard.sol";

contract AntiLoopholeGuard is FactoryFriendly, BaseGuard, Ownable {
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
        __Ownable_init();
        address _owner = abi.decode(initializeParams, (address));
        lockEndTime = block.timestamp + LOCK_DURATION;
        transferOwnership(_owner); <------ I assume this is the Avatar (SAFE)?
    }

    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        ...
    ) external view override {
        if (isDisabled) {
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

    function checkAfterExecution(bytes32, bool) external view override virtual {
      // balance checks against Avatar go here, leave the function virtual and override
    }

    function disableGuard() external onlyOwner {
        require(block.timestamp >= lockEndTime, "Lock period not ended");
        if (isDisabled) revert GuardAlreadyDisabled();
        isDisabled = true;
    }
}
