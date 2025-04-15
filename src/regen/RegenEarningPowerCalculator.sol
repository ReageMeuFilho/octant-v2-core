// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IWhitelist } from "./whitelist/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "./IWhitelistedEarningPowerCalculator.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract RegenEarningPowerCalculator is IWhitelistedEarningPowerCalculator, Ownable, ERC165 {
    IWhitelist public override whitelist;

    constructor(address _owner, IWhitelist _whitelist) Ownable(_owner) {
        whitelist = _whitelist;
        emit WhitelistSet(_whitelist);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IWhitelistedEarningPowerCalculator).interfaceId || super.supportsInterface(interfaceId);
    }

    // For whitelisted users, return their staked amount
    // For non-whitelisted users, return 0
    function getEarningPower(uint256 stakedAmount, address staker, address) external view returns (uint256) {
        // Staker.sol uses uint96 for the earning power, so we cap the amount at that.
        uint256 cappedAmount = stakedAmount > type(uint96).max ? type(uint96).max : stakedAmount;
        if (address(whitelist) == address(0)) return cappedAmount;
        else if (whitelist.isWhitelisted(staker)) return cappedAmount;
        else return 0;
    }

    function getNewEarningPower(
        uint256 stakedAmount,
        address staker,
        address,
        uint256 oldEarningPower
    ) external view returns (uint256, bool) {
        // Staker.sol uses uint96 for the earning power, so we cap the amount at that.
        uint256 cappedAmount = stakedAmount > type(uint96).max ? type(uint96).max : stakedAmount;

        // Calculate new earning power based on whitelist status
        uint256 newEarningPower;
        if (address(whitelist) == address(0)) {
            newEarningPower = cappedAmount;
        } else if (whitelist.isWhitelisted(staker)) {
            newEarningPower = cappedAmount;
        } else {
            newEarningPower = 0;
        }

        // Determine if this qualifies for a bump
        bool qualifiesForBump = false;

        // Case 1: Whitelist status changes (going from earning to not earning or vice versa)
        if ((oldEarningPower > 0 && newEarningPower == 0) || (oldEarningPower == 0 && newEarningPower > 0)) {
            qualifiesForBump = true;
        }
        // Case 2: Significant change in earning power (e.g., doubled or halved)
        // Only check when both values are non-zero to avoid division by zero
        else if (oldEarningPower > 0 && newEarningPower > 0) {
            // Check if value doubled or halved (significant enough change to warrant a bump)
            if (newEarningPower >= oldEarningPower * 2 || newEarningPower * 2 <= oldEarningPower) {
                qualifiesForBump = true;
            }
        }

        return (newEarningPower, qualifiesForBump);
    }

    function setWhitelist(IWhitelist _whitelist) public onlyOwner {
        whitelist = _whitelist;
        emit WhitelistSet(_whitelist);
    }
}
