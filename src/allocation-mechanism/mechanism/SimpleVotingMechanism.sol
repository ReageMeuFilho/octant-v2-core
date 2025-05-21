// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseAllocationMechanism } from "../BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleVotingMechanism is BaseAllocationMechanism {
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumShares,
        uint256 _timelockDelay
    ) BaseAllocationMechanism(_asset, _name, _symbol, _votingDelay, _votingPeriod, _quorumShares, _timelockDelay) {}

    function _beforeProposeHook(address proposer) internal view override returns (bool) {
        return votingPower[proposer] > 0;
    }

    function _validateProposalHook(uint256 pid) internal view override returns (bool) {
        return pid > 0 && pid <= _proposalIdCounter;
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
        if (choice == VoteType.For) {
            proposalVotes[pid].sharesFor += weight;
        } else if (choice == VoteType.Against) {
            proposalVotes[pid].sharesAgainst += weight;
        } else {
            proposalVotes[pid].sharesAbstain += weight;
        }
        return oldPower - weight;
    }

    function _hasQuorumHook(uint256 pid) internal view override returns (bool) {
        uint256 forVotes = proposalVotes[pid].sharesFor;
        uint256 againstVotes = proposalVotes[pid].sharesAgainst;
        uint256 net = forVotes > againstVotes ? forVotes - againstVotes : 0;
        return net >= quorumShares;
    }

    function _beforeFinalizeVoteTallyHook() internal pure override returns (bool) {
        return true;
    }

    function _convertVotesToShares(uint256 pid) internal view override returns (uint256) {
        uint256 forVotes = proposalVotes[pid].sharesFor;
        uint256 againstVotes = proposalVotes[pid].sharesAgainst;
        uint256 net = forVotes > againstVotes ? forVotes - againstVotes : 0;
        return net;
    }

    function _getRecipientAddressHook(uint256 pid) internal view override returns (address) {
        return proposals[pid].recipient;
    }

    function _requestDistributionHook(address, uint256) internal pure override returns (bool) {
        return true;
    }
}
