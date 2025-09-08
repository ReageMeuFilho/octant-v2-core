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
        _setAlpha(_alphaNumerator, _alphaDenominator);
    }

    /// @notice Only keeper or management can propose
    function _beforeProposeHook(address proposer) internal view virtual override returns (bool) {
        if (proposer == address(0)) revert ZeroAddressCannotPropose();

        // Get keeper and management addresses from TokenizedAllocationMechanism
        address keeper = _tokenizedAllocation().keeper();
        address management = _tokenizedAllocation().management();

        // Allow if proposer is either keeper or management
        return proposer == keeper || proposer == management;
    }

    /// @notice Validate proposal ID exists
    function _validateProposalHook(uint256 pid) internal view virtual override returns (bool) {
        return _proposalExists(pid);
    }

    /// @notice Allow all users to register, including multiple signups (can be restricted in derived contracts)
    /// @dev Returns true for all users, allowing unlimited signups to accumulate voting power
    /// @dev IMPORTANT: While technically possible, pure quadratic voting mechanisms should restrict users
    /// @dev to single signups to prevent double-spending of vote credits. In QV, users receive a fixed
    /// @dev allocation of vote credits and should only be able to claim them once. Multiple signups may
    /// @dev be appropriate for quadratic funding (QF) variants where users contribute their own funds
    /// @dev to increase voting power, but quadratic voting (QV) variants should override this hook to
    /// @dev prevent re-registration and double-spending of allocated vote credits.
    function _beforeSignupHook(address) internal virtual override returns (bool) {
        return true;
    }

    /// @notice Calculate voting power by converting from asset decimals to 18 decimals
    function _getVotingPowerHook(address, uint256 deposit) internal view virtual override returns (uint256) {
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

    /// @dev Normalize token amount to 18 decimals (matches voting power normalization)
    function _normalizeToDecimals(uint256 amount, uint8 assetDecimals) internal pure returns (uint256) {
        if (assetDecimals == 18) {
            return amount;
        } else if (assetDecimals < 18) {
            // Scale up: multiply by 10^(18 - assetDecimals)
            uint256 scaleFactor = 10 ** (18 - assetDecimals);
            return amount * scaleFactor;
        } else {
            // Scale down: divide by 10^(assetDecimals - 18)
            uint256 scaleFactor = 10 ** (assetDecimals - 18);
            return amount / scaleFactor;
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
    ) internal virtual override returns (uint256) {
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
    function _hasQuorumHook(uint256 pid) internal view virtual override returns (bool) {
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
    function _convertVotesToShares(uint256 pid) internal view virtual override returns (uint256) {
        // Get project funding metrics
        // getTally() returns: alpha-weighted quadratic funding + alpha-weighted linear funding
        (, , uint256 quadraticFunding, uint256 linearFunding) = getTally(pid);

        // Calculate total funding: both components are already alpha-weighted
        // F_j = α × (sum_sqrt)² + (1-α) × sum_contributions
        return quadraticFunding + linearFunding;
    }

    /// @notice Allow finalization once voting period ends
    function _beforeFinalizeVoteTallyHook() internal pure virtual override returns (bool) {
        return true;
    }

    /// @notice Get recipient address for proposal
    function _getRecipientAddressHook(uint256 pid) internal view virtual override returns (address) {
        TokenizedAllocationMechanism.Proposal memory proposal = _getProposal(pid);
        if (proposal.recipient == address(0)) revert TokenizedAllocationMechanism.InvalidRecipient(proposal.recipient);
        return proposal.recipient;
    }

    /// @notice Handle custom share distribution - returns false to use default minting
    /// @return handled False to indicate default minting should be used
    /// @return assetsTransferred 0 since no custom distribution is performed
    function _requestCustomDistributionHook(
        address,
        uint256
    ) internal pure virtual override returns (bool handled, uint256 assetsTransferred) {
        // Return false to indicate we want to use the default share minting in TokenizedAllocationMechanism
        // This allows the base implementation to handle the minting via _mint()
        return (false, 0);
    }

    // Note: _availableWithdrawLimit is now inherited from BaseAllocationMechanism
    // The default implementation enforces timelock and grace period boundaries

    /// @notice Calculate total assets including matching pool + user deposits for finalization
    /// @dev This snapshots the total asset balance in the contract during finalize
    /// @return Total assets available for allocation (matching pool + user signup deposits)
    function _calculateTotalAssetsHook() internal view virtual override returns (uint256) {
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

        // Return zero funding for cancelled proposals
        if (_tokenizedAllocation().state(pid) == TokenizedAllocationMechanism.ProposalState.Canceled) {
            return (0, 0, 0, 0);
        }

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

        // Update alpha using ProperQF's internal function (validates constraints internally)
        _setAlpha(newNumerator, newDenominator);
    }

    /// @notice Calculate optimal alpha for 1:1 shares-to-assets ratio given fixed matching pool amount
    /// @param matchingPoolAmount Fixed amount of matching funds available (in token's native decimals)
    /// @param totalUserDeposits Total user deposits in the mechanism (in token's native decimals)
    /// @return optimalAlphaNumerator Calculated alpha numerator
    /// @return optimalAlphaDenominator Calculated alpha denominator
    /// @dev Internally normalizes amounts to 18 decimals to match quadratic/linear sum calculations
    function calculateOptimalAlpha(
        uint256 matchingPoolAmount,
        uint256 totalUserDeposits
    ) external view returns (uint256 optimalAlphaNumerator, uint256 optimalAlphaDenominator) {
        // Get asset decimals to normalize amounts
        uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();

        // Normalize both amounts to 18 decimals to match quadratic/linear sums
        uint256 normalizedMatchingPool = _normalizeToDecimals(matchingPoolAmount, assetDecimals);
        uint256 normalizedUserDeposits = _normalizeToDecimals(totalUserDeposits, assetDecimals);

        return
            _calculateOptimalAlpha(
                normalizedMatchingPool,
                totalQuadraticSum(),
                totalLinearSum(),
                normalizedUserDeposits
            );
    }

    /// @notice Reject ETH deposits to prevent permanent fund loss
    /// @dev Override BaseAllocationMechanism's receive() to prevent accidental ETH deposits
    receive() external payable override {
        revert("ETH not supported - use ERC20 tokens only");
    }
}
