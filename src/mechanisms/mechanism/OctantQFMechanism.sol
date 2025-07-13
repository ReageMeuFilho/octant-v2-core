// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { QuadraticVotingMechanism } from "./QuadraticVotingMechanism.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { BaseAllocationMechanism, AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";

/// @title Octant Quadratic Funding Mechanism
/// @notice Extends QuadraticVotingMechanism with whitelist-based access control for signups
/// @dev Only whitelisted addresses can signup to participate in the allocation mechanism
contract OctantQFMechanism is QuadraticVotingMechanism {
    /// @notice Whitelist contract for signup access control
    IWhitelist public whitelist;

    /// @notice Emitted when whitelist contract is updated
    event WhitelistUpdated(address indexed oldWhitelist, address indexed newWhitelist);

    /// @notice Initialize OctantQFMechanism with whitelist support
    /// @param _implementation Address of the TokenizedAllocationMechanism implementation
    /// @param _config Configuration parameters for the allocation mechanism
    /// @param _alphaNumerator Numerator for alpha parameter (quadratic vs linear weighting)
    /// @param _alphaDenominator Denominator for alpha parameter
    /// @param _whitelist Address of the whitelist contract (can be address(0) for open access)
    constructor(
        address _implementation,
        AllocationConfig memory _config,
        uint256 _alphaNumerator,
        uint256 _alphaDenominator,
        address _whitelist
    ) QuadraticVotingMechanism(_implementation, _config, _alphaNumerator, _alphaDenominator) {
        whitelist = IWhitelist(_whitelist);
        emit WhitelistUpdated(address(0), _whitelist);
    }

    /// @notice Override signup hook to check whitelist
    /// @param user Address attempting to sign up
    /// @return True if user is whitelisted or whitelist is disabled
    function _beforeSignupHook(address user) internal view virtual override returns (bool) {
        // If no whitelist is set, allow all users (open access)
        if (address(whitelist) == address(0)) {
            return true;
        }

        // Check if user is whitelisted
        return whitelist.isWhitelisted(user);
    }

    /// @notice Update the whitelist contract address
    /// @param _newWhitelist Address of new whitelist contract (address(0) to disable)
    /// @dev Only callable by the mechanism owner
    function setWhitelist(address _newWhitelist) external {
        require(_tokenizedAllocation().owner() == msg.sender, "Only owner can update whitelist");

        address oldWhitelist = address(whitelist);
        whitelist = IWhitelist(_newWhitelist);

        emit WhitelistUpdated(oldWhitelist, _newWhitelist);
    }

    /// @notice Check if an address is allowed to signup
    /// @param user Address to check
    /// @return True if user can signup
    function canSignup(address user) external view returns (bool) {
        return _beforeSignupHook(user);
    }
}
