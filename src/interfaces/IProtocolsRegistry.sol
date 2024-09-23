// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @author  .
 * @title   Protocols Registry Interface
 * @dev     .
 * @notice  Protocols Registry is a mechanism to curate external funds allocation & distribution algorithms
 */
interface IProtocolRegistry {
    struct Protocol {
        string name;
        address entrypoint;
    }

    struct ProtocolStrategy {
        uint256 protocolId;
        string name;
        address entrypoint;
    }

    function registerProtocol(string calldata name, address entrypoint) external;

    function getProtocol(uint256 id) external view returns (address);

    function getProtocolName(uint256 id) external view returns (string memory);

    function registerAllocationStrategy(uint256 protocolId, string calldata name, address entrypoint) external;
}
