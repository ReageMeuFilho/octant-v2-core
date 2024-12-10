// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.20;


// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // skipped
// import { IProjectRegistry } from "src/interfaces/IProjectRegistry.sol"; // included
// import "src/impact-strategy/BaseImpactStrategy.sol"; // included

// contract MockImpactStrategy is BaseImpactStrategy {
//     // Storage for vote tracking
//     mapping(address => mapping(address => uint256)) public userVotes;
//     mapping(address => uint256) public projectVotes;
//     uint256 public totalVotesCast;

//     constructor(
//         address _asset,
//         string memory _name
//     ) BaseImpactStrategy(_asset, _name) {}

//     /**
//      * @notice Calculates veToken amount for a deposit
//      * @dev Simple 1:1 conversion for testing purposes
//      */
//     function _calculateVeTokens(
//         uint256 _amount,
//         address,
//         uint256
//     ) internal pure override returns (uint256) {
//         return _amount; // 1:1 conversion for testing
//     }

//     /**
//      * @notice Processes a vote allocation
//      * @dev Records vote weight based on token balance
//      * @param _voter Address casting the vote
//      * @param _project Project being voted for
//      * @param _weight Amount of voting power to allocate
//      */
//     function _processVote(
//         address _voter,
//         address _project,
//         uint256 _weight
//     ) internal {
//         require(_weight > 0, "ZERO_WEIGHT");
//         require(ASSET.balanceOf(_voter) >= _weight, "INSUFFICIENT_BALANCE");
        
//         // Update vote records
//         projectVotes[_project] += _weight;
//         userVotes[_voter][_project] += _weight;
//         totalVotesCast += _weight;
//     }

//     /**
//      * @notice Calculates shares based on vote weight
//      * @dev Direct 1:1 mapping of votes to shares
//      */
//     function _calculateShares(
//         address,
//         uint256 _totalVotes
//     ) internal pure returns (uint256) {
//         return _totalVotes;
//     }

//     /**
//      * @notice Get total votes for a project
//      * @param _project Project address to check
//      * @return uint256 Total votes allocated to project
//      */
//     function getProjectVotes(address _project) external view returns (uint256) {
//         return projectVotes[_project];
//     }

//     /**
//      * @notice Get user's votes for a project
//      * @param _voter Voter address to check
//      * @param _project Project address to check
//      * @return uint256 User's votes for project
//      */
//     function getUserVotes(
//         address _voter,
//         address _project
//     ) external view returns (uint256) {
//         return userVotes[_voter][_project];
//     }

//     /**
//      * @notice Get total votes in system
//      * @return uint256 Total votes cast
//      */
//     function getTotalVotes() external view returns (uint256) {
//         return totalVotesCast;
//     }
// } 