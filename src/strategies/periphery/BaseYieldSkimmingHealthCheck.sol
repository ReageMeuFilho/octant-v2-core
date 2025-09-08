// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseStrategy } from "src/core/BaseStrategy.sol";
import { IBaseHealthCheck } from "src/strategies/interfaces/IBaseHealthCheck.sol";
import { IYieldSkimmingStrategy } from "src/strategies/yieldSkimming/IYieldSkimmingStrategy.sol";
import { WadRayMath } from "src/utils/libs/Maths/WadRay.sol";

/**
 *   @title Base Yield Skimming Health Check
 *   @author Octant
 *   @notice This contract can be inherited by any Yield Skimming strategy wishing to implement a health check during
 *   the `harvestAndReport` function in order to prevent any unexpected behavior from being permanently recorded as well
 *   as the `checkHealth` modifier.
 *
 *   A strategist simply needs to inherit this contract. Set
 *   the limit ratios to the desired amounts and then
 *   override `_harvestAndReport()` just as they otherwise
 *  would. If the profit or loss that would be recorded is
 *   outside the acceptable bounds the tx will revert.
 *
 *   The healthcheck does not prevent a strategy from reporting
 *   losses, but rather can make sure manual intervention is
 *   needed before reporting an unexpected loss or profit.
 */
abstract contract BaseYieldSkimmingHealthCheck is BaseStrategy, IBaseHealthCheck {
    using WadRayMath for uint256;

    // Can be used to determine if a healthcheck should be called.
    // Defaults to true;
    bool public doHealthCheck = true;

    uint256 internal constant MAX_BPS = 10_000;

    // Default profit limit to 100%.
    uint16 private _profitLimitRatio = uint16(MAX_BPS);

    // Defaults loss limit to 0.
    uint16 private _lossLimitRatio;

    /// @notice Emitted when the health check flag is updated
    event HealthCheckUpdated(bool doHealthCheck);

    /// @notice Emitted when the profit limit ratio is updated
    event ProfitLimitRatioUpdated(uint256 newProfitLimitRatio);

    /// @notice Emitted when the loss limit ratio is updated
    event LossLimitRatioUpdated(uint256 newLossLimitRatio);

    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseStrategy(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {}

    /**
     * @notice Returns the current profit limit ratio.
     * @dev Use a getter function to keep the variable private.
     * @return . The current profit limit ratio.
     */
    function profitLimitRatio() public view returns (uint256) {
        return _profitLimitRatio;
    }

    /**
     * @notice Returns the current loss limit ratio.
     * @dev Use a getter function to keep the variable private.
     * @return . The current loss limit ratio.
     */
    function lossLimitRatio() public view returns (uint256) {
        return _lossLimitRatio;
    }

    /**
     * @notice Set the `profitLimitRatio`.
     * @dev Denominated in basis points. I.E. 1_000 == 10%.
     * @param _newProfitLimitRatio The new profit limit ratio.
     */
    function setProfitLimitRatio(uint256 _newProfitLimitRatio) external onlyManagement {
        _setProfitLimitRatio(_newProfitLimitRatio);
    }

    /**
     * @dev Internally set the profit limit ratio. Denominated
     * in basis points. I.E. 1_000 == 10%.
     * @param _newProfitLimitRatio The new profit limit ratio.
     */
    function _setProfitLimitRatio(uint256 _newProfitLimitRatio) internal {
        require(_newProfitLimitRatio > 0, "!zero profit");
        require(_newProfitLimitRatio <= type(uint16).max, "!too high");
        _profitLimitRatio = uint16(_newProfitLimitRatio);
        emit ProfitLimitRatioUpdated(_newProfitLimitRatio);
    }

    /**
     * @notice Returns the current exchange rate in RAY format
     * @return The current exchange rate in RAY format.
     */
    function getCurrentRateRay() public view returns (uint256) {
        uint256 currentRate = IYieldSkimmingStrategy(address(this)).getCurrentExchangeRate();
        uint256 decimals = IYieldSkimmingStrategy(address(this)).decimalsOfExchangeRate();

        // Convert directly to RAY (27 decimals) to avoid precision loss
        if (decimals < 27) {
            return currentRate * 10 ** (27 - decimals);
        } else if (decimals > 27) {
            return currentRate / 10 ** (decimals - 27);
        } else {
            return currentRate;
        }
    }

    /**
     * @notice Set the `lossLimitRatio`.
     * @dev Denominated in basis points. I.E. 1_000 == 10%.
     * @param _newLossLimitRatio The new loss limit ratio.
     */
    function setLossLimitRatio(uint256 _newLossLimitRatio) external onlyManagement {
        _setLossLimitRatio(_newLossLimitRatio);
    }

    /**
     * @dev Internally set the loss limit ratio. Denominated
     * in basis points. I.E. 1_000 == 10%.
     * @param _newLossLimitRatio The new loss limit ratio.
     */
    function _setLossLimitRatio(uint256 _newLossLimitRatio) internal {
        require(_newLossLimitRatio < MAX_BPS, "!loss limit");
        _lossLimitRatio = uint16(_newLossLimitRatio);
        emit LossLimitRatioUpdated(_newLossLimitRatio);
    }

    /**
     * @notice Turns the healthcheck on and off.
     * @dev If turned off the next report will auto turn it back on.
     * @param _doHealthCheck Bool if healthCheck should be done.
     */
    function setDoHealthCheck(bool _doHealthCheck) public onlyManagement {
        doHealthCheck = _doHealthCheck;
        emit HealthCheckUpdated(_doHealthCheck);
    }

    /**
     * @notice OVerrides the default {harvestAndReport} to include a healthcheck.
     * @return _totalAssets New totalAssets post report.
     */
    function harvestAndReport() external override onlySelf returns (uint256 _totalAssets) {
        // Let the strategy report.
        _totalAssets = _harvestAndReport();

        // Run the healthcheck on the amount returned.
        _executeHealthCheck(_totalAssets);
    }

    /**
     * @dev To be called during a report to make sure the profit
     * or loss being recorded is within the acceptable bound.
     */
    function _executeHealthCheck(uint256 /*_newTotalAssets*/) internal virtual {
        if (!doHealthCheck) {
            doHealthCheck = true;
            return;
        }

        uint256 currentExchangeRate = IYieldSkimmingStrategy(address(this)).getLastRateRay();
        uint256 newExchangeRate = getCurrentRateRay();

        if (currentExchangeRate < newExchangeRate) {
            require(
                ((newExchangeRate - currentExchangeRate) <=
                    (currentExchangeRate * uint256(_profitLimitRatio)) / MAX_BPS),
                "!profit"
            );
        } else if (currentExchangeRate > newExchangeRate) {
            require(
                ((currentExchangeRate - newExchangeRate) <= (currentExchangeRate * uint256(_lossLimitRatio)) / MAX_BPS),
                "!loss"
            );
        }
    }
}
