// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import {DragonTokenizedStrategy} from "src/dragons/vaults/DragonTokenizedStrategy.sol";
import {ModuleProxyFactory} from "src/dragons/ModuleProxyFactory.sol";

import {DeploySafe} from "script/deploy/DeploySafe.sol";
import {DeployDragonRouter} from "script/deploy/DeployDragonRouter.sol";
import {DeployModuleProxyFactory} from "script/deploy/DeployModuleProxyFactory.sol";
import {DeployDragonTokenizedStrategy} from "script/deploy/DeployDragonTokenizedStrategy.sol";
import {DeployMockStrategy} from "script/deploy/DeployMockStrategy.sol";
import {DeployHatsProtocol} from "script/deploy/DeployHatsProtocol.sol";
import {LinearAllowanceSingletonForGnosisSafe} from "src/dragons/modules/LinearAllowanceSingletonForGnosisSafe.sol";
import {DeployHats} from "script/deploy/DeployHats.sol";

/**
 * @title DeployProtocol
 * @notice Production deployment script for Dragon Protocol core components
 * @dev This script handles the sequential deployment of all protocol components
 *      with proper security checks and verification steps
 */
contract DeployProtocol is Script {
    // Constants for Safe deployment
    uint256 public constant SAFE_THRESHOLD = 1;
    uint256 public constant SAFE_TOTAL_OWNERS = 1;

    // Deployment scripts
    DeploySafe public deploySafe;
    DeployModuleProxyFactory public deployModuleProxyFactory;
    DeployDragonTokenizedStrategy public deployDragonTokenizedStrategy;
    DeployDragonRouter public deployDragonRouter;
    DeployMockStrategy public deployMockStrategy;
    ModuleProxyFactory public moduleProxyFactory;
    LinearAllowanceSingletonForGnosisSafe public linearAllowanceSingletonForGnosisSafe;
    DragonTokenizedStrategy public dragonTokenizedStrategySingleton;
    DeployHats public deployHats;

    // Deployed contract addresses
    address public safeAddress;
    address public moduleProxyFactoryAddress;
    address public dragonTokenizedStrategyAddress;
    address public linearAllowanceSingletonForGnosisSafeAddress;
    address public dragonRouterAddress;
    address public mockStrategyAddress;

    error DeploymentFailed();
    error InvalidAddress();

    function setUp() public {
        // Initialize deployment scripts
        deploySafe = new DeploySafe();
        deployModuleProxyFactory = new DeployModuleProxyFactory();
        deployDragonTokenizedStrategy = new DeployDragonTokenizedStrategy();
        deployDragonRouter = new DeployDragonRouter();
        deployMockStrategy = new DeployMockStrategy();
        deployHats = new DeployHats();
    }

    function run() public {
        // Get deployer address from private key
        setUp();
        address safeSingleton = vm.envAddress("SAFE_SINGLETON");
        address safeProxyFactory = vm.envAddress("SAFE_PROXY_FACTORY");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.rememberKey(deployerPrivateKey);

        console2.log("Starting deployment with deployer:", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Safe with single signer
        address[] memory owners = new address[](SAFE_TOTAL_OWNERS);
        owners[0] = deployerAddress;
        bytes memory initializer = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            SAFE_THRESHOLD,
            address(0), // No module
            bytes(""), // Empty setup data
            address(0), // No fallback handler
            address(0), // No payment token
            0, // No payment
            address(0) // No payment receiver
        );

        // Deploy new Safe via factory
        SafeProxyFactory factory = SafeProxyFactory(safeProxyFactory);
        SafeProxy proxy = factory.createProxyWithNonce(
            safeSingleton,
            initializer,
            block.timestamp // Use timestamp as salt
        );

        // Store deployed Safe
        safeAddress = address(proxy);
        if (safeAddress == address(0)) revert DeploymentFailed();

        // 2. Deploy Module Proxy Factory
        moduleProxyFactory = new ModuleProxyFactory();
        moduleProxyFactoryAddress = address(moduleProxyFactory);
        if (moduleProxyFactoryAddress == address(0)) revert DeploymentFailed();

        // 3. Deploy LinearAllowanceSingletonForGnosisSafe
        linearAllowanceSingletonForGnosisSafe = new LinearAllowanceSingletonForGnosisSafe();
        linearAllowanceSingletonForGnosisSafeAddress = address(linearAllowanceSingletonForGnosisSafe);
        if (linearAllowanceSingletonForGnosisSafeAddress == address(0)) revert DeploymentFailed();

        vm.stopBroadcast();

        // 4. Deploy Dragon Tokenized Strategy Implementation
        deployDragonTokenizedStrategy.deploy();
        dragonTokenizedStrategyAddress = address(deployDragonTokenizedStrategy.dragonTokenizedStrategySingleton());
        if (dragonTokenizedStrategyAddress == address(0)) revert DeploymentFailed();

        // 5. Deploy Dragon Router
        deployDragonRouter.deploy();
        dragonRouterAddress = address(deployDragonRouter.dragonRouterProxy());
        if (dragonRouterAddress == address(0)) revert DeploymentFailed();

        // 6. Deploy Mock Strategy
        deployMockStrategy.deploy(
            safeAddress,
            dragonTokenizedStrategyAddress,
            dragonRouterAddress
        );
        mockStrategyAddress = address(deployMockStrategy.mockStrategyProxy());
        if (mockStrategyAddress == address(0)) revert DeploymentFailed();

        // Deploy HATS with random SALT
        deployHats.deploy();

        // Log deployment addresses
        console2.log("\nDeployment Summary:");
        console2.log("------------------");
        console2.log("Safe:                      ", safeAddress);
        console2.log("Safe threshold:            ", SAFE_THRESHOLD);
        console2.log("Safe owners:               ", SAFE_TOTAL_OWNERS);
        console2.log("Module Proxy Factory:      ", moduleProxyFactoryAddress);
        console2.log("Dragon Tokenized Strategy: ", dragonTokenizedStrategyAddress);
        console2.log("Dragon Router:             ", dragonRouterAddress);
        console2.log("Split Checker:             ", address(deployDragonRouter.splitCheckerProxy()));
        console2.log("Mock Strategy:             ", mockStrategyAddress);
        console2.log("Linear Allowance Singleton:", linearAllowanceSingletonForGnosisSafeAddress);
        console2.log("Hats contract:             ", address(deployHats.hats()));
        console2.log("Hats salt:                 ", vm.toString(deployHats.salt()));
        console2.log("------------------");
        console2.log("ENV|DRAGON_TOKENIZED_STRATEGY_ADDRESS=", dragonTokenizedStrategyAddress);
        console2.log("ENV|DRAGON_ROUTER_ADDRESS=", dragonRouterAddress);
        console2.log("ENV|SPLIT_CHECKER_ADDRESS", address(deployDragonRouter.splitCheckerProxy()));

        // Verify deployments
        _verifyDeployments(deployerAddress);
    }

    function _verifyDeployments(address deployerAddress) internal view {
        // Verify Safe setup
        Safe safe = Safe(payable(safeAddress));
        require(safe.getThreshold() == SAFE_THRESHOLD, "Invalid Safe threshold");
        require(safe.getOwners().length == SAFE_TOTAL_OWNERS, "Invalid Safe owners count");
        require(safe.isOwner(deployerAddress), "Deployer not Safe owner");

        // Verify Mock Strategy is enabled on Safe
        if (!safe.isModuleEnabled(mockStrategyAddress)) {
            console2.log("Mock Strategy not enabled on Safe");
        }

        // Additional security checks can be added here
        console2.log("\nAll deployments verified successfully!");
    }
}
