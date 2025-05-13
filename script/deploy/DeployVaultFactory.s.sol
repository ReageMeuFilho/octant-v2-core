// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "src/dragons/vaults/Vault.sol";
import "src/dragons/vaults/VaultFactory.sol";

contract DeployVaultFactory is Script {
    Vault vaultImplementation;
    VaultFactory vaultFactory;
    string factoryName;
    address governance;

    function run() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        deployVaultFactory();
        vm.stopBroadcast();
    }

    function deployVaultFactory() internal returns (address) {
        // Deploy Vault implementation first
        try
            vm.prompt(
                "Is the Vault implementation already deployed? (if yes, provide the address) / (if no, provide 'no')"
            )
        returns (string memory res) {
            if (keccak256(abi.encode(res)) == keccak256(abi.encode("no"))) {
                vaultImplementation = new Vault();
                console.log("Vault implementation deployed at:", address(vaultImplementation));
            } else {
                vaultImplementation = Vault(payable(vm.parseAddress(res)));
                console.log("Using existing Vault implementation at:", address(vaultImplementation));
            }
        } catch (bytes memory) {
            revert("Invalid Vault implementation response");
        }

        // Get factory name
        try vm.prompt("Enter the name for the VaultFactory") returns (string memory res) {
            factoryName = res;
        } catch (bytes memory) {
            revert("Invalid factory name");
        }

        // Get governance address
        try vm.prompt("Enter governance address") returns (string memory res) {
            governance = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Invalid governance address");
        }

        // Deploy VaultFactory
        vaultFactory = new VaultFactory(factoryName, address(vaultImplementation), governance);

        console.log("VaultFactory successfully deployed at:", address(vaultFactory));
        console.log("VaultFactory details:");
        console.log("  - Name:", factoryName);
        console.log("  - Vault Original:", address(vaultImplementation));
        console.log("  - Governance:", governance);
        console.log("  - API Version:", vaultFactory.API_VERSION());

        return address(vaultFactory);
    }
}
