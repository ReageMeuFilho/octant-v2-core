// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract ProperQF {
    using Math for uint256;

    // Custom Errors
    error ContributionMustBePositive();
    error VoteWeightMustBePositive();
    error VoteWeightOverflow();
    error SquareRootTooLarge();
    error VoteWeightOutsideTolerance();
    error QuadraticSumUnderflow();
    error LinearSumUnderflow();
    error DenominatorMustBePositive();
    error AlphaMustBeLessOrEqualToOne();

    /// @notice EIP-712 storage slot for the ProperQF storage struct
    /// @dev keccak256("ProperQF.storage") - 1
    bytes32 private constant STORAGE_SLOT = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

    struct Project {
        uint256 sumContributions; // Sum of contributions (Sum_j)
        uint256 sumSquareRoots; // Sum of square roots (S_j)
        uint256 quadraticFunding; // Quadratic term (F_quad_j)
        uint256 linearFunding; // Linear term (F_linear_j)
    }

    /// @notice Main storage struct containing all mutable state for ProperQF
    struct ProperQFStorage {
        mapping(uint256 => Project) projects; // Mapping of project IDs to project data
        uint256 alphaNumerator; // Numerator for alpha (e.g., 6 for 0.6)
        uint256 alphaDenominator; // Denominator for alpha (e.g., 10 for 0.6)
        uint256 totalQuadraticSum; // Sum of all quadratic terms across projects
        uint256 totalLinearSum; // Sum of all linear terms across projects
        uint256 totalFunding; // Total funding across all projects
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
        if (voteWeight < actualSqrt - tolerance || voteWeight > actualSqrt + tolerance) {
            revert VoteWeightOutsideTolerance();
        }

        ProperQFStorage storage s = _getProperQFStorage();
        Project storage project = s.projects[projectId];

        // Update project sums
        uint256 newSumSquareRoots = project.sumSquareRoots + voteWeight;
        uint256 newSumContributions = project.sumContributions + contribution;

        // Compute new quadratic and linear terms
        uint256 newQuadraticFunding = (newSumSquareRoots * newSumSquareRoots);

        // Update global sums with underflow protection
        if (s.totalQuadraticSum < project.quadraticFunding) revert QuadraticSumUnderflow();
        if (s.totalLinearSum < project.linearFunding) revert LinearSumUnderflow();

        s.totalQuadraticSum = s.totalQuadraticSum - project.quadraticFunding + newQuadraticFunding;
        s.totalLinearSum = s.totalLinearSum - project.linearFunding + newSumContributions;

        // Calculate total funding with alpha weighting
        s.totalFunding = _calculateWeightedTotalFunding();

        // Update project state
        project.sumSquareRoots = newSumSquareRoots;
        project.sumContributions = newSumContributions;
        project.quadraticFunding = newQuadraticFunding;
        project.linearFunding = newSumContributions;
    }

    /**
     * @dev Calculate weighted total funding using alpha parameter
     * @return The weighted total funding across all projects
     */
    function _calculateWeightedTotalFunding() internal view returns (uint256) {
        ProperQFStorage storage s = _getProperQFStorage();
        uint256 weightedQuadratic = (s.totalQuadraticSum * s.alphaNumerator) / s.alphaDenominator;
        uint256 weightedLinear = s.totalLinearSum; // Linear funding is always the raw contribution sum
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
    function getTally(uint256 projectId)
        public
        view
        returns (uint256 sumContributions, uint256 sumSquareRoots, uint256 quadraticFunding, uint256 linearFunding)
    {
        // Retrieve the project data from storage
        ProperQFStorage storage s = _getProperQFStorage();
        Project storage project = s.projects[projectId];

        // Return all relevant metrics for the project
        return (
            project.sumContributions, // Total contributions
            project.sumSquareRoots, // Sum of square roots
            (project.quadraticFunding * s.alphaNumerator) / s.alphaDenominator, // Alpha-weighted quadratic funding
            project.sumContributions // Raw linear funding (Sum_j)
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
        uint256 oldNumerator = s.alphaNumerator;
        uint256 oldDenominator = s.alphaDenominator;

        // Update state
        s.alphaNumerator = newNumerator;
        s.alphaDenominator = newDenominator;

        // Emit event
        emit AlphaUpdated(oldNumerator, oldDenominator, newNumerator, newDenominator);
    }

    /**
     * @dev Returns the current alpha value as a tuple of numerator and denominator
     * @return The current alpha ratio components
     */
    function getAlpha() public view returns (uint256, uint256) {
        ProperQFStorage storage s = _getProperQFStorage();
        return (s.alphaNumerator, s.alphaDenominator);
    }
}
