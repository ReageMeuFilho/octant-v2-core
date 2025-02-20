// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {NonfungibleDepositManager} from "src/dragons/eth2StakeVault/NonfungibleDepositManager.sol";
import {Eth2StakeVaultHarness} from "src/dragons/eth2StakeVault/Eth2StakeVaultHarness.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DeployNonfungibleDepositManager
 * @notice Deployment script for NonfungibleDepositManager contract
 * @dev Deploys the NonfungibleDepositManager contract
 */
contract DeployNonfungibleDepositManager is Test {
    /// @notice The deployed NonfungibleDepositManager contract
    Eth2StakeVaultHarness public nonfungibleDepositManager;

    /**
     * @notice Deploy the ETH2StakeVault contract
     * @dev This function is virtual to allow test contracts to override it
     */
    function deploy() public virtual {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the ETH2StakeVault contract with NFT visualization
        nonfungibleDepositManager = new Eth2StakeVaultHarness();

        // Label the contract for better trace outputs
        vm.label(address(nonfungibleDepositManager), "NonfungibleDepositManager");

        vm.stopBroadcast();
    }
}


