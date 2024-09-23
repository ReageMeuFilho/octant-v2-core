// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @author  .
 * @title   Public Goods Staking interface
 * @dev     .
 * @notice  Public Goods Staking interface should be implemented by external protocols that
 * want give people an option to join Octant with ETH that they are depositing
 */
interface IPgStaking {
    function deposit(uint256 pgAssets) external payable returns (uint256 shares, uint256 pgShares);
    function depositFor(address user, uint256 pgAssets) external payable returns (uint256 shares, uint256 pgShares);
}

interface IPgStakingWithDestination {
    function depositForWithDestination(address user, uint256 pgAssets, address pgDestination) external payable;
}
