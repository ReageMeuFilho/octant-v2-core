// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @author  .
 * @title   Public Goods Staking interface
 * @dev     .
 * @notice  Public Goods Staking interface should be implemented by external protocols that want give people an option to join
 * @notice  Octant with ETH that they are depositing
 */

interface IPgStaking {
    function deposit(uint256 pgAmount) external payable;
    function depositFor(address user, uint256 pgAmount) external payable;
}


interface IPgStakingWithDestination {
    function depositForWithDestination(address user, uint256 pgAmount, address pgDestination) external payable;
}
