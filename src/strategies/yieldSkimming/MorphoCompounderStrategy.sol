// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import { BaseYieldSkimmingStrategy } from "src/strategies/yieldSkimming/BaseYieldSkimmingStrategy.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

/**
 * @title MorphoCompounderStrategy
 * @notice A strategy that manages deposits in a Morpho yield source and captures yield
 * @dev This strategy tracks the value of deposits and captures yield as the price per share increases
 */
contract MorphoCompounderStrategy is BaseYieldSkimmingStrategy {
    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        address _tokenizedStrategyAddress
    )
        BaseYieldSkimmingStrategy(
            _asset, // shares address
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _tokenizedStrategyAddress
        )
    {}

    /**
     * @notice Returns the decimals of the exchange rate
     * @return The decimals of the exchange rate
     */
    function decimalsOfExchangeRate() public pure override returns (uint256) {
        return 18;
    }

    /**
     * @notice Gets the current exchange rate from the yield vault
     * @return The current price per share
     */
    function _getCurrentExchangeRate() internal view override returns (uint256) {
        // Call the pricePerShare function on the tokenized strategy
        return ITokenizedStrategy(address(asset)).pricePerShare();
    }
}
