// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseAllocationMechanism, AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Simple Voting Mechanism with Share Distribution
/// @notice Implements a basic 1:1 voting mechanism where net votes directly convert to shares
/// @dev Follows the Yearn V3 pattern with minimal implementation surface
contract SimpleVotingMechanism is BaseAllocationMechanism {
    /// @notice Vote tally storage for simple voting
    struct VoteTally {
        uint256 sharesFor;
        uint256 sharesAgainst;
        uint256 sharesAbstain;
    }

    /// @notice Mapping of proposal ID to vote tallies
    mapping(uint256 => VoteTally) public voteTallies;

    /// @notice Mapping to track which users have already signed up to prevent multiple registrations
    mapping(address => bool) public hasSignedUp;

    constructor(
        address _implementation,
        AllocationConfig memory _config
    ) BaseAllocationMechanism(_implementation, _config) {}

    // ---------- Internal Hook Implementations ----------

    /// @dev Allow users to sign up only if they haven't already registered
    /// @dev Maintains explicit tracking to prevent re-registration even after voting power is spent
    function _beforeSignupHook(address user) internal override returns (bool) {
        if (hasSignedUp[user]) {
            return false;
        }
        hasSignedUp[user] = true;
        return true;
    }

    /// @dev Only allow users with voting power to propose
    function _beforeProposeHook(address proposer) internal view override returns (bool) {
        return _getVotingPower(proposer) > 0;
    }

    /// @notice Calculate voting power by converting from asset decimals to 18 decimals
    function _getVotingPowerHook(address, uint256 deposit) internal view override returns (uint256) {
        uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
        if (assetDecimals == 18) {
            return deposit;
        } else if (assetDecimals < 18) {
            return deposit * 10 ** (18 - assetDecimals);
        } else {
            return deposit / 10 ** (assetDecimals - 18);
        }
    }

    /// @dev Validate proposal exists
    function _validateProposalHook(uint256 pid) internal view override returns (bool) {
        return _proposalExists(pid);
    }

    /// @dev Process vote by updating tallies and reducing voting power
    function _processVoteHook(
        uint256 pid,
        address,
        TokenizedAllocationMechanism.VoteType choice,
        uint256 weight,
        uint256 oldPower
    ) internal override returns (uint256) {
        VoteTally storage tally = voteTallies[pid];
        uint256 sharesFor = tally.sharesFor;
        uint256 sharesAgainst = tally.sharesAgainst;
        uint256 sharesAbstain = tally.sharesAbstain;

        if (choice == TokenizedAllocationMechanism.VoteType.For) {
            sharesFor += weight;
        } else if (choice == TokenizedAllocationMechanism.VoteType.Against) {
            sharesAgainst += weight;
        } else {
            sharesAbstain += weight;
        }

        tally.sharesFor = sharesFor;
        tally.sharesAgainst = sharesAgainst;
        tally.sharesAbstain = sharesAbstain;

        return oldPower - weight;
    }

    /// @dev Check if proposal has enough net votes for quorum
    function _hasQuorumHook(uint256 pid) internal view override returns (bool) {
        VoteTally storage tally = voteTallies[pid];
        uint256 forVotes = tally.sharesFor;
        uint256 againstVotes = tally.sharesAgainst;
        uint256 net = forVotes > againstVotes ? forVotes - againstVotes : 0;
        return net >= _getQuorumShares();
    }

    /// @dev Simple net vote to shares conversion
    function _convertVotesToShares(uint256 pid) internal view override returns (uint256 sharesToMint) {
        VoteTally storage tally = voteTallies[pid];
        uint256 forVotes = tally.sharesFor;
        uint256 againstVotes = tally.sharesAgainst;
        uint256 netVotes = forVotes > againstVotes ? forVotes - againstVotes : 0;
        if (netVotes == 0) return 0;
        return netVotes;
    }

    /// @dev Allow finalization
    function _beforeFinalizeVoteTallyHook() internal pure override returns (bool) {
        return true;
    }

    /// @dev Get recipient address from proposal
    function _getRecipientAddressHook(uint256 pid) internal view override returns (address) {
        TokenizedAllocationMechanism.Proposal memory proposal = _getProposal(pid);
        return proposal.recipient;
    }

    /// @dev Handle custom share distribution - returns false to use default minting
    function _requestCustomDistributionHook(
        address,
        uint256
    ) internal pure override returns (bool handled, uint256 assetsTransferred) {
        return (false, 0);
    }

    /// @dev Get available withdraw limit for share owner with timelock and grace period enforcement
    function _availableWithdrawLimit(address shareOwner) internal view override returns (uint256) {
        uint256 redeemableTime = _getGlobalRedemptionStart();
        if (redeemableTime == 0) return 0;
        if (block.timestamp < redeemableTime) return 0;
        uint256 gracePeriod = _getGracePeriod();
        if (block.timestamp > redeemableTime + gracePeriod) return 0;
        uint256 shareBalance = _tokenizedAllocation().balanceOf(shareOwner);
        if (shareBalance == 0) return 0;
        return _tokenizedAllocation().convertToAssets(shareBalance);
    }

    /// @notice Calculate total assets for simple voting (just the contract balance)
    function _calculateTotalAssetsHook() internal view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice Reject ETH deposits to prevent permanent fund loss
    receive() external payable override {
        revert("ETH not supported - use ERC20 tokens only");
    }
}
