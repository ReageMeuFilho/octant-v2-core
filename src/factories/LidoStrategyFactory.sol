// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { BaseStrategyFactory } from "./BaseStrategyFactory.sol";
import { LidoStrategy } from "src/strategies/yieldSkimming/LidoStrategy.sol";

/**
 * @title LidoStrategyFactory
 * @author Octant
 * @notice Factory for deploying Lido yield skimming strategies
 * @dev Inherits secure deterministic deployment from BaseStrategyFactory
 */
contract LidoStrategyFactory is BaseStrategyFactory {
    /// @notice wstETH token address on mainnet
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /**
     * @notice Deploys a new Lido strategy for the Yield Skimming Vault.
     * @dev Uses secure deterministic deployment with deployer-specific counters
     *      to prevent front-running attacks. Each deployer gets unique addresses.
     * @param _name The name of the vault token associated with the strategy.
     * @param _management The address of the management entity responsible for the strategy.
     * @param _keeper The address of the keeper responsible for maintaining the strategy.
     * @param _emergencyAdmin The address of the emergency admin for the strategy.
     * @param _donationAddress The address where donations from the strategy will be sent.
     * @param _enableBurning Whether to enable burning shares from dragon router during loss protection.
     * @param _tokenizedStrategyAddress Address of the tokenized strategy implementation
     * @param _allowDepositDuringLoss Whether to allow deposits during loss periods
     * @return strategyAddress The address of the newly deployed strategy contract.
     */
    function createStrategy(
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress,
        bool _allowDepositDuringLoss
    ) external returns (address strategyAddress) {
        bytes memory bytecode = abi.encodePacked(
            type(LidoStrategy).creationCode,
            abi.encode(
                WSTETH,
                _name,
                _management,
                _keeper,
                _emergencyAdmin,
                _donationAddress,
                _enableBurning,
                _tokenizedStrategyAddress,
                _allowDepositDuringLoss
            )
        );

        // Deploy using secure deterministic method from base
        strategyAddress = _deployStrategy(bytecode);
        
        // Record the deployment
        _recordStrategy(_name, _donationAddress, strategyAddress);
    }
}
