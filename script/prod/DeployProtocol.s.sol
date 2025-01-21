// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Safe} from "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import {SafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";

import {DeploySafe} from "script/deploy/DeploySafe.sol";
import {DeployDragonRouter} from "script/deploy/DeployDragonRouter.sol";
import {DeployModuleProxyFactory} from "script/deploy/DeployModuleProxyFactory.sol";
import {DeployDragonTokenizedStrategy} from "script/deploy/DeployDragonTokenizedStrategy.sol";
import {DeployMockStrategy} from "script/deploy/DeployMockStrategy.sol";
import {DeployHatsProtocol} from "script/deploy/DeployHatsProtocol.sol";

/**
 * @title DeployProtocol
 * @notice Production deployment script for Dragon Protocol core components
 * @dev This script handles the sequential deployment of all protocol components
 *      with proper security checks and verification steps
 */
contract DeployProtocol is Script {
    // Constants for Safe deployment
    address public constant SAFE_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address public constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    uint256 public constant SAFE_THRESHOLD = 1;
    uint256 public constant SAFE_TOTAL_OWNERS = 1;

    // Deployment scripts
    DeploySafe public deploySafe;
    DeployModuleProxyFactory public deployModuleProxyFactory;
    DeployDragonTokenizedStrategy public deployDragonTokenizedStrategy;
    DeployDragonRouter public deployDragonRouter;
    DeployHatsProtocol public deployHatsProtocol;
    DeployMockStrategy public deployMockStrategy;

    // Deployed contract addresses
    address public safeAddress;
    address public moduleProxyFactoryAddress;
    address public dragonTokenizedStrategyAddress;
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
        deployHatsProtocol = new DeployHatsProtocol();
        deployMockStrategy = new DeployMockStrategy();
    }

    function run() public {
        // Get deployer address from private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.rememberKey(deployerPrivateKey);
        
        console2.log("Starting deployment with deployer:", deployerAddress);
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Safe with single signer
        address[] memory owners = new address[](SAFE_TOTAL_OWNERS);
        owners[0] = deployerAddress;
        
        deploySafe.setUpSafeDeployParams(
            SAFE_SINGLETON,
            SAFE_PROXY_FACTORY,
            owners,
            SAFE_THRESHOLD
        );
        deploySafe.deploy();
        safeAddress = address(deploySafe.deployedSafe());
        if (safeAddress == address(0)) revert DeploymentFailed();
        
        // 2. Deploy Module Proxy Factory
        deployModuleProxyFactory.deploy();
        moduleProxyFactoryAddress = address(deployModuleProxyFactory.moduleProxyFactory());
        if (moduleProxyFactoryAddress == address(0)) revert DeploymentFailed();

        // 3. Deploy Hats Protocol
        deployHatsProtocol.deploy();
        
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

        vm.stopBroadcast();

        // Log deployment addresses
        console2.log("\nDeployment Summary:");
        console2.log("------------------");
        console2.log("Safe:", safeAddress);
        console2.log("Module Proxy Factory:", moduleProxyFactoryAddress);
        console2.log("Dragon Tokenized Strategy:", dragonTokenizedStrategyAddress);
        console2.log("Dragon Router:", dragonRouterAddress);
        console2.log("Mock Strategy:", mockStrategyAddress);
        console2.log("Hats Protocol:", address(deployHatsProtocol.HATS()));
        console2.log("Dragon Hatter:", address(deployHatsProtocol.dragonHatter()));

        // Verify deployments
        _verifyDeployments();
    }

    function _verifyDeployments() internal view {
        // Verify Safe setup
        Safe safe = Safe(payable(safeAddress));
        require(safe.getThreshold() == SAFE_THRESHOLD, "Invalid Safe threshold");
        require(safe.getOwners().length == SAFE_TOTAL_OWNERS, "Invalid Safe owners count");
        require(safe.isOwner(vm.addr(vm.envUint("PRIVATE_KEY"))), "Deployer not Safe owner");

        // Verify Mock Strategy is enabled on Safe
        require(safe.isModuleEnabled(mockStrategyAddress), "Strategy not enabled on Safe");

        // Additional security checks can be added here
        console2.log("\nAll deployments verified successfully!");
    }
} 