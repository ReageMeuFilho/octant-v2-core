// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

import { IDragon } from "../interfaces/IDragon.sol";

/**
 * @author  .
 * @title   Dragon Contract
 * @dev     .
 * @notice  The Dragon is a facade contract that is the main entrypoint of interactions with an Octant model PG funding mechanism for a specific Dragon
 */
contract Dragon is IDragon {
    address token;
    address octantRouter;
    address epochsGuardian;

    constructor(address governingToken, address router, address guardian) {
        token = governingToken;
        octantRouter = router;
        epochsGuardian = guardian;
    }

    /// @inheritdoc IDragon
    function getDragonToken() external view returns (address) {
        return token;
    }

    /// @inheritdoc IDragon
    function getOctantRouter() external view returns (address) {
        return octantRouter;
    }

    /// @inheritdoc IDragon
    function getEpochsGuardian() external view returns (address) {
        return epochsGuardian;
    }
}
