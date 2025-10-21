// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @title ICapitalSourceProvider (DEPRECATED)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice DEPRECATED: Legacy interface for external capital delivery to Octant
 * @dev No longer actively used - retained for historical reference
 */
interface ICapitalSourceProvider {
    function isWithdrawalRequestRequired() external returns (bool);
    function availableToWithdraw() external returns (bool);
    function requestPgWithdrawal() external;
    function claimAccumulatedPgCapital() external;
    function withdrawAccumulatedPgCapital() external returns (uint256 pgAmount);
    function claimAndWithdrawAccumulatedPgCapital() external returns (uint256 pgAmount);
    function getEligibleRewards() external view returns (uint256);
}
