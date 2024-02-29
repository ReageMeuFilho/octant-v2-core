// SPDX-License-Identifier; GPL-3.0

pragma solidity ^0.8.23;

import {IDragonsFactory} from "../interfaces/IDragonsFactory.sol";
import {Dragon} from "./Dragon.sol";

/**
 * @author  .
 * @title   Dragons Factory
 * @notice  Deploys and manages Dragons
 */
contract DragonsFactory is IDragonsFactory {
    
    /// @inheritdoc IDragonsFactory
    function createDragon(
        address governingToken,
        address octantRouter,
        address epochsGuardian
    ) external returns (address dragon) {
        return address(new Dragon(governingToken, octantRouter, epochsGuardian));
    }
}