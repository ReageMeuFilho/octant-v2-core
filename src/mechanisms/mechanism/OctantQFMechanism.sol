// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { QuadraticVotingMechanism } from "./QuadraticVotingMechanism.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { AccessMode } from "src/constants.sol";
import { AllocationConfig, TokenizedAllocationMechanism } from "src/mechanisms/BaseAllocationMechanism.sol";
import { NotInAllowset, InBlockset } from "src/errors.sol";

/// @title Octant Quadratic Funding Mechanism
/// @notice Extends QuadraticVotingMechanism with access control for signups
/// @dev Supports dual-mode access control (allowset/blockset) for contribution restrictions
contract OctantQFMechanism is QuadraticVotingMechanism {
    AccessMode public contributionAccessMode;
    IAddressSet public contributionAllowset;
    IAddressSet public contributionBlockset;

    event ContributionAllowsetAssigned(IAddressSet indexed allowset);
    event ContributionBlocksetAssigned(IAddressSet indexed blockset);
    event AccessModeSet(AccessMode indexed mode);

    constructor(
        address _implementation,
        AllocationConfig memory _config,
        uint256 _alphaNumerator,
        uint256 _alphaDenominator,
        IAddressSet _contributionAllowset,
        IAddressSet _contributionBlockset,
        AccessMode _contributionAccessMode
    ) QuadraticVotingMechanism(_implementation, _config, _alphaNumerator, _alphaDenominator) {
        contributionAllowset = _contributionAllowset;
        contributionBlockset = _contributionBlockset;
        contributionAccessMode = _contributionAccessMode;

        emit ContributionAllowsetAssigned(_contributionAllowset);
        emit ContributionBlocksetAssigned(_contributionBlockset);
        emit AccessModeSet(_contributionAccessMode);
    }

    function _beforeSignupHook(address user) internal view virtual override returns (bool) {
        if (contributionAccessMode == AccessMode.ALLOWSET) {
            require(contributionAllowset.contains(user), NotInAllowset(user));
        } else if (contributionAccessMode == AccessMode.BLOCKSET) {
            require(!contributionBlockset.contains(user), InBlockset(user));
        }

        return true;
    }

    /// @notice Sets the contribution allowset (for ALLOWSET mode)
    /// @param _allowset The new allowset contract
    /// @dev Non-retroactive. Existing voting power is not affected.
    function setContributionAllowset(IAddressSet _allowset) external {
        require(_tokenizedAllocation().owner() == msg.sender, "Only owner");
        contributionAllowset = _allowset;
        emit ContributionAllowsetAssigned(_allowset);
    }

    /// @notice Sets the contribution blockset (for BLOCKSET mode)
    /// @param _blockset The new blockset contract
    /// @dev Non-retroactive. Existing voting power is not affected.
    function setContributionBlockset(IAddressSet _blockset) external {
        require(_tokenizedAllocation().owner() == msg.sender, "Only owner");
        contributionBlockset = _blockset;
        emit ContributionBlocksetAssigned(_blockset);
    }

    /// @notice Sets the contribution access mode
    /// @param _mode The new access mode (NONE, ALLOWSET, or BLOCKSET)
    /// @dev Only allowed before voting starts or after tally finalization.
    ///      Non-retroactive. Existing voting power is not affected.
    function setAccessMode(AccessMode _mode) external {
        TokenizedAllocationMechanism tam = _tokenizedAllocation();
        require(tam.owner() == msg.sender, "Only owner");

        // Safety check: Prevent mode switching during active voting or before finalization
        // This prevents attackers from gaining voting power mid-vote or front-running mode switches
        bool beforeVoting = block.timestamp < tam.votingStartTime();
        bool afterFinalization = tam.tallyFinalized();
        require(
            beforeVoting || afterFinalization,
            "Mode changes only allowed before voting starts or after tally finalization"
        );

        contributionAccessMode = _mode;
        emit AccessModeSet(_mode);
    }

    /// @notice Checks if a user is eligible to signup/contribute based on current access mode
    /// @param user The address to check
    /// @return bool True if user can signup, false otherwise
    /// @dev Used for defense-in-depth checks. Respects contributionAccessMode:
    ///      NONE: always returns true
    ///      ALLOWSET: returns true if user is in contributionAllowset
    ///      BLOCKSET: returns true if user is NOT in contributionBlockset
    function canSignup(address user) external view returns (bool) {
        if (contributionAccessMode == AccessMode.ALLOWSET) {
            return contributionAllowset.contains(user);
        } else if (contributionAccessMode == AccessMode.BLOCKSET) {
            return !contributionBlockset.contains(user);
        }
        return true;
    }
}
