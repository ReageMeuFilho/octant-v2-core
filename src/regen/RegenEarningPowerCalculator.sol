// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from IAccessControlledEarningPowerCalculator by [Golem Foundation](https://golem.foundation)
// IAccessControlledEarningPowerCalculator is licensed under AGPL-3.0-only.
// Users of this contract should ensure compliance with the AGPL-3.0-only license terms of the inherited IAccessControlledEarningPowerCalculator contract.

pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { IAccessControlledEarningPowerCalculator } from "src/regen/interfaces/IAccessControlledEarningPowerCalculator.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AccessMode } from "src/constants.sol";

/// @title RegenEarningPowerCalculator
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Contract that calculates earning power based on staked amounts with optional access control
/// @dev This calculator returns the minimum of the staked amount and uint96 max value as earning power.
/// Supports dual-mode access control: ALLOWSET (only approved addresses) or BLOCKSET (all except blocked).
contract RegenEarningPowerCalculator is IAccessControlledEarningPowerCalculator, Ownable, ERC165 {
    /// @notice The allowset contract that determines which addresses are eligible to earn power (ALLOWSET mode)
    /// @dev Active only when accessMode == AccessMode.ALLOWSET
    IAddressSet public override allowset;

    /// @notice The blockset contract that determines which addresses are blocked from earning (BLOCKSET mode)
    IAddressSet public blockset;

    /// @notice Current access mode for earning power
    AccessMode public accessMode;

    /// @notice Emitted when blockset is updated
    event BlocksetAssigned(IAddressSet indexed blockset);

    /// @notice Emitted when access mode is changed
    event AccessModeSet(AccessMode indexed mode);

    /// @notice Initializes the RegenEarningPowerCalculator with an owner and address sets
    /// @param _owner The address that will own this contract
    /// @param _allowset The allowset contract address
    /// @param _blockset The blockset contract address
    /// @param _accessMode The initial access mode (NONE, ALLOWSET, or BLOCKSET)
    /// @dev NOTE: AccessMode determines which address set is active, not address(0) checks
    constructor(address _owner, IAddressSet _allowset, IAddressSet _blockset, AccessMode _accessMode) Ownable(_owner) {
        allowset = _allowset;
        blockset = _blockset;
        accessMode = _accessMode;
        emit AllowsetAssigned(_allowset);
        emit BlocksetAssigned(_blockset);
        emit AccessModeSet(_accessMode);
    }

    function _hasAccess(address staker) internal view returns (bool) {
        if (accessMode == AccessMode.ALLOWSET) {
            return allowset.contains(staker);
        } else if (accessMode == AccessMode.BLOCKSET) {
            return !blockset.contains(staker);
        }
        return true;
    }

    /// @notice Returns the earning power of a staker
    /// @param stakedAmount The amount of staked tokens
    /// @param staker The address of the staker
    /// @return The earning power of the staker
    /// @dev Returns staked amount (capped at uint96 max) if staker has access, 0 otherwise
    function getEarningPower(
        uint256 stakedAmount,
        address staker,
        address /*_delegatee*/
    ) external view override returns (uint256) {
        if (!_hasAccess(staker)) {
            return 0;
        }
        return Math.min(stakedAmount, uint256(type(uint96).max));
    }

    /// @notice Returns the new earning power of a staker
    /// @param stakedAmount The amount of staked tokens
    /// @param staker The address of the staker
    /// @param oldEarningPower The old earning power of the staker
    /// @return newCalculatedEarningPower The new earning power of the staker
    /// @return qualifiesForBump Boolean indicating if the staker qualifies for a bump
    /// @dev Calculates new earning power based on access control status and staked amount.
    /// A staker qualifies for a bump whenever their earning power changes, which can happen when:
    /// - They are added/removed from access control sets
    /// - Their staked amount changes
    /// This ensures deposits are updated promptly when access status changes.
    function getNewEarningPower(
        uint256 stakedAmount,
        address staker,
        address, // _delegatee - unused
        uint256 oldEarningPower
    ) external view override returns (uint256 newCalculatedEarningPower, bool qualifiesForBump) {
        if (!_hasAccess(staker)) {
            newCalculatedEarningPower = 0;
        } else {
            newCalculatedEarningPower = Math.min(stakedAmount, uint256(type(uint96).max));
        }

        qualifiesForBump = newCalculatedEarningPower != oldEarningPower;
    }

    /// @notice Sets the allowset for the earning power calculator (ALLOWSET mode)
    /// @param _allowset The allowset to set
    /// @dev NOTE: Use setAccessMode(AccessMode.NONE) to disable access control
    function setAllowset(IAddressSet _allowset) public override onlyOwner {
        allowset = _allowset;
        emit AllowsetAssigned(_allowset);
    }

    /// @notice Sets the blockset for the earning power calculator (BLOCKSET mode)
    /// @param _blockset The blockset to set
    /// @dev NOTE: Use setAccessMode(AccessMode.NONE) to disable access control
    function setBlockset(IAddressSet _blockset) public onlyOwner {
        blockset = _blockset;
        emit BlocksetAssigned(_blockset);
    }

    /// @notice Sets the access mode for the earning power calculator
    /// @param _mode The access mode to set (NONE, ALLOWSET, or BLOCKSET)
    /// @dev Non-retroactive. Existing deposits require bumpEarningPower() to reflect changes.
    function setAccessMode(AccessMode _mode) public onlyOwner {
        accessMode = _mode;
        emit AccessModeSet(_mode);
    }

    /// @inheritdoc ERC165
    /// @dev Additionally supports the IAccessControlledEarningPowerCalculator interface
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IAccessControlledEarningPowerCalculator).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
