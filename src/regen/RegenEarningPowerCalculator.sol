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

    function getEarningPower(
        uint256 stakedAmount,
        address staker,
        address /*_delegatee*/
    ) external view override returns (uint256) {
        uint256 const_uint96_max = uint256(type(uint96).max);
        uint256 cappedAmount;
        if (stakedAmount > const_uint96_max) {
            cappedAmount = const_uint96_max;
        } else {
            cappedAmount = stakedAmount;
        }

        if (address(whitelist) == address(0)) return cappedAmount;
        else if (whitelist.isWhitelisted(staker)) return cappedAmount;
        else return 0;
    }

    function getNewEarningPower(
        uint256 stakedAmount,
        address staker,
        address, // _delegatee - unused
        uint256 oldEarningPower
    ) external view override returns (uint256 newCalculatedEarningPower, bool qualifiesForBump) {
        uint256 const_uint96_max = uint256(type(uint96).max);
        uint256 cappedAmount;
        if (stakedAmount > const_uint96_max) {
            cappedAmount = const_uint96_max;
        } else {
            cappedAmount = stakedAmount;
        }

        if (address(whitelist) == address(0)) {
            newCalculatedEarningPower = cappedAmount;
        } else if (whitelist.isWhitelisted(staker)) {
            newCalculatedEarningPower = cappedAmount;
        } else {
            newCalculatedEarningPower = 0;
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
