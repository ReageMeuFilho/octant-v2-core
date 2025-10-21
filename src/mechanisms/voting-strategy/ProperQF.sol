// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Proper Quadratic Funding (QF) math and tallying
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Incremental QF tallying utilities with alpha-weighted quadratic/linear funding.
 * @dev Provides storage isolation via deterministic slot, input validation helpers,
 *      and funding aggregation with well-defined rounding behavior.
 */
abstract contract ProperQF {
    using Math for uint256;

    // Custom Errors
    error ContributionMustBePositive();
    error VoteWeightMustBePositive();
    error VoteWeightOverflow(); // Keep for backward compatibility in tests
    error SquareRootTooLarge();
    error VoteWeightOutsideTolerance();
    error QuadraticSumUnderflow();
    error LinearSumUnderflow();
    error DenominatorMustBePositive();
    error AlphaMustBeLessOrEqualToOne();

    /// @notice Storage slot for ProperQF storage (EIP-1967-like deterministic slot)
    /// @dev Calculated as keccak256("proper.qf.storage") - 1 to minimize collision risk
    bytes32 private constant STORAGE_SLOT = bytes32(uint256(keccak256("proper.qf.storage")) - 1);

    /// @notice Per-project aggregated sums
    struct Project {
        /// @notice Sum of contributions for this project (asset base units)
        uint256 sumContributions; // Sum of contributions (Sum_j)
        /// @notice Sum of square roots of all contributions (dimensionless)
        uint256 sumSquareRoots; // Sum of square roots (S_j)
    }

    /// @notice Main storage struct containing all mutable state for ProperQF
    struct ProperQFStorage {
        /// @notice Mapping of project IDs to project data
        mapping(uint256 => Project) projects; // Mapping of project IDs to project data
        /// @notice Numerator for alpha (dimensionless; 1.0 = denominator)
        uint256 alphaNumerator; // Numerator for alpha (e.g., 6 for 0.6)
        /// @notice Denominator for alpha (must be > 0)
        uint256 alphaDenominator; // Denominator for alpha (e.g., 10 for 0.6)
        /// @notice Sum of all quadratic terms across projects (dimensionless squared weights)
        uint256 totalQuadraticSum; // Sum of all quadratic terms across projects
        /// @notice Sum of all linear contributions across projects (asset base units)
        uint256 totalLinearSum; // Sum of all linear terms across projects
        /// @notice Alpha-weighted total funding across all projects (asset base units)
        uint256 totalFunding; // Total funding across all projects - keep as uint256 for precision
    }

    /// @notice Emitted when alpha value is updated
    /// @param oldNumerator Previous alpha numerator
    /// @param oldDenominator Previous alpha denominator
    /// @param newNumerator New alpha numerator
    /// @param newDenominator New alpha denominator
    /// @notice Emitted when alpha parameters are updated
    /// @param oldNumerator Previous alpha numerator
    /// @param oldDenominator Previous alpha denominator
    /// @param newNumerator New alpha numerator
    /// @param newDenominator New alpha denominator
    event AlphaUpdated(uint256 oldNumerator, uint256 oldDenominator, uint256 newNumerator, uint256 newDenominator);

    /// @notice Constructor initializes default alpha values in storage
    constructor() {
        ProperQFStorage storage s = _getProperQFStorage();
        s.alphaNumerator = 10000; // Default alpha = 1.0 (10000/10000)
        s.alphaDenominator = 10000;
    }

    /// @notice Get the storage struct from the predefined slot
    /// @return s The storage struct containing all mutable state for ProperQF
    function _getProperQFStorage() internal pure returns (ProperQFStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /// @notice Public getter for projects mapping (delegating to storage)
    function projects(uint256 projectId) public view returns (Project memory) {
        return _getProperQFStorage().projects[projectId];
    }

    /// @notice Public getter for alphaNumerator (delegating to storage)
    function alphaNumerator() public view returns (uint256) {
        return _getProperQFStorage().alphaNumerator;
    }

    /// @notice Public getter for alphaDenominator (delegating to storage)
    function alphaDenominator() public view returns (uint256) {
        return _getProperQFStorage().alphaDenominator;
    }

    /// @notice Public getter for totalQuadraticSum (delegating to storage)
    function totalQuadraticSum() public view returns (uint256) {
        return _getProperQFStorage().totalQuadraticSum;
    }

    /// @notice Public getter for totalLinearSum (delegating to storage)
    function totalLinearSum() public view returns (uint256) {
        return _getProperQFStorage().totalLinearSum;
    }

    /// @notice Public getter for totalFunding (delegating to storage)
    function totalFunding() public view returns (uint256) {
        return _getProperQFStorage().totalFunding;
    }

    /**
     * @notice Process a vote and update the tally for the voting strategy
     * @dev Implements incremental update quadratic funding algorithm with validations:
     *      - contribution > 0 (asset base units)
     *      - voteWeight > 0 and voteWeight^2 == contribution within 10% tolerance
     * @param projectId The ID of the project to update
     * @param contribution The contribution to add (asset base units)
     * @param voteWeight The square root of contribution (dimensionless)
     */
    function _processVote(uint256 projectId, uint256 contribution, uint256 voteWeight) internal virtual {
        if (contribution == 0) revert ContributionMustBePositive();
        if (voteWeight == 0) revert VoteWeightMustBePositive();

        // Validate square root relationship with safe multiplication
        uint256 voteWeightSquared = voteWeight * voteWeight;
        if (voteWeightSquared / voteWeight != voteWeight) revert VoteWeightOverflow();
        if (voteWeightSquared > contribution) revert SquareRootTooLarge();

        // Validate square root approximation within 10% tolerance
        uint256 actualSqrt = contribution.sqrt();
        uint256 tolerance = actualSqrt / 10; // 10% tolerance
        // Only allow vote weight to be lower than actual sqrt, not higher
        if (voteWeight < actualSqrt - tolerance || voteWeight > actualSqrt) {
            revert VoteWeightOutsideTolerance();
        }

        _processVoteUnchecked(projectId, contribution, voteWeight);
    }

    /**
     * @notice Process vote without validation - for trusted callers who have already validated
     * @dev Skips input validation for gas optimization when caller guarantees correctness
     * @param projectId The ID of the project to update
     * @param contribution Contribution amount (asset base units)
     * @param voteWeight Vote weight (dimensionless; sqrt of contribution)
     */
    function _processVoteUnchecked(uint256 projectId, uint256 contribution, uint256 voteWeight) internal {
        ProperQFStorage storage s = _getProperQFStorage();
        Project memory project = s.projects[projectId];

        // Update project sums
        uint256 newSumSquareRoots = project.sumSquareRoots + voteWeight;
        uint256 newSumContributions = project.sumContributions + contribution;

        // Calculate quadratic funding - no overflow risk with uint256
        uint256 oldQuadraticFunding = project.sumSquareRoots * project.sumSquareRoots;
        uint256 newQuadraticFunding = newSumSquareRoots * newSumSquareRoots;

        // Update global sums with underflow protection (keep checked for safety)
        if (s.totalQuadraticSum < oldQuadraticFunding) revert QuadraticSumUnderflow();
        if (s.totalLinearSum < project.sumContributions) revert LinearSumUnderflow();

        // Update global sums
        uint256 newTotalQuadraticSum = s.totalQuadraticSum - oldQuadraticFunding + newQuadraticFunding;
        uint256 newTotalLinearSum = s.totalLinearSum - project.sumContributions + newSumContributions;

        s.totalQuadraticSum = newTotalQuadraticSum;
        s.totalLinearSum = newTotalLinearSum;

        // Update project state - batch storage writes
        project.sumSquareRoots = newSumSquareRoots;
        project.sumContributions = newSumContributions;

        s.projects[projectId] = project;

        // Update total funding after vote processing
        s.totalFunding = _calculateWeightedTotalFunding();
    }

    /**
     * @notice Calculate alpha-weighted total funding across all projects
     * @dev Rounding: per-project integer division makes sum(project funding) ≤ totalFunding.
     *      Discrepancy ε is bounded: 0 ≤ ε ≤ 2(|P|-1) where |P| is number of projects.
     *      This dust ensures no over-allocation; all funds are still fully distributed.
     * @return totalFunding_ Weighted total funding across all projects (asset base units)
     */
    function _calculateWeightedTotalFunding() internal view returns (uint256) {
        ProperQFStorage storage s = _getProperQFStorage();
        // Calculate weighted funding
        uint256 weightedQuadratic = (s.totalQuadraticSum * s.alphaNumerator) / s.alphaDenominator;
        uint256 weightedLinear = (s.totalLinearSum * (s.alphaDenominator - s.alphaNumerator)) / s.alphaDenominator;
        return weightedQuadratic + weightedLinear;
    }

    /**
     * @notice Return current funding metrics for a specific project
     * @dev Aggregates sums and computes alpha-weighted components on-demand.
     * @param projectId The ID of the project to tally
     * @return sumContributions Total sum of contributions (asset base units)
     * @return sumSquareRoots Sum of square roots of contributions (dimensionless)
     * @return quadraticFunding Alpha-weighted quadratic funding: ⌊α × S_j²⌋ (asset base units)
     * @return linearFunding Alpha-weighted linear funding: ⌊(1-α) × Sum_j⌋ (asset base units)
     * @dev Rounding: sum of per-project funding ≤ totalFunding() with small bounded dust ε.
     */
    function getTally(
        uint256 projectId
    )
        public
        view
        returns (uint256 sumContributions, uint256 sumSquareRoots, uint256 quadraticFunding, uint256 linearFunding)
    {
        // Retrieve the project data from storage
        ProperQFStorage storage s = _getProperQFStorage();
        Project storage project = s.projects[projectId];

        // Calculate quadratic funding on-demand as square of sum of square roots
        uint256 rawQuadraticFunding = project.sumSquareRoots * project.sumSquareRoots;

        // Return all relevant metrics for the project
        return (
            project.sumContributions, // Total contributions
            project.sumSquareRoots, // Sum of square roots
            (rawQuadraticFunding * s.alphaNumerator) / s.alphaDenominator, // Alpha-weighted quadratic funding
            (project.sumContributions * (s.alphaDenominator - s.alphaNumerator)) / s.alphaDenominator // Alpha-weighted linear funding (1-α) × Sum_j
        );
    }

    /**
     * @notice Set alpha parameter determining ratio between quadratic and linear funding
     * @param newNumerator Numerator of new alpha (0 ≤ numerator ≤ denominator)
     * @param newDenominator Denominator of new alpha (> 0)
     */
    function _setAlpha(uint256 newNumerator, uint256 newDenominator) internal {
        // Input validation
        if (newDenominator == 0) revert DenominatorMustBePositive();
        if (newNumerator > newDenominator) revert AlphaMustBeLessOrEqualToOne();

        ProperQFStorage storage s = _getProperQFStorage();

        // Store old values for event emission
        uint256 oldNumerator = s.alphaNumerator;
        uint256 oldDenominator = s.alphaDenominator;

        // Update state - no SafeCast needed with uint256
        s.alphaNumerator = newNumerator;
        s.alphaDenominator = newDenominator;

        // Recalculate total funding with new alpha
        s.totalFunding = _calculateWeightedTotalFunding();

        // Emit event
        emit AlphaUpdated(oldNumerator, oldDenominator, newNumerator, newDenominator);
    }

    /**
     * @notice Get current alpha ratio components
     * @return numerator Current alpha numerator
     * @return denominator Current alpha denominator
     */
    function getAlpha() public view returns (uint256, uint256) {
        ProperQFStorage storage s = _getProperQFStorage();
        return (s.alphaNumerator, s.alphaDenominator);
    }

    /**
     * @notice Calculate optimal alpha for 1:1 shares-to-assets ratio given fixed matching pool amount
     * @dev Solve α where: α × totalQuadraticSum + (1−α) × totalLinearSum = totalUserDeposits + matchingPoolAmount
     * @param matchingPoolAmount Matching pool amount (asset base units)
     * @param quadraticSum Total quadratic sum across all proposals (dimensionless)
     * @param linearSum Total linear sum across all proposals (asset base units)
     * @param totalUserDeposits Total user deposits in the mechanism (asset base units)
     * @return optimalAlphaNumerator Calculated alpha numerator
     * @return optimalAlphaDenominator Calculated alpha denominator
     */
    function _calculateOptimalAlpha(
        uint256 matchingPoolAmount,
        uint256 quadraticSum,
        uint256 linearSum,
        uint256 totalUserDeposits
    ) internal pure returns (uint256 optimalAlphaNumerator, uint256 optimalAlphaDenominator) {
        // Handle edge cases
        if (quadraticSum <= linearSum) {
            // No quadratic funding benefit, set alpha to 0
            optimalAlphaNumerator = 0;
            optimalAlphaDenominator = 1;
            return (optimalAlphaNumerator, optimalAlphaDenominator);
        }

        uint256 totalAssetsAvailable = totalUserDeposits + matchingPoolAmount;
        uint256 quadraticAdvantage = quadraticSum - linearSum;

        // We want: α × quadraticSum + (1-α) × linearSum = totalAssetsAvailable
        // Solving for α: α × (quadraticSum - linearSum) = totalAssetsAvailable - linearSum
        // Therefore: α = (totalAssetsAvailable - linearSum) / (quadraticSum - linearSum)

        if (totalAssetsAvailable <= linearSum) {
            // Not enough assets even for linear funding, set alpha to 0
            optimalAlphaNumerator = 0;
            optimalAlphaDenominator = 1;
        } else {
            uint256 numerator = totalAssetsAvailable - linearSum;

            if (numerator >= quadraticAdvantage) {
                // Enough assets for full quadratic funding
                optimalAlphaNumerator = 1;
                optimalAlphaDenominator = 1;
            } else {
                // Calculate fractional alpha
                optimalAlphaNumerator = numerator;
                optimalAlphaDenominator = quadraticAdvantage;
            }
        }
    }
}
