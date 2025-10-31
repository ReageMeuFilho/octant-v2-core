// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from IWhitelistedEarningPowerCalculator by [Golem Foundation](https://golem.foundation)
// IWhitelistedEarningPowerCalculator is licensed under AGPL-3.0-only.
// Users of this contract should ensure compliance with the AGPL-3.0-only license terms of the inherited IWhitelistedEarningPowerCalculator contract.

pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "src/regen/interfaces/IWhitelistedEarningPowerCalculator.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title RegenEarningPowerCalculator
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Contract that calculates earning power based on staked amounts with optional whitelist restrictions
/// @dev This calculator returns the minimum of the staked amount and uint96 max value as earning power.
/// When a whitelist is configured, only whitelisted addresses receive earning power.
/// Setting the whitelist to address(0) allows all addresses to earn.
contract RegenEarningPowerCalculator is IWhitelistedEarningPowerCalculator, Ownable, ERC165 {
    /// @notice The whitelist contract that determines which addresses are eligible to earn power
    /// @dev When set to address(0), all addresses are eligible. Otherwise, only whitelisted addresses
    /// can earn power from their staked tokens.
    IWhitelist public override whitelist;

    /// @notice Initializes the RegenEarningPowerCalculator with an owner and optional whitelist
    /// @param _owner The address that will own this contract
    /// @param _whitelist The whitelist contract address (can be address(0) for no whitelist)
    /// @dev Emits a WhitelistSet event upon construction
    constructor(address _owner, IWhitelist _whitelist) Ownable(_owner) {
        whitelist = _whitelist;
        emit WhitelistSet(_whitelist);
    }

    /// @notice Returns the earning power of a staker
    /// @param stakedAmount The amount of staked tokens
    /// @param staker The address of the staker
    /// @return The earning power of the staker
    /// @dev Example: For stakedAmount=100, returns 100 if whitelisted; 0 otherwise.
    function getEarningPower(
        uint256 stakedAmount,
        address staker,
        address /*_delegatee*/
    ) external view override returns (uint256) {
        if (address(whitelist) != address(0) && !whitelist.isWhitelisted(staker)) {
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
    /// @dev Calculates new earning power based on whitelist status and staked amount.
    /// A staker qualifies for a bump whenever their earning power changes, which can happen when:
    /// - They are added/removed from the whitelist
    /// - Their staked amount changes
    /// This ensures deposits are updated promptly when whitelist status changes.
    function getNewEarningPower(
        uint256 stakedAmount,
        address staker,
        address, // _delegatee - unused
        uint256 oldEarningPower
    ) external view override returns (uint256 newCalculatedEarningPower, bool qualifiesForBump) {
        if (address(whitelist) != address(0) && !whitelist.isWhitelisted(staker)) {
            newCalculatedEarningPower = 0;
        } else {
            newCalculatedEarningPower = Math.min(stakedAmount, uint256(type(uint96).max));
        }

        qualifiesForBump = newCalculatedEarningPower != oldEarningPower;
    }

    /// @notice Sets the whitelist for the earning power calculator. Setting the whitelist to address(0) will allow all addresses to be eligible for earning power.
    /// @param _whitelist The whitelist to set
    /// @dev When _whitelist is address(0), whitelist checks are bypassed and all stakers can earn power.
    /// This allows the calculator to switch between permissioned and permissionless modes.
    /// Emits a WhitelistSet event.
    function setWhitelist(IWhitelist _whitelist) public override onlyOwner {
        whitelist = _whitelist;
        emit WhitelistSet(_whitelist);
    }

    /// @inheritdoc ERC165
    /// @dev Additionally supports the IWhitelistedEarningPowerCalculator interface
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IWhitelistedEarningPowerCalculator).interfaceId || super.supportsInterface(interfaceId);
    }
}
