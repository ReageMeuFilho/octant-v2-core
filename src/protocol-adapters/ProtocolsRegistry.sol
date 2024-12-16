// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { IProtocolRegistry } from "../interfaces/IProtocolsRegistry.sol";

/**
 * @author  .
 * @title   Protocols Registry
 * @dev     .
 * @notice  Protocols Registry is a mechanism to curate external funds allocation & distribution algorithms
 */
contract ProtocolsRegistry is IProtocolRegistry {
    mapping(uint256 => Protocol) protocolRegistry;
    mapping(uint256 => ProtocolStrategy) strategiesRegistry;

    function registerProtocol(string calldata name, address entrypoint) external {}

    function getProtocol(uint256 id) external view returns (address) {}

    function getProtocolName(uint256 id) external view returns (string memory) {}

    function registerAllocationStrategy(uint256 protocolId, string calldata name, address entrypoint) external {}
}
