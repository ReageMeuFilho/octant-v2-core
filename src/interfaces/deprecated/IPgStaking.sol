// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @title IPgStaking (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy public goods staking interface
 * @dev No longer actively used - retained for historical reference
 */
interface IPgStaking {
    function deposit(uint256 pgAssets) external payable returns (uint256 shares, uint256 pgShares);
    function depositFor(address user, uint256 pgAssets) external payable returns (uint256 shares, uint256 pgShares);
}

interface IPgStakingWithDestination {
    function depositForWithDestination(address user, uint256 pgAssets, address pgDestination) external payable;
}
