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
    constructor(
        address _implementation,
        AllocationConfig memory _config
    ) BaseAllocationMechanism(_implementation, _config) {}

    // ---------- Internal Hook Implementations ----------

    /// @dev Allow all users to sign up
    function _beforeSignupHook(address) internal pure override returns (bool) {
        return true;
    }

    /// @dev Only allow users with voting power to propose
    function _beforeProposeHook(address proposer) internal view override returns (bool) {
        return _getVotingPower(proposer) > 0;
    }

    /// @notice Calculate voting power by converting from asset decimals to 18 decimals
    function _getVotingPowerHook(address, uint256 deposit) internal view override returns (uint256) {
        // Get asset decimals
        uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();

        // Convert to 18 decimals for voting power
        if (assetDecimals == 18) {
            return deposit;
        } else if (assetDecimals < 18) {
            // Scale up: multiply by 10^(18 - assetDecimals)
            uint256 scaleFactor = 10 ** (18 - assetDecimals);
            return deposit * scaleFactor;
        } else {
            // Scale down: divide by 10^(assetDecimals - 18)
            uint256 scaleFactor = 10 ** (assetDecimals - 18);
            return deposit / scaleFactor;
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
        // Get current vote tallies
        VoteTally storage tally = voteTallies[pid];
        uint256 sharesFor = tally.sharesFor;
        uint256 sharesAgainst = tally.sharesAgainst;
        uint256 sharesAbstain = tally.sharesAbstain;

        // Update based on vote choice
        if (choice == TokenizedAllocationMechanism.VoteType.For) {
            sharesFor += weight;
        } else if (choice == TokenizedAllocationMechanism.VoteType.Against) {
            sharesAgainst += weight;
        } else {
            sharesAbstain += weight;
        }

        // Update storage directly
        tally.sharesFor = sharesFor;
        tally.sharesAgainst = sharesAgainst;
        tally.sharesAbstain = sharesAbstain;

        // Return reduced voting power
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

        // Calculate net votes (For - Against)
        uint256 netVotes = forVotes > againstVotes ? forVotes - againstVotes : 0;

        if (netVotes == 0) return 0;

        // For now, return net votes directly as shares
        // In a real implementation, this would use the vault's conversion logic
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
    /// @return handled False to indicate default minting should be used
    function _requestCustomDistributionHook(address, uint256) internal pure override returns (bool) {
        // Return false to indicate we want to use the default share minting in TokenizedAllocationMechanism
        // This allows the base implementation to handle the minting via _mint()
        return false;
    }

    /// @dev Get available withdraw limit for share owner with timelock and grace period enforcement
    /// @param shareOwner Address attempting to withdraw shares
    /// @return availableLimit Amount of assets that can be withdrawn (0 if timelock active or expired)
    function _availableWithdrawLimit(address shareOwner) internal view override returns (uint256) {
        // Get the redeemable time for this share owner
        uint256 redeemableTime = _getRedeemableAfter(shareOwner);

        // If no redeemable time set, allow unlimited withdrawal (shouldn't happen in normal flow)
        if (redeemableTime == 0) {
            return type(uint256).max;
        }

        // Check if still in timelock period
        if (block.timestamp < redeemableTime) {
            return 0; // Cannot withdraw during timelock
        }

        // Check if grace period has expired
        uint256 gracePeriod = _getGracePeriod();
        if (block.timestamp > redeemableTime + gracePeriod) {
            return 0; // Cannot withdraw after grace period expires
        }

        // Within valid redemption window - return max assets this user can withdraw
        // Convert share balance to assets using current exchange rate
        uint256 shareBalance = _tokenizedAllocation().balanceOf(shareOwner);
        if (shareBalance == 0) {
            return 0;
        }

        // Convert shares to assets - this gives the maximum assets withdrawable
        return _tokenizedAllocation().convertToAssets(shareBalance);
    }

    /// @notice Calculate total assets for simple voting (just the contract balance)
    function _calculateTotalAssetsHook() internal view override returns (uint256) {
        // For simple voting, total assets is just the actual token balance
        // This reflects all user deposits without any matching pools
        return asset.balanceOf(address(this));
    }
}
