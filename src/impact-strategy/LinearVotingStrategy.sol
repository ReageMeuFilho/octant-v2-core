// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BaseImpactStrategy.sol";

/**
 * @title LinearVotingStrategy
 * @notice Example strategy with linear vote counting
 */
contract LinearVotingStrategy is BaseImpactStrategy {
    /**
     * @notice Process votes linearly
     * @param voter Address of voter
     * @param project Project being voted for
     * @param amount Amount of veTokens to vote with
     */
    function _processVote(
        address voter,
        address project,
        uint256 amount
    ) internal override {
        // Lock veTokens for voting period
        veToken.lock(voter, amount);
        
        // Record vote
        VaultState storage state = _getState();
        state.projectVotes[project] += amount;
    }
} 