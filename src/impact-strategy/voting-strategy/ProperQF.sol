// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
contract ProperQF {
    struct Project {
        uint256 sumContributions; // Sum of contributions (Sum_j)
        uint256 sumSquareRoots; // Sum of square roots (S_j)
        uint256 quadraticFunding; // Quadratic term (F_quad_j)
        uint256 linearFunding; // Linear term (F_linear_j)
    }

    mapping(uint256 => Project) public projects; // Mapping of project IDs to project data
    uint256 public alphaNumerator = 10000; // Numerator for alpha (e.g., 6 for 0.6)
    uint256 public alphaDenominator = 10000; // Denominator for alpha (e.g., 10 for 0.6)

    uint256 public totalQuadraticSum; // Sum of all quadratic terms across projects
    uint256 public totalLinearSum; // Sum of all linear terms across projects
    uint256 public totalFunding; // Total funding across all projects

    /// @dev Event emitted when alpha value is updated
    event AlphaUpdated(uint256 oldNumerator, uint256 oldDenominator, uint256 newNumerator, uint256 newDenominator);

    /**
     * @dev Updates a project with a new contribution.
     * @param projectId The ID of the project to update.
     * @param contribution The new contribution to add.
     */
    function _processVote(uint256 projectId, uint256 contribution, uint256 voteWeight) internal {
        require(contribution > 0, "Contribution must be positive");
        require(voteWeight > 0, "Square root of contribution must be positive");
        require(voteWeight**2 <= contribution, "Square root of contribution must be less than or equal to contribution"); 
        // should be within 10% of the contribution

        Project storage project = projects[projectId];

        // Update project sums
        uint256 newSumSquareRoots = project.sumSquareRoots + voteWeight;
        uint256 newSumContributions = project.sumContributions + contribution;

        // Compute new quadratic and linear terms
        uint256 newQuadraticFunding = (newSumSquareRoots * newSumSquareRoots);

        // Update global sums
        totalQuadraticSum = totalQuadraticSum - project.quadraticFunding + newQuadraticFunding;
        totalLinearSum = totalLinearSum - project.linearFunding + newSumContributions;
        totalFunding = totalQuadraticSum + totalLinearSum;

        // Update project state
        project.sumSquareRoots = newSumSquareRoots;
        project.sumContributions = newSumContributions;
        project.quadraticFunding = newQuadraticFunding;
        project.linearFunding = newSumContributions;
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
     * @return quadraticFunding The quadratic funding component (α * S_j^2)
     * @return linearFunding The linear funding component ((1-α) * Sum_j)
     */
    function tally(uint256 projectId) 
        public 
        view 
        returns (
            uint256 sumContributions,
            uint256 sumSquareRoots,
            uint256 quadraticFunding,
            uint256 linearFunding
        ) 
    {
        // Retrieve the project data from storage
        Project storage project = projects[projectId];
        
        // Return all relevant metrics for the project
        return (
            project.sumContributions,    // Total contributions
            project.sumSquareRoots,      // Sum of square roots
            Math.mulDiv(project.quadraticFunding, alphaNumerator, alphaDenominator),    // Quadratic funding term
            Math.mulDiv(project.linearFunding, alphaDenominator, alphaDenominator)         // Linear funding term
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
        require(newDenominator > 0, "Denominator must be positive");
        require(newNumerator <= newDenominator, "Alpha must be <= 1");
        
        // Store old values for event emission
        uint256 oldNumerator = alphaNumerator;
        uint256 oldDenominator = alphaDenominator;
        
        // Update state
        alphaNumerator = newNumerator;
        alphaDenominator = newDenominator;
        
        // Emit event
        emit AlphaUpdated(oldNumerator, oldDenominator, newNumerator, newDenominator);
    }

    /**
     * @dev Returns the current alpha value as a tuple of numerator and denominator
     * @return The current alpha ratio components
     */
    function getAlpha() public view returns (uint256, uint256) {
        return (alphaNumerator, alphaDenominator);
    }
}
