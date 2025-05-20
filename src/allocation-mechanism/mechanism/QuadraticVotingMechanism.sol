// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseAllocationMechanism } from "../BaseAllocationMechanism.sol";
import { ProperQF } from "../voting-strategy/ProperQF.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Quadratic Voting Mechanism
/// @notice Implements quadratic funding for proposal allocation using the ProperQF strategy
/// @dev Combines BaseAllocationMechanism governance with ProperQF quadratic funding algorithm
contract QuadraticVotingMechanism is BaseAllocationMechanism, ProperQF, Ownable, Pausable, ReentrancyGuard {
    using Math for uint256;

    /// @notice Total voting power distributed across all proposals
    uint256 public totalVotingPower;

    /// @notice Emitted when alpha parameter is updated by governance
    event AlphaParameterUpdated(uint256 indexed numerator, uint256 indexed denominator);

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumShares,
        uint256 _timelockDelay,
        uint256 _alphaNumerator,
        uint256 _alphaDenominator
    )
        BaseAllocationMechanism(_asset, _name, _symbol, _votingDelay, _votingPeriod, _quorumShares, _timelockDelay)
        Ownable(msg.sender)
    {
        require(_votingDelay > 0, "Voting delay must be positive");
        require(_votingPeriod > 0, "Voting period must be positive");
        require(_quorumShares > 0, "Quorum must be positive");
        require(_timelockDelay > 0, "Timelock delay must be positive");
        require(_alphaNumerator <= _alphaDenominator, "Alpha must be <= 1");
        require(_alphaDenominator > 0, "Alpha denominator must be positive");

        // startBlock is already defined in BaseAllocationMechanism
        _setAlpha(_alphaNumerator, _alphaDenominator);
    }

    /// @notice Only registered users with voting power can propose
    function _beforeProposeHook(address proposer) internal view override whenNotPaused returns (bool) {
        require(proposer != address(0), "Zero address cannot propose");
        return votingPower[proposer] > 0;
    }

    /// @notice Validate proposal ID exists
    function _validateProposalHook(uint256 pid) internal view override returns (bool) {
        return pid > 0 && pid <= _proposalIdCounter;
    }

    /// @notice Allow all users to register (can be restricted in derived contracts)
    function _beforeSignupHook(address) internal pure override returns (bool) {
        return true;
    }

    /// @notice Calculate voting power directly from deposit amount
    function _getVotingPowerHook(address, uint256 deposit) internal pure override returns (uint256) {
        return deposit;
    }

    /// @notice Process vote using quadratic funding algorithm
    /// @dev The cost of voting is quadratic: to cast `weight` votes, you pay `weight^2` voting power
    function _processVoteHook(
        uint256 pid,
        address,
        VoteType choice,
        uint256 weight,
        uint256 oldPower
    ) internal override returns (uint256) {
        require(choice == VoteType.For, "Only For votes supported in QF");

        // Validate weight to prevent overflow in quadratic cost calculation
        require(weight <= type(uint128).max, "Vote weight too large");

        // Quadratic cost: to vote with weight W, you pay W^2 voting power
        uint256 quadraticCost = weight * weight;
        require(quadraticCost <= oldPower, "Insufficient voting power for quadratic cost");

        // Use ProperQF's vote processing: contribution = quadratic cost, voteWeight = actual vote weight
        _processVote(pid, quadraticCost, weight);

        // Track total voting power used with overflow protection
        uint256 newTotalVotingPower = totalVotingPower + weight;
        require(newTotalVotingPower >= totalVotingPower, "Total voting power overflow");
        totalVotingPower = newTotalVotingPower;

        // Return remaining voting power after quadratic cost
        return oldPower - quadraticCost;
    }

    /// @notice Check quorum based on quadratic funding threshold
    function _hasQuorumHook(uint256 pid) internal view override returns (bool) {
        // Get the project's funding metrics
        (, , uint256 quadraticFunding, uint256 linearFunding) = getTally(pid);

        // Calculate total funding for this project using alpha weighting
        uint256 projectTotalFunding = Math.mulDiv(quadraticFunding, alphaNumerator, alphaDenominator) +
            Math.mulDiv(linearFunding, (alphaDenominator - alphaNumerator), alphaDenominator);

        // Project meets quorum if it has minimum funding threshold
        return projectTotalFunding >= quorumShares;
    }

    /// @notice Convert quadratic funding to shares proportional to total funding
    function _convertVotesToShares(uint256 pid) internal view override returns (uint256) {
        if (totalFunding == 0) return 0;

        // Get project funding metrics
        (, , uint256 quadraticFunding, uint256 linearFunding) = getTally(pid);

        // Calculate project's weighted funding
        uint256 projectWeightedFunding = Math.mulDiv(quadraticFunding, alphaNumerator, alphaDenominator) +
            Math.mulDiv(linearFunding, (alphaDenominator - alphaNumerator), alphaDenominator);

        // Calculate total weighted funding across all projects
        uint256 totalWeightedFunding = Math.mulDiv(totalQuadraticSum, alphaNumerator, alphaDenominator) +
            Math.mulDiv(totalLinearSum, (alphaDenominator - alphaNumerator), alphaDenominator);

        // Return proportional shares (scaled by total voting power for meaningful allocation)
        if (totalWeightedFunding == 0 || totalVotingPower == 0) return 0;
        return Math.mulDiv(projectWeightedFunding, totalVotingPower, totalWeightedFunding);
    }

    /// @notice Allow finalization once voting period ends
    function _beforeFinalizeVoteTallyHook() internal pure override returns (bool) {
        return true;
    }

    /// @notice Get recipient address for proposal
    function _getRecipientAddressHook(uint256 pid) internal view override returns (address) {
        address recipient = proposals[pid].recipient;
        require(recipient != address(0), "Invalid recipient address");
        return recipient;
    }

    /// @notice Allow all distribution requests
    function _requestDistributionHook(address, uint256) internal pure override returns (bool) {
        return true;
    }

    /// @notice Only owner can update quorum
    function _beforeQuorumUpdateHook(uint256) internal view override returns (bool) {
        return msg.sender == owner();
    }

    /// @notice Update alpha parameter (governance function)
    /// @param newNumerator New alpha numerator
    /// @param newDenominator New alpha denominator
    function setAlpha(uint256 newNumerator, uint256 newDenominator) external onlyOwner {
        _setAlpha(newNumerator, newDenominator);
        emit AlphaParameterUpdated(newNumerator, newDenominator);
    }

    /// @notice Pause the contract in case of emergency
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
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
        require(_validateProposalHook(pid), "Invalid proposal");
        return getTally(pid);
    }
}
