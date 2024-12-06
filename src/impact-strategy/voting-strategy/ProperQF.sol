// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ProperQF {
    struct Project {
        uint256 sumContributions; // Sum of contributions (Sum_j)
        uint256 sumSquareRoots; // Sum of square roots (S_j)
        uint256 quadraticFunding; // Quadratic term (F_quad_j)
        uint256 linearFunding; // Linear term (F_linear_j)
    }

    mapping(uint256 => Project) public projects; // Mapping of project IDs to project data
    uint256 public alphaNumerator = 6; // Numerator for alpha (e.g., 6 for 0.6)
    uint256 public alphaDenominator = 10; // Denominator for alpha (e.g., 10 for 0.6)

    uint256 public totalQuadraticSum; // Sum of all quadratic terms across projects
    uint256 public totalLinearSum; // Sum of all linear terms across projects
    uint256 public totalFunding; // Total funding across all projects

    /**
     * @dev Updates a project with a new contribution.
     * @param projectId The ID of the project to update.
     * @param contribution The new contribution to add.
     */
    function _processVote(uint256 projectId, uint256 contribution) internal {
        require(contribution > 0, "Contribution must be positive");

        Project storage project = projects[projectId];

        // Compute square root of the new contribution
        uint256 sqrtContribution = _sqrt(contribution);

        // Update project sums
        uint256 newSumSquareRoots = project.sumSquareRoots + sqrtContribution;
        uint256 newSumContributions = project.sumContributions + contribution;

        // Compute new quadratic and linear terms
        uint256 newQuadraticFunding = (alphaNumerator * newSumSquareRoots * newSumSquareRoots) / alphaDenominator;
        uint256 newLinearFunding = ((alphaDenominator - alphaNumerator) * newSumContributions) / alphaDenominator;

        // Update global sums
        totalQuadraticSum = totalQuadraticSum - project.quadraticFunding + newQuadraticFunding;
        totalLinearSum = totalLinearSum - project.linearFunding + newLinearFunding;
        totalFunding = totalQuadraticSum + totalLinearSum;

        // Update project state
        project.sumSquareRoots = newSumSquareRoots;
        project.sumContributions = newSumContributions;
        project.quadraticFunding = newQuadraticFunding;
        project.linearFunding = newLinearFunding;
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
}
