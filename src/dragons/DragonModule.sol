pragma solidity ^0.8.23;

import { Module } from "zodiac/core/Module.sol";
import { IAvatar, Enum } from "zodiac/interfaces/IAvatar.sol";
import { Unauthorized, ZeroAddress } from "src/errors.sol";

contract DragonModule is Module {
    struct DragonModuleStorageV0 {
        address gnosisSafe;
        address dragonRouter;
        address strategy;
        address accessControlRegistry;
    }

    /// keccak256(abi.encode(uint256(keccak256("dragonmodule.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 public constant DRAGON_MODULE_STORAGE_LOCATION =
        0x5c9920b1e29ceee7a72a6a1d1314bf71f30523f55624a0abe6d215ad1e9bf100;

    function _dragonModuleStorage() internal pure returns (DragonModuleStorageV0 storage $) {
        bytes32 loc = DRAGON_MODULE_STORAGE_LOCATION;
        assembly {
            $.slot := loc
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _gnosisSafe, address _dragonRouter, address _strategy) public {
        if (_dragonRouter == address(0)) {
            revert ZeroAddress();
        }
        if (_strategy == address(0)) {
            revert ZeroAddress();
        }
        if (_gnosisSafe == address(0)) {
            revert ZeroAddress();
        }
        DragonModuleStorageV0 storage $ = _dragonModuleStorage();
        $.gnosisSafe = _gnosisSafe;
        $.dragonRouter = _dragonRouter;
        $.strategy = _strategy;
    }

    function _requireOnlyGnosisSafe() internal view {
        DragonModuleStorageV0 storage $ = _dragonModuleStorage();
        if (msg.sender != $.gnosisSafe) {
            revert Unauthorized();
        }
    }

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public override initializer {
        address _owner = abi.decode(initializeParams, (address));
        __Ownable_init(_owner);
        setAvatar(_owner);
        setTarget(_owner);
    }

    // Gnosis Safe Module functions
    function execTransaction(address to, uint256 value, bytes memory data, uint8 operation) external returns (bool) {
        DragonModuleStorageV0 storage $ = _dragonModuleStorage();
        _requireOnlyGnosisSafe();
        return IAvatar($.gnosisSafe).execTransactionFromModule(to, value, data, Enum.Operation(operation));
    }
}
