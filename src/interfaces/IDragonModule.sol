// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

/**
 * @author  .
 * @title   The Dragon
 * @dev     Draft
 * @notice  Interface for the Dragon Moodule contract
 */
interface IDragonModule {
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
    function getDragonRouter() external view returns (address);
}
