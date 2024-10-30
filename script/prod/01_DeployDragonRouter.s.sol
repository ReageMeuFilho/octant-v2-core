// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {DragonRouter} from "../../src/dragons/DragonRouter.sol";
import {SplitChecker} from "../../src/dragons/SplitChecker.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployDragonRouter is Script {
    address[] public owners;
    uint256 public threshold;
    address public safeSingleton;
    address public proxyFactory;
    address public moduleFactory;
    address public module;

    address keeper;
    address treasury;
    address dragonRouter;

    uint256 maxOpexSplit = 0.5e18;
    uint256 minMetapoolSplit = 0.05e18;

    function setUp() public {
        // Initialize owners and threshold
        owners = [vm.envAddress("OWNER")];
        threshold = vm.envUint("THRESHOLD");
    }

    function run() public {
        vm.startBroadcast();

        // Deploy DragonRouter implementation
        DragonRouter dragonRouterImplementation = new DragonRouter();

        // Deploy SplitChecker implementation
        SplitChecker splitCheckerImplementation = new SplitChecker();

        // Deploy ProxyAdmin for SplitChecker proxy
        ProxyAdmin splitCheckerProxyAdmin = new ProxyAdmin(vm.envAddress("PROXY_ADMIN_OWNER"));

        // Deploy TransparentProxy for SplitChecker
        TransparentUpgradeableProxy splitCheckerProxy = new TransparentUpgradeableProxy(
            address(splitCheckerImplementation),
            address(splitCheckerProxyAdmin),
            abi.encodeCall(SplitChecker.initialize, (vm.envAddress("GOVERNANCE"), maxOpexSplit, minMetapoolSplit))
        );

        // Deploy TransparentProxy for DragonRouter
        bytes memory initData = abi.encode(
            address(this), // owner 
            abi.encode(
                new address[](0), // initial strategies array
                new address[](0), // initial assets array
                vm.envAddress("GOVERNANCE"), // governance address
                address(splitCheckerProxy), // split checker address  
                vm.envAddress("OPEX_VAULT"), // opex vault address
                vm.envAddress("METAPOOL") // metapool address
            )
        );

        // Deploy ProxyAdmin for DragonRouter proxy
        ProxyAdmin proxyAdmin = new ProxyAdmin(vm.envAddress("PROXY_ADMIN_OWNER"));

        // Deploy TransparentProxy for DragonRouter
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(dragonRouterImplementation),
            address(proxyAdmin), // admin
            abi.encodeCall(DragonRouter.setUp, (initData))
        );

        vm.stopBroadcast();

        // Log the address of the newly deployed contracts
        console.log("Split Checker Implementation deployed at:", address(splitCheckerImplementation));
        console.log("Split Checker Proxy deployed at:", address(splitCheckerProxy));
        console.log("Split Checker Proxy Admin deployed at:", address(splitCheckerProxyAdmin), "with owner:", vm.envAddress("PROXY_ADMIN_OWNER"));

        console.log("Dragon Router Implementation deployed at:", address(dragonRouterImplementation));
        console.log("Dragon Router deployed at:", address(proxy));
        console.log("Dragon Router Proxy Admin deployed at:", address(proxyAdmin), "with owner:", vm.envAddress("PROXY_ADMIN_OWNER"));
    }
}
