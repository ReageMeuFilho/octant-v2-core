// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { BaseStrategy__NotSelf } from "src/errors.sol";

/**
 * @title Standard Harvest Reporter
 * @notice Implements standard harvest and report logic for strategies that return total assets
 */
abstract contract StandardHarvestReporter {
    /*//////////////////////////////////////////////////////////////
                        TokenizedStrategy HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the accurate amount of all funds currently
     * held by the Strategy.
     * @dev Callback for the TokenizedStrategy to call during a report to
     * get an accurate accounting of assets the strategy controls.
     *
     * This can only be called after a report() delegateCall to the
     * TokenizedStrategy so msg.sender == address(this).
     *
     * @return . A trusted and accurate account for the total amount
     * of 'asset' the strategy currently holds including idle funds.
     */
    function harvestAndReport() external virtual returns (uint256) {
        // only self can call this function
        if (msg.sender != address(this)) {
            revert BaseStrategy__NotSelf();
        }
        return _harvestAndReport();
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport() internal virtual returns (uint256 _totalAssets);
}
