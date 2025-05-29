// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from IWhitelistedEarningPowerCalculator by [Golem Foundation](https://golem.foundation)
// IWhitelistedEarningPowerCalculator is licensed under AGPL-3.0-only.
// Users of this contract should ensure compliance with the AGPL-3.0-only license terms of the inherited IWhitelistedEarningPowerCalculator contract.

pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "src/regen/IWhitelistedEarningPowerCalculator.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract RegenEarningPowerCalculator is IWhitelistedEarningPowerCalculator, Ownable, ERC165 {
    IWhitelist public override whitelist;

    constructor(address _owner, IWhitelist _whitelist) Ownable(_owner) {
        whitelist = _whitelist;
        emit WhitelistSet(_whitelist);
    }

    // @notice Returns the earning power of a staker
    // @param stakedAmount The amount of staked tokens
    // @param staker The address of the staker
    // @param _delegatee The address of the delegatee
    // @return The earning power of the staker
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

    // @notice Returns the new earning power of a staker
    // @param stakedAmount The amount of staked tokens
    // @param staker The address of the staker
    // @param _delegatee The address of the delegatee
    // @param oldEarningPower The old earning power of the staker
    // @return The new earning power of the staker and a boolean indicating if the staker qualifies for a bump
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

    // @notice Sets the whitelist for the earning power calculator. Setting the whitelist to address(0) will allow all addresses to be eligible for earning power.
    // @param _whitelist The whitelist to set
    function setWhitelist(IWhitelist _whitelist) public override onlyOwner {
        whitelist = _whitelist;
        emit WhitelistSet(_whitelist);
    }

    // @notice Returns true if the contract implements the interface
    // @param interfaceId The interface ID to check
    // @return True if the contract implements the interface, false otherwise
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IWhitelistedEarningPowerCalculator).interfaceId || super.supportsInterface(interfaceId);
    }
}
