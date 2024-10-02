pragma solidity ^0.8.23;

import { Module } from "zodiac/core/Module.sol";

contract DragonModule is Module {
    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public override initializer {
        address _owner = abi.decode(initializeParams, (address));
        __Ownable_init(_owner);
        setAvatar(_owner);
        setTarget(_owner);
    }

    // Gnosis Safe Module functions
    function execTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) external onlyGnosisSafe returns (bool) {
        return IGnosisSafe(gnosisSafe).execTransactionFromModule(to, value, data, operation);
    }
}
