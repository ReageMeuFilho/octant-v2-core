// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import { MultistrategyVaultFactory } from "src/factories/MultistrategyVaultFactory.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";

contract DeployVaults is Script {
    MultistrategyVaultFactory vaultFactory;
    address public factoryAddress;

    // Vault parameters
    address public asset;
    string public vaultName;
    string public vaultSymbol;
    address public roleManager;
    uint256 public profitMaxUnlockTime;

    function run() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        deployVault();
        vm.stopBroadcast();
    }

    function deployVault() internal returns (address) {
        // Get factory address
        try vm.prompt("Enter VaultFactory address") returns (string memory res) {
            factoryAddress = vm.parseAddress(res);
            vaultFactory = MultistrategyVaultFactory(factoryAddress);
            console.log("Using VaultFactory at:", factoryAddress);
        } catch (bytes memory) {
            revert("Invalid VaultFactory address");
        }

        // Check if factory is shutdown
        if (vaultFactory.shutdown()) {
            revert("VaultFactory is shutdown");
        }

        // Get asset address
        try vm.prompt("Enter asset address for the vault") returns (string memory res) {
            asset = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Invalid asset address");
        }

        // Get vault name
        try vm.prompt("Enter vault name") returns (string memory res) {
            vaultName = res;
        } catch (bytes memory) {
            revert("Invalid vault name");
        }

        // Get vault symbol
        try vm.prompt("Enter vault symbol") returns (string memory res) {
            vaultSymbol = res;
        } catch (bytes memory) {
            revert("Invalid vault symbol");
        }

        // Get role manager address
        try vm.prompt("Enter role manager address") returns (string memory res) {
            roleManager = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Invalid role manager address");
        }

        // Get profit max unlock time
        try vm.prompt("Enter profit max unlock time in seconds (default: 604800 - 7 days)") returns (
            string memory res
        ) {
            if (keccak256(abi.encode(res)) != keccak256(abi.encode(""))) {
                profitMaxUnlockTime = vm.parseUint(res);
            } else {
                profitMaxUnlockTime = 604800; // 7 days in seconds as default
            }
        } catch (bytes memory) {
            revert("Invalid profit max unlock time");
        }

        // Deploy vault through factory
        address vaultAddress = vaultFactory.deployNewVault(
            asset,
            vaultName,
            vaultSymbol,
            roleManager,
            profitMaxUnlockTime
        );

        console.log("Vault successfully deployed at:", vaultAddress);
        console.log("Vault details:");
        console.log("  - Asset:", asset);
        console.log("  - Name:", vaultName);
        console.log("  - Symbol:", vaultSymbol);
        console.log("  - Role Manager:", roleManager);
        console.log("  - Profit Max Unlock Time:", profitMaxUnlockTime);

        // Check that the vault has the expected values
        IMultistrategyVault vault = IMultistrategyVault(vaultAddress);
        console.log("Vault verification:");
        console.log("  - API Version:", vault.apiVersion());
        console.log("  - Asset matches:", vault.asset() == asset);
        console.log("  - Role Manager matches:", vault.roleManager() == roleManager);
        console.log("  - Profit Max Unlock Time matches:", vault.profitMaxUnlockTime() == profitMaxUnlockTime);

        return vaultAddress;
    }

    function deployMultipleVaults(uint256 count) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get factory address only once
        try vm.prompt("Enter VaultFactory address") returns (string memory res) {
            factoryAddress = vm.parseAddress(res);
            vaultFactory = MultistrategyVaultFactory(factoryAddress);
            console.log("Using VaultFactory at:", factoryAddress);
        } catch (bytes memory) {
            revert("Invalid VaultFactory address");
        }

        // Check if factory is shutdown
        if (vaultFactory.shutdown()) {
            revert("VaultFactory is shutdown");
        }

        // Get role manager address (assumed same for all vaults)
        try vm.prompt("Enter role manager address (used for all vaults)") returns (string memory res) {
            roleManager = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Invalid role manager address");
        }

        // Get profit max unlock time (assumed same for all vaults)
        try vm.prompt("Enter profit max unlock time in seconds (default: 604800 - 7 days)") returns (
            string memory res
        ) {
            if (keccak256(abi.encode(res)) != keccak256(abi.encode(""))) {
                profitMaxUnlockTime = vm.parseUint(res);
            } else {
                profitMaxUnlockTime = 604800; // 7 days in seconds as default
            }
        } catch (bytes memory) {
            revert("Invalid profit max unlock time");
        }

        // Deploy multiple vaults
        address[] memory deployedVaults = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            // Get asset address
            try vm.prompt(string.concat("Enter asset address for vault ", vm.toString(i + 1))) returns (
                string memory res
            ) {
                asset = vm.parseAddress(res);
            } catch (bytes memory) {
                revert("Invalid asset address");
            }

            // Get vault name
            try vm.prompt(string.concat("Enter name for vault ", vm.toString(i + 1))) returns (string memory res) {
                vaultName = res;
            } catch (bytes memory) {
                revert("Invalid vault name");
            }

            // Get vault symbol
            try vm.prompt(string.concat("Enter symbol for vault ", vm.toString(i + 1))) returns (string memory res) {
                vaultSymbol = res;
            } catch (bytes memory) {
                revert("Invalid vault symbol");
            }

            // Deploy vault through factory
            deployedVaults[i] = vaultFactory.deployNewVault(
                asset,
                vaultName,
                vaultSymbol,
                roleManager,
                profitMaxUnlockTime
            );

            console.log(string.concat("Vault ", vm.toString(i + 1), " deployed at:"), deployedVaults[i]);
        }

        console.log("All vaults deployed successfully!");
        for (uint256 i = 0; i < count; i++) {
            console.log(string.concat("Vault ", vm.toString(i + 1), ":"), deployedVaults[i]);
        }

        vm.stopBroadcast();
    }
}
