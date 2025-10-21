// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @title IProtocolRegistry (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy protocols registry interface
 * @dev No longer actively used - retained for historical reference
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

    function registerAllocationStrategy(uint256 protocolId, string calldata name, address entrypoint) external;

    function getProtocol(uint256 id) external view returns (address);

    function getProtocolName(uint256 id) external view returns (string memory);
}
