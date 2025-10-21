// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @title IHatsToggle
 * @author Haberdasher Labs
 * @custom:vendor Hats Protocol
 * @notice Interface for hat toggle modules
 * @dev Determines if a hat is active/inactive
 */
interface IHatsToggle {
    function getHatStatus(uint256 _hatId) external view returns (bool);
}
