// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseAllocationMechanism, AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { ProperQF } from "src/mechanisms/voting-strategy/ProperQF.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Quadratic Voting Mechanism
/// @notice Implements quadratic funding for proposal allocation using the ProperQF strategy
/// @dev Follows the Yearn V3 pattern with minimal implementation surface
contract QuadraticVotingMechanism is BaseAllocationMechanism, ProperQF {
    // Custom Errors
    error AlphaMustBeLEQOne();
    error AlphaDenominatorMustBePositive();
    error ZeroAddressCannotPropose();
    error OnlyForVotesSupported();
    error InsufficientVotingPowerForQuadraticCost();
    error AlreadyVoted(address voter, uint256 pid);

    /// @notice Total voting power distributed across all proposals

    /// @notice Mapping to track if a voter has voted on a proposal
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    constructor(
        address _implementation,
        AllocationConfig memory _config,
        uint256 _alphaNumerator,
        uint256 _alphaDenominator
    ) BaseAllocationMechanism(_implementation, _config) {
        if (_alphaNumerator > _alphaDenominator) revert AlphaMustBeLEQOne();
        if (_alphaDenominator == 0) revert AlphaDenominatorMustBePositive();

        _setAlpha(_alphaNumerator, _alphaDenominator);
    }

    /// @notice Only keeper or management can propose
    function _beforeProposeHook(address proposer) internal view override returns (bool) {
        // Get keeper and management addresses from TokenizedAllocationMechanism
        address keeper = _tokenizedAllocation().keeper();
        address management = _tokenizedAllocation().management();

        // Allow if proposer is either keeper or management
        return proposer == keeper || proposer == management;
    }

    /// @notice Validate proposal ID exists
    function _validateProposalHook(uint256 pid) internal view override returns (bool) {
        return _proposalExists(pid);
    }

    /// @notice Allow all users to register (can be restricted in derived contracts)
    function _beforeSignupHook(address) internal pure override returns (bool) {
        return true;
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

    /// @notice Process vote using quadratic funding algorithm
    /// @dev The cost of voting is quadratic: to cast `weight` votes, you pay `weight^2` voting power
    function _processVoteHook(
        uint256 pid,
        address voter,
        TokenizedAllocationMechanism.VoteType choice,
        uint256 weight,
        uint256 oldPower
    ) internal override returns (uint256) {
        if (choice != TokenizedAllocationMechanism.VoteType.For) revert OnlyForVotesSupported();

        // Check if voter has already voted on this proposal
        if (hasVoted[pid][voter]) revert AlreadyVoted(voter, pid);

        // Quadratic cost: to vote with weight W, you pay W^2 voting power
        uint256 quadraticCost = weight * weight;

        if (quadraticCost > oldPower) revert InsufficientVotingPowerForQuadraticCost();

        // Use ProperQF's unchecked vote processing since we control the inputs
        // contribution = quadratic cost, voteWeight = actual vote weight
        // We know: quadraticCost = weight^2, so sqrt(quadraticCost) = weight (perfect square root relationship)
        _processVoteUnchecked(pid, quadraticCost, weight);

        // Mark that voter has voted on this proposal
        hasVoted[pid][voter] = true;

        // Return remaining voting power after quadratic cost
        return oldPower - quadraticCost;
    }

    /// @notice Check quorum based on quadratic funding threshold
    function _hasQuorumHook(uint256 pid) internal view override returns (bool) {
        // Get the project's funding metrics
        // getTally() returns: alpha-weighted quadratic funding + alpha-weighted linear funding
        (, , uint256 quadraticFunding, uint256 linearFunding) = getTally(pid);

        // Calculate total funding: both components are already alpha-weighted
        // F_j = α × (sum_sqrt)² + (1-α) × sum_contributions
        uint256 projectTotalFunding = quadraticFunding + linearFunding;

        // Project meets quorum if it has minimum funding threshold
        return projectTotalFunding >= _getQuorumShares();
    }

    /// @notice Convert quadratic funding to shares
    function _convertVotesToShares(uint256 pid) internal view override returns (uint256) {
        // Get project funding metrics
        // getTally() returns: alpha-weighted quadratic funding + alpha-weighted linear funding
        (, , uint256 quadraticFunding, uint256 linearFunding) = getTally(pid);

        // Calculate total funding: both components are already alpha-weighted
        // F_j = α × (sum_sqrt)² + (1-α) × sum_contributions
        return quadraticFunding + linearFunding;
    }

    /// @notice Allow finalization once voting period ends
    function _beforeFinalizeVoteTallyHook() internal pure override returns (bool) {
        return true;
    }

    /// @notice Get recipient address for proposal
    function _getRecipientAddressHook(uint256 pid) internal view override returns (address) {
        TokenizedAllocationMechanism.Proposal memory proposal = _getProposal(pid);
        if (proposal.recipient == address(0)) revert TokenizedAllocationMechanism.InvalidRecipient(proposal.recipient);
        return proposal.recipient;
    }

    /// @notice Handle custom share distribution - returns false to use default minting
    /// @return handled False to indicate default minting should be used
    function _requestCustomDistributionHook(address, uint256) internal pure override returns (bool) {
        // Return false to indicate we want to use the default share minting in TokenizedAllocationMechanism
        // This allows the base implementation to handle the minting via _mint()
        return false;
    }

    /// @dev Get available withdraw limit for share owner with global timelock and grace period enforcement
    /// @param shareOwner Address attempting to withdraw shares
    /// @return availableLimit Amount of assets that can be withdrawn (0 if timelock active or expired)
    function _availableWithdrawLimit(address shareOwner) internal view override returns (uint256) {
        // Get the global redemption start time
        uint256 globalRedemptionStart = _getGlobalRedemptionStart();

        // If no global redemption time set, no withdrawals allowed
        if (globalRedemptionStart == 0) {
            return 0;
        }

        // Check if still in timelock period
        if (block.timestamp < globalRedemptionStart) {
            return 0; // Cannot withdraw during timelock
        }

        // Check if global grace period has expired
        uint256 gracePeriod = _getGracePeriod();
        if (block.timestamp > globalRedemptionStart + gracePeriod) {
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

    /// @notice Calculate total assets including matching pool + user deposits for finalization
    /// @dev This snapshots the total asset balance in the contract during finalize
    /// @return Total assets available for allocation (matching pool + user signup deposits)
    function _calculateTotalAssetsHook() internal view override returns (uint256) {
        // Return current asset balance of the contract
        // This includes both:
        // 1. Matching pool funds (pre-funded in setUp)
        // 2. User deposits from signups
        return asset.balanceOf(address(this));
    }

    /// @notice Get project funding breakdown for a proposal
    /// @param pid Proposal ID
    /// @return sumContributions Total contribution amounts
    /// @return sumSquareRoots Sum of square roots for quadratic calculation
    /// @return quadraticFunding Quadratic funding component
    /// @return linearFunding Linear funding component
    function getProposalFunding(
        uint256 pid
    )
        external
        view
        returns (uint256 sumContributions, uint256 sumSquareRoots, uint256 quadraticFunding, uint256 linearFunding)
    {
        if (!_validateProposalHook(pid)) revert TokenizedAllocationMechanism.InvalidProposal(pid);
        return getTally(pid);
    }

    /// @notice Set the alpha parameter for quadratic vs linear funding weighting
    /// @param newNumerator The numerator of the new alpha value
    /// @param newDenominator The denominator of the new alpha value
    /// @dev Alpha determines the ratio: F_j = α × (sum_sqrt)² + (1-α) × sum_contributions
    /// @dev Only callable by owner (inherited from BaseAllocationMechanism via TokenizedAllocationMechanism)
    function setAlpha(uint256 newNumerator, uint256 newDenominator) external {
        // Access control: only owner can modify alpha
        require(_tokenizedAllocation().owner() == msg.sender, "Only owner can set alpha");

        // Validate alpha constraints
        if (newNumerator > newDenominator) revert AlphaMustBeLEQOne();
        if (newDenominator == 0) revert AlphaDenominatorMustBePositive();

        // Update alpha using ProperQF's internal function
        _setAlpha(newNumerator, newDenominator);
    }

    /// @notice Calculate optimal alpha for 1:1 shares-to-assets ratio given fixed matching pool amount
    /// @param matchingPoolAmount Fixed amount of matching funds available
    /// @param totalUserDeposits Total user deposits in the mechanism
    /// @return optimalAlphaNumerator Calculated alpha numerator
    /// @return optimalAlphaDenominator Calculated alpha denominator
    /// @dev Uses current mechanism state for quadratic and linear sums
    function calculateOptimalAlpha(
        uint256 matchingPoolAmount,
        uint256 totalUserDeposits
    ) external view returns (uint256 optimalAlphaNumerator, uint256 optimalAlphaDenominator) {
        return _calculateOptimalAlpha(matchingPoolAmount, totalQuadraticSum(), totalLinearSum(), totalUserDeposits);
    }

    /// @notice Reject ETH deposits to prevent permanent fund loss
    /// @dev Override BaseAllocationMechanism's receive() to prevent accidental ETH deposits
    receive() external payable override {
        revert("ETH not supported - use ERC20 tokens only");
    }
}
