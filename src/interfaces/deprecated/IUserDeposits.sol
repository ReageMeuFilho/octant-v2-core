// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

/**
 * @title IUserDeposits (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy user deposits interface
 * @dev No longer actively used - retained for historical reference
 */
interface IUserDeposits {
    function getIndividualShare(
        address _user,
        uint256 _accumulationPeriod,
        bytes memory _data
    ) external view returns (uint256 amount);
    function getTokensLocked(
        address _user,
        uint256 _from,
        uint256 _to,
        bytes memory _data
    ) external view returns (uint256 amount);
    function getTokensUnlocked(
        address _user,
        uint256 _from,
        uint256 _to,
        bytes memory _data
    ) external view returns (uint256 amount);
}
