// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @author  .
 * @title   The Dragon
 * @dev     Draft
 * @notice  Interface for the Dragon contract, the facade to interact with an Octant-based ecosystem
 */
interface IDragon {
    /**
     * @notice  Returns the dragon token address
     * @dev     .
     * @return  dragonToken  A token that is used as a collateral to receive PG voting rights and individual rewards
     */
    function getDragonToken() external view returns (address);

    /**
     * @notice  .
     * @dev     .
     * @return  octantRouter  A router that acts as entry point for routing, transformation and distribution of the rewards
     */
    function getOctantRouter() external view returns (address);

    /**
     * @notice  .
     * @dev     .
     * @return  epochsGuardian  A guardian that defines rules and conditions for capital flows
     */
    function getEpochsGuardian() external view returns (address);
}
