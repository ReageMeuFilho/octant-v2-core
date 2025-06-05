// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { DistributionMechanism } from "../DistributionMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Simple Voting Mechanism with Share Distribution
/// @notice Implements a basic 1:1 voting mechanism where net votes directly convert to shares
contract SimpleVotingMechanism is DistributionMechanism {
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumShares,
        uint256 _timelockDelay,
        uint256 _startBlock
    )
        DistributionMechanism(
            _asset,
            _name,
            _symbol,
            _votingDelay,
            _votingPeriod,
            _quorumShares,
            _timelockDelay,
            _startBlock
        )
    {}

    function _beforeProposeHook(address proposer) internal view override returns (bool) {
        return _getStorage().votingPower[proposer] > 0;
    }

    function _validateProposalHook(uint256 pid) internal view override returns (bool) {
        return pid > 0 && pid <= _getStorage().proposalIdCounter;
    }

    function _beforeSignupHook(address) internal pure override returns (bool) {
        return true;
    }

    function _getVotingPowerHook(address, uint256 deposit) internal pure override returns (uint256) {
        return deposit;
    }

    function _processVoteHook(
        uint256 pid,
        address,
        VoteType choice,
        uint256 weight,
        uint256 oldPower
    ) internal override returns (uint256) {
        BaseAllocationStorage storage s = _getStorage();
        if (choice == VoteType.For) {
            s.proposalVotes[pid].sharesFor += weight;
        } else if (choice == VoteType.Against) {
            s.proposalVotes[pid].sharesAgainst += weight;
        } else {
            s.proposalVotes[pid].sharesAbstain += weight;
        }
        return oldPower - weight;
    }

    function _hasQuorumHook(uint256 pid) internal view override returns (bool) {
        BaseAllocationStorage storage s = _getStorage();
        uint256 forVotes = s.proposalVotes[pid].sharesFor;
        uint256 againstVotes = s.proposalVotes[pid].sharesAgainst;
        uint256 net = forVotes > againstVotes ? forVotes - againstVotes : 0;
        return net >= quorumShares;
    }

    function _beforeFinalizeVoteTallyHook() internal pure override returns (bool) {
        return true;
    }

    function _getRecipientAddressHook(uint256 pid) internal view override returns (address) {
        return _getStorage().proposals[pid].recipient;
    }
    function _convertVotesToShares(uint256 pid) internal view virtual override returns (uint256 sharesToMint) {
        BaseAllocationStorage storage s = _getStorage();
        ProposalVote storage votes = s.proposalVotes[pid];

        // Calculate net votes (For - Against)
        uint256 netVotes = votes.sharesFor > votes.sharesAgainst ? votes.sharesFor - votes.sharesAgainst : 0;

        if (netVotes == 0) return 0;

        // For now, return net votes directly as shares
        // In a real implementation, this would use the vault's conversion logic
        return netVotes;
    }
}
