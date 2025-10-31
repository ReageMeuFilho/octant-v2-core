// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

/**
 * @notice Interface for the factory that deployed the vault.
 */
interface IFactory {
    function protocolFeeConfig() external view returns (uint16, address);
}
