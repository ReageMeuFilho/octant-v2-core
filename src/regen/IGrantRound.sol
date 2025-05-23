// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGrantRound {
    /// @notice Grants voting power to `receiver` by
    /// depositing exactly `assets` of underlying tokens.
    /// @param assets The amount of underlying to deposit in.
    /// @param receiver The address to receive the `shares`.
    /// @param signature The signature of the user.
    /// @return votingPower The actual amount of votingPower issued. In case of a failure, votingPower will be 0.
    function signup(uint256 assets, address receiver, bytes32 signature) external returns (uint256 votingPower);

    /// @notice Process a vote for a project with a contribution amount and vote weight
    /// @dev This function validates and processes votes according to the implemented formula
    /// @dev Must check if the user can vote in _processVote
    /// @dev Must check if the project is whitelisted in _processVote
    /// @dev Must update the project tally in _processVote
    /// Only keepers can call this function to prevent spam and ensure proper vote processing.
    /// @param projectId The ID of the project being voted for
    /// @param votingPower the votingPower msg.sender will assign to projectId, must be checked in _processVote by strategist
    function vote(uint256 projectId, uint256 votingPower) external;
}
