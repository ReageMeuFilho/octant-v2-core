// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { BaseYieldSkimmingStrategy } from "src/strategies/yieldSkimming/BaseYieldSkimmingStrategy.sol";

interface IRocketPool {
    function getExchangeRate() external view returns (uint256);
}

/**
 * @title RocketPoolStrategy
 * @notice A strategy that manages deposits in a RocketPool yield source and captures yield
 * @dev This strategy tracks the value of deposits and captures yield as the price per share increases
 */
contract RocketPoolStrategy is BaseYieldSkimmingStrategy {
    /**
     * @param _asset Address of the underlying asset
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
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
        BaseYieldSkimmingStrategy(
            _asset, // shares address
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
        // Call the getExchangeRate function on the RocketPool contract
        return IRocketPool(address(asset)).getExchangeRate();
    }
}
