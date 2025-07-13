// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract ProperQF {
    using Math for uint256;
    using SafeCast for uint256;

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

    /// @notice Storage slot for allocation mechanism data (EIP-1967 pattern)
    bytes32 private constant STORAGE_SLOT = bytes32(uint256(keccak256("proper.qf.storage")) - 1);

    struct Project {
        uint128 sumContributions; // Sum of contributions (Sum_j) - up to ~340 trillion with 18 decimals
        uint128 sumSquareRoots; // Sum of square roots (S_j) - up to ~340 trillion with 18 decimals
        uint128 quadraticFunding; // Quadratic term (F_quad_j) - up to ~340 trillion with 18 decimals
        uint128 linearFunding; // Linear term (F_linear_j) - up to ~340 trillion with 18 decimals
    }

    /// @notice Main storage struct containing all mutable state for ProperQF
    struct ProperQFStorage {
        mapping(uint256 => Project) projects; // Mapping of project IDs to project data
        uint128 alphaNumerator; // Numerator for alpha (e.g., 6 for 0.6) - max 340 trillion
        uint128 alphaDenominator; // Denominator for alpha (e.g., 10 for 0.6) - max 340 trillion
        uint128 totalQuadraticSum; // Sum of all quadratic terms across projects
        uint128 totalLinearSum; // Sum of all linear terms across projects
        uint256 totalFunding; // Total funding across all projects - keep as uint256 for precision
    }

    /// @dev Event emitted when alpha value is updated
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
        return uint256(_getProperQFStorage().alphaNumerator);
    }

    /// @notice Public getter for alphaDenominator (delegating to storage)
    function alphaDenominator() public view returns (uint256) {
        return uint256(_getProperQFStorage().alphaDenominator);
    }

    /// @notice Public getter for totalQuadraticSum (delegating to storage)
    function totalQuadraticSum() public view returns (uint256) {
        return uint256(_getProperQFStorage().totalQuadraticSum);
    }

    /// @notice Public getter for totalLinearSum (delegating to storage)
    function totalLinearSum() public view returns (uint256) {
        return uint256(_getProperQFStorage().totalLinearSum);
    }

    /// @notice Public getter for totalFunding (delegating to storage)
    function totalFunding() public view returns (uint256) {
        return _getProperQFStorage().totalFunding;
    }

    /**
     * @notice This function is used to process a vote and update the tally for the voting strategy
     * @dev Implements incremental update quadratic funding algorithm
     * @param projectId The ID of the project to update.
     * @param contribution The new contribution to add.
     */
    function _processVote(uint256 projectId, uint256 contribution, uint256 voteWeight) internal virtual {
        if (contribution == 0) revert ContributionMustBePositive();
        if (voteWeight == 0) revert VoteWeightMustBePositive();

        // Validate square root relationship with safe multiplication
        uint256 voteWeightSquared = voteWeight * voteWeight;
        if (voteWeightSquared / voteWeight != voteWeight) revert VoteWeightOverflow();
        if (voteWeightSquared > contribution) revert SquareRootTooLarge();

        // Validate square root approximation within 10% tolerance
        uint256 actualSqrt = _sqrt(contribution);
        uint256 tolerance = actualSqrt / 10; // 10% tolerance
        // Only allow vote weight to be lower than actual sqrt, not higher
        if (voteWeight < actualSqrt - tolerance || voteWeight > actualSqrt) {
            revert VoteWeightOutsideTolerance();
        }

        _processVoteUnchecked(projectId, contribution, voteWeight);
    }

    /**
     * @notice Process vote without validation - for trusted callers who have already validated
     * @dev Skips all input validation for gas optimization when caller guarantees correctness
     * @param projectId The ID of the project to update
     * @param contribution The contribution amount (must equal voteWeight^2 for quadratic funding)
     * @param voteWeight The vote weight (square root of contribution)
     */
    function _processVoteUnchecked(uint256 projectId, uint256 contribution, uint256 voteWeight) internal {
        ProperQFStorage storage s = _getProperQFStorage();
        Project storage project = s.projects[projectId];

        // Update project sums using SafeCast for overflow protection
        uint128 newSumSquareRoots = project.sumSquareRoots + voteWeight.toUint128();
        uint128 newSumContributions = project.sumContributions + contribution.toUint128();

        // Check for overflow on quadratic calculation and cast safely
        uint256 quadraticResult = uint256(newSumSquareRoots) * uint256(newSumSquareRoots);
        uint128 newQuadraticFunding = quadraticResult.toUint128();

        // Update global sums with underflow protection (keep checked for safety)
        if (s.totalQuadraticSum < project.quadraticFunding) revert QuadraticSumUnderflow();
        if (s.totalLinearSum < project.linearFunding) revert LinearSumUnderflow();

        // Update global sums with SafeCast overflow protection
        uint256 newTotalQuadraticSum = uint256(s.totalQuadraticSum) -
            uint256(project.quadraticFunding) +
            uint256(newQuadraticFunding);
        uint256 newTotalLinearSum = uint256(s.totalLinearSum) -
            uint256(project.linearFunding) +
            uint256(newSumContributions);

        s.totalQuadraticSum = newTotalQuadraticSum.toUint128();
        s.totalLinearSum = newTotalLinearSum.toUint128();

        // Update project state - batch storage writes
        project.sumSquareRoots = newSumSquareRoots;
        project.sumContributions = newSumContributions;
        project.quadraticFunding = newQuadraticFunding;
        project.linearFunding = newSumContributions;

        // Update total funding after vote processing
        s.totalFunding = _calculateWeightedTotalFunding();
    }

    /**
     * @dev Calculate weighted total funding using alpha parameter
     * @return The weighted total funding across all projects
     */
    function _calculateWeightedTotalFunding() internal view returns (uint256) {
        ProperQFStorage storage s = _getProperQFStorage();
        // Convert to uint256 for calculation to prevent overflow
        uint256 weightedQuadratic = (uint256(s.totalQuadraticSum) * uint256(s.alphaNumerator)) /
            uint256(s.alphaDenominator);
        uint256 weightedLinear = (uint256(s.totalLinearSum) *
            (uint256(s.alphaDenominator) - uint256(s.alphaNumerator))) / uint256(s.alphaDenominator);
        return weightedQuadratic + weightedLinear;
    }

    /**
     * @dev Computes the square root of a number using the Babylonian method.
     * @param x The input number.
     * @return result The square root of the input number.
     */
    function _sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        result = x;
        while (z < result) {
            result = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @notice Returns the current funding metrics for a specific project
     * @dev This function aggregates all the relevant funding data for a project
     * @param projectId The ID of the project to tally
     * @return sumContributions The total sum of all contributions for the project
     * @return sumSquareRoots The sum of square roots of all contributions
     * @return quadraticFunding The raw quadratic funding component (S_j^2)
     * @return linearFunding The raw linear funding component (Sum_j)
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

        // Convert to uint256 for calculations and return all relevant metrics for the project
        return (
            uint256(project.sumContributions), // Total contributions
            uint256(project.sumSquareRoots), // Sum of square roots
            (uint256(project.quadraticFunding) * uint256(s.alphaNumerator)) / uint256(s.alphaDenominator), // Alpha-weighted quadratic funding
            (uint256(project.sumContributions) * (uint256(s.alphaDenominator) - uint256(s.alphaNumerator))) /
                uint256(s.alphaDenominator) // Alpha-weighted linear funding (1-α) × Sum_j
        );
    }

    /**
     * @dev Sets the alpha parameter which determines the ratio between quadratic and linear funding
     * @param newNumerator The numerator of the new alpha value
     * @param newDenominator The denominator of the new alpha value
     * @notice Alpha must be between 0 and 1 (inclusive)
     */
    function _setAlpha(uint256 newNumerator, uint256 newDenominator) internal {
        // Input validation
        if (newDenominator == 0) revert DenominatorMustBePositive();
        if (newNumerator > newDenominator) revert AlphaMustBeLessOrEqualToOne();

        ProperQFStorage storage s = _getProperQFStorage();

        // Store old values for event emission
        uint256 oldNumerator = uint256(s.alphaNumerator);
        uint256 oldDenominator = uint256(s.alphaDenominator);

        // Update state using SafeCast
        s.alphaNumerator = newNumerator.toUint128();
        s.alphaDenominator = newDenominator.toUint128();

        // Recalculate total funding with new alpha
        s.totalFunding = _calculateWeightedTotalFunding();

        // Emit event
        emit AlphaUpdated(oldNumerator, oldDenominator, newNumerator, newDenominator);
    }

    /**
     * @dev Returns the current alpha value as a tuple of numerator and denominator
     * @return The current alpha ratio components
     */
    function getAlpha() public view returns (uint256, uint256) {
        ProperQFStorage storage s = _getProperQFStorage();
        return (uint256(s.alphaNumerator), uint256(s.alphaDenominator));
    }

    /**
     * @notice Calculate optimal alpha for 1:1 shares-to-assets ratio given fixed matching pool amount
     * @dev Formula: We want total funding = total assets available
     * @dev Total funding = α × totalQuadraticSum + (1-α) × totalLinearSum
     * @dev Total assets = totalUserDeposits + matchingPoolAmount
     * @dev Solving: α × totalQuadraticSum + (1-α) × totalLinearSum = totalUserDeposits + matchingPoolAmount
     * @dev Rearranging: α × (totalQuadraticSum - totalLinearSum) = totalUserDeposits + matchingPoolAmount - totalLinearSum
     * @param matchingPoolAmount Fixed amount of matching funds available
     * @param quadraticSum Total quadratic sum across all proposals
     * @param linearSum Total linear sum across all proposals (voting costs)
     * @param totalUserDeposits Total user deposits in the mechanism
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
