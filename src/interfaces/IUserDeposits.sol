// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

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
