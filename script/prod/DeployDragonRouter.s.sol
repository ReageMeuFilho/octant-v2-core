// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import { DragonRouter } from "../../src/zodiac-core/DragonRouter.sol";
import { SplitChecker } from "../../src/zodiac-core/SplitChecker.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployDragonRouter is Script {
    // default splits
    uint256 maxOpexSplit = 0.5e18;
    uint256 minMetapoolSplit = 0.05e18;

    SplitChecker splitCheckerImplementation;
    ProxyAdmin splitCheckerProxyAdmin;
    TransparentUpgradeableProxy splitCheckerProxy;
    DragonRouter dragonRouterImplementation;
    address proxyAdminOwner;
    address governance;
    address opexVault;
    address metapool;

    function run() public virtual {
        vm.startBroadcast();
        deployDragonRouter();
        vm.stopBroadcast();
    }

    function deployDragonRouter() internal returns (address) {
        try
            vm.prompt(
                "Is the dragon router implementation already deployed? (if yes, provide the address) / (if no, provide 'no')"
            )
        returns (string memory res) {
            if (keccak256(abi.encode(res)) == keccak256(abi.encode("no"))) {
                dragonRouterImplementation = new DragonRouter();
                console.log("Dragon Router Implementation deployed at:", address(dragonRouterImplementation));
            } else {
                dragonRouterImplementation = DragonRouter(payable(vm.parseAddress(res)));
            }
        } catch (bytes memory) {
            revert("Invalid Dragon Router Deployment Response");
        }

        try
            vm.prompt("Is the split checker already deployed? (if yes, provide the address) / (if no, provide 'no')")
        returns (string memory res) {
            if (keccak256(abi.encode(res)) == keccak256(abi.encode("no"))) {
                try vm.prompt("Enter Proxy Admin Owner Address") returns (string memory proxyAdminRes) {
                    proxyAdminOwner = vm.parseAddress(proxyAdminRes);
                } catch (bytes memory) {
                    revert("Invalid Proxy Admin Owner Address");
                }
                try vm.prompt("Enter Octant Governance Address") returns (string memory governanceRes) {
                    governance = vm.parseAddress(governanceRes);
                } catch (bytes memory) {
                    revert("Invalid Octant Governance Address");
                }

                try vm.prompt("Enter Max Opex Split (as a percentage, default: 0.5e18)") returns (
                    string memory opexSplitRes
                ) {
                    if (keccak256(abi.encode(opexSplitRes)) != keccak256(abi.encode(""))) {
                        maxOpexSplit = vm.parseUint(opexSplitRes);
                    }
                } catch (bytes memory) {
                    revert("Invalid Max Opex Split");
                }

                try vm.prompt("Enter Min Metapool Split (as a percentage, default: 0.05e18)") returns (
                    string memory metapoolSplitRes
                ) {
                    if (keccak256(abi.encode(metapoolSplitRes)) != keccak256(abi.encode(""))) {
                        minMetapoolSplit = vm.parseUint(metapoolSplitRes);
                    }
                } catch (bytes memory) {
                    revert("Invalid Min Metapool Split");
                }

                // Deploy SplitChecker implementation
                splitCheckerImplementation = new SplitChecker();

                // Deploy ProxyAdmin for SplitChecker proxy
                splitCheckerProxyAdmin = new ProxyAdmin(proxyAdminOwner);

                // Deploy TransparentProxy for SplitChecker
                splitCheckerProxy = new TransparentUpgradeableProxy(
                    address(splitCheckerImplementation),
                    address(splitCheckerProxyAdmin),
                    abi.encodeCall(SplitChecker.initialize, (governance, maxOpexSplit, minMetapoolSplit))
                );
                console.log("Split Checker Implementation deployed at:", address(splitCheckerImplementation));
                console.log("Split Checker Proxy deployed at:", address(splitCheckerProxy));
                console.log(
                    "Split Checker Proxy Admin deployed at:",
                    address(splitCheckerProxyAdmin),
                    "with owner:",
                    proxyAdminOwner
                );
            } else {
                splitCheckerProxy = TransparentUpgradeableProxy(payable(vm.parseAddress(res)));
            }
        } catch (bytes memory) {
            revert("Invalid Split Checker Deployment Response");
        }

        try vm.prompt("Enter Opex Vault Address") returns (string memory res) {
            opexVault = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Invalid Opex Vault Address");
        }

        try vm.prompt("Enter Metapool Address") returns (string memory res) {
            metapool = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Invalid Metapool Address");
        }

        // Deploy TransparentProxy for DragonRouter
        bytes memory initData = abi.encode(
            address(this), // owner
            abi.encode(
                new address[](0), // initial strategies array
                new address[](0), // initial assets array
                governance, // governance address
                address(splitCheckerProxy), // split checker address
                opexVault, // opex vault address
                metapool // metapool address
            )
        );

        // Deploy ProxyAdmin for DragonRouter proxy
        ProxyAdmin proxyAdmin = new ProxyAdmin(proxyAdminOwner);

        // Deploy TransparentProxy for DragonRouter
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(dragonRouterImplementation),
            address(proxyAdmin), // admin
            abi.encodeCall(DragonRouter.setUp, (initData))
        );

        // Log the address of the newly deployed contracts
        console.log("Dragon Router deployed at:", address(proxy));
        console.log("Dragon Router Proxy Admin deployed at:", address(proxyAdmin), "with owner:", proxyAdminOwner);

        return address(proxy);
    }
}
