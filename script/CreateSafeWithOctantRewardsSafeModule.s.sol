// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import "forge-std/Script.sol";

contract CreateSafeWithModule is Script {
    address[] public owners;
    uint256 public threshold;
    address public safeSingleton;
    address public proxyFactory;
    address public moduleFactory;
    address public module;

    address keeper;
    address treasury;
    address dragonRouter;
    uint256 totalValidators;

    function setUp() public {
        // Initialize owners and threshold
        owners = [vm.envAddress("OWNER")];
        threshold = vm.envUint("SAFE_THRESHOLD");

        // Set the addresses for the Safe singleton and Proxy Factory
        safeSingleton = vm.envAddress("SAFE_SINGLETON");
        proxyFactory = vm.envAddress("SAFE_PROXY_FACTORY");

        moduleFactory = vm.envAddress("MODULE_FACTORY");
        module = vm.envAddress("MODULE");
        keeper = vm.envAddress("KEEPER");
        treasury = vm.envAddress("TREASURY");
        dragonRouter = vm.envAddress("DRAGON_ROUTER");
        totalValidators = vm.envUint("TOTAL_VALIDATORS");
    }

    function run() public {
        vm.startBroadcast();

        // Deploy a new Safe Multisig using the Proxy Factory
        SafeProxyFactory factory = SafeProxyFactory(proxyFactory);
        bytes memory data = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            threshold,
            moduleFactory,
            abi.encodeWithSignature(
                "deployAndEnableModuleFromSafe(address,bytes,uint256)",
                module,
                abi.encode(keeper, treasury, dragonRouter, totalValidators),
                block.timestamp
            ),
            address(0),
            address(0),
            0,
            address(0)
        );

        SafeProxy proxy = factory.createProxyWithNonce(safeSingleton, data, block.timestamp);

        vm.stopBroadcast();

        // Log the address of the newly deployed Safe
        console.log("Safe deployed at:", address(proxy));
    }
}
