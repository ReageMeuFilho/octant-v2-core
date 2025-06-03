// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.25;

/**
 * @title IBaseHealthCheck Interface
 * @author Yearn.finance
 * @notice Interface for the BaseHealthCheck contract defining the core functions
 * and events needed for health checking strategy profit/loss reporting.
 */
interface IBaseHealthCheck {
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns whether the health check is currently enabled.
     * @return Status of the health check.
     */
    function doHealthCheck() external view returns (bool);

    /**
     * @notice Returns the current profit limit ratio.
     * @return The current profit limit ratio in basis points.
     */
    function profitLimitRatio() external view returns (uint256);

    /**
     * @notice Returns the current loss limit ratio.
     * @return The current loss limit ratio in basis points.
     */
    function lossLimitRatio() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the `profitLimitRatio`.
     * @dev Denominated in basis points. I.E. 1_000 == 10%.
     * @param _newProfitLimitRatio The new profit limit ratio.
     */
    function setProfitLimitRatio(uint256 _newProfitLimitRatio) external;

    /**
     * @notice Set the `lossLimitRatio`.
     * @dev Denominated in basis points. I.E. 1_000 == 10%.
     * @param _newLossLimitRatio The new loss limit ratio.
     */
    function setLossLimitRatio(uint256 _newLossLimitRatio) external;

    /**
     * @notice Turns the healthcheck on and off.
     * @dev If turned off the next report will auto turn it back on.
     * @param _doHealthCheck Bool if healthCheck should be done.
     */
    function setDoHealthCheck(bool _doHealthCheck) external;
}
