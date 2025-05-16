// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IWhitelist } from "./whitelist/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "./IWhitelistedEarningPowerCalculator.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract RegenEarningPowerCalculator is IWhitelistedEarningPowerCalculator, Ownable, ERC165 {
    IWhitelist public override whitelist;

    constructor(address _owner, IWhitelist _whitelist) Ownable(_owner) {
        whitelist = _whitelist;
        emit WhitelistSet(_whitelist);
    }

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

        if (
            (oldEarningPower > 0 && newCalculatedEarningPower == 0) ||
            (oldEarningPower == 0 && newCalculatedEarningPower > 0)
        ) {
            qualifiesForBump = true;
        } else if (oldEarningPower > 0 && newCalculatedEarningPower > 0) {
            if (newCalculatedEarningPower >= oldEarningPower * 2 || newCalculatedEarningPower * 2 <= oldEarningPower) {
                qualifiesForBump = true;
            }
        }
        // else qualifiesForBump remains false (default)
    }

    function setWhitelist(IWhitelist _whitelist) public override onlyOwner {
        whitelist = _whitelist;
        emit WhitelistSet(_whitelist);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IWhitelistedEarningPowerCalculator).interfaceId || super.supportsInterface(interfaceId);
    }
}
