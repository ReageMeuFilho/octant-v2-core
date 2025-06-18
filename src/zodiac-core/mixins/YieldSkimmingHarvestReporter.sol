// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { BaseStrategy__NotSelf } from "src/errors.sol";

/**
 * @title Yield Skimming Harvest Reporter
 * @notice Implements yield skimming harvest and report logic for strategies that return delta
 */
abstract contract YieldSkimmingHarvestReporter {
    /*//////////////////////////////////////////////////////////////
                        TokenizedStrategy HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the change in value since the last report.
     * @dev Callback for the TokenizedStrategy to call during a report to
     * get the delta (change in value) the strategy has generated.
     *
     * This can only be called after a report() delegateCall to the
     * TokenizedStrategy so msg.sender == address(this).
     *
     * NOTE: This YieldSkimmingStrategy variant returns delta (int256)
     * instead of totalAssets (uint256) like the standard BaseStrategy.
     *
     * @return . The change in value (positive for gains, negative for losses)
     * since the last report as an int256.
     */
    function harvestAndReport() external virtual returns (int256) {
        // only self can call this function
        if (msg.sender != address(this)) {
            revert BaseStrategy__NotSelf();
        }
        int256 delta;
        (delta, ) = _harvestAndReport();
        return delta;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return the profit or loss since the last report.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current profit/loss.
     *
     * NOTE: Unlike the standard BaseStrategy, this YieldSkimmingStrategy variant
     * returns the DELTA (change in value, positive or negative) rather than totalAssets. This is
     * more efficient for strategies that maintain a stable principal and only
     * need to report yield changes. We also return the absolute delta, which is the
     * delta in value divided by the last reported exchange rate. This is useful for
     * strategies health checks.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return deltaAtNewRate The change in value (positive for gains, negative for losses)
     * generated since the last report at the new exchange rate. This is an int256 to handle both directions.
     * @return deltaAtOldRate The change in value (positive for gains, negative for losses)
     * generated since the last report at the old exchange rate. This is an int256 to handle both directions.
     */
    function _harvestAndReport() internal virtual returns (int256 deltaAtNewRate, int256 deltaAtOldRate);
}
