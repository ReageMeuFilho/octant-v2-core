// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

interface IHatsToggle {
    function getHatStatus(uint256 _hatId) external view returns (bool);
}
