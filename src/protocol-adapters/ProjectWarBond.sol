// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {ONFT1155} from "src/vendor/layerzero/ONFT1155.sol";

contract ProjectWarBond is ONFT1155 {
    address public registry;

    constructor(
        address _owner,
        address _registry,
        address _lzEndpoint,
        string memory _uri
    ) ONFT1155(_uri, _lzEndpoint, _owner) {
        registry = msg.sender;
    }

    function setNewRegistry(address _newRegistry) external {
        require(msg.sender == registry, "Only previous registry can set new registry");
        registry = _newRegistry;
    }

    function mint(address recipient, uint256 amount) external {
        require(msg.sender == registry, "Only registry can mint");
        _mint(recipient, 0, amount, "");
    }
} 
