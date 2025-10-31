// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from IEarningPowerCalculator by [ScopeLift](https://scopelift.co)
// IEarningPowerCalculator is licensed under AGPL-3.0-only.
// Users of this contract should ensure compliance with the AGPL-3.0-only license terms of the inherited IEarningPowerCalculator contract.

pragma solidity ^0.8.0;

import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IWhitelistedEarningPowerCalculator
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This interface extends the IEarningPowerCalculator interface by adding a whitelist.
interface IWhitelistedEarningPowerCalculator is IEarningPowerCalculator, IERC165 {
    event WhitelistSet(IWhitelist indexed whitelist);

    /// @notice Sets the whitelist for the earning power calculator
    /// @param _whitelist The whitelist to set
    function setWhitelist(IWhitelist _whitelist) external;

    /// @notice Returns the whitelist for the earning power calculator
    /// @return The whitelist
    function whitelist() external view returns (IWhitelist);
}
