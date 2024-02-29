// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;


/**
 * @author  .
 * @title   The interface for the DragonsFactory
 * @dev     Draft
 * @notice  This contract is used to deploy and configure facade Dragon contracts
 */

interface IDragonsFactory {

    /**
     * @notice  Creates a dragon contract that defines key parameters, algorithms and addresses of that dragon
     * @dev     Consider using beacon proxy
     * @param   governingToken  A token that is used as a collateral to receive PG voting rights and individual rewards
     * @param   octantRouter  A router that acts as entry point for routing, transformation and distribution of the rewards
     * @param   epochsGuardian  A guardian that defines rules and conditions for capital flows
     * @return  dragon  Returns an address of the dragon
     */
    function createDragon(
        address governingToken,
        address octantRouter,
        address epochsGuardian
    ) external returns (address dragon);
}