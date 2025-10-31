// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

/**
 * @author  .
 * @title   Capital Source Provider
 * @dev     .
 * @notice  Capital Source Provider is used as a mechanism to deliver capital from external protocols to Octant
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
