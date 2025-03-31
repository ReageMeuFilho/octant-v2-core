// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {DeployDragonRouter} from "script/deploy/DeployDragonRouter.sol";
import {DeployDragonTokenizedStrategy} from "script/deploy/DeployDragonTokenizedStrategy.sol";
import {DeployHatsProtocol} from "script/deploy/DeployHatsProtocol.sol";
import {DeployLinearAllowanceSingletonForGnosisSafe} from "script/deploy/DeployLinearAllowanceSingletonForGnosisSafe.sol";
import {DeployMockStrategy} from "script/deploy/DeployMockStrategy.sol";
import {DeployModuleProxyFactory} from "script/deploy/DeployModuleProxyFactory.sol";

/**
 * @title DeployProtocol
 * @notice Production deployment script for Dragon Protocol core components
 * @dev This script handles the sequential deployment of all protocol components
 */
contract DeployProtocol is Script {
    // Deployers
    DeployModuleProxyFactory public deployModuleProxyFactory;
    DeployLinearAllowanceSingletonForGnosisSafe public deployLinearAllowanceSingletonForGnosisSafe;
    DeployDragonTokenizedStrategy public deployDragonTokenizedStrategy;
    DeployDragonRouter public deployDragonRouter;
    DeployMockStrategy public deployMockStrategy;
    DeployHatsProtocol public deployHatsProtocol;

    // Deployed contract addresses
    address public moduleProxyFactoryAddress;
    address public linearAllowanceSingletonForGnosisSafeAddress;
    address public dragonTokenizedStrategyAddress;
    address public dragonRouterAddress;
    address public splitCheckerAddress;
    address public mockStrategySingletonAddress;
    address public mockTokenAddress;
    address public mockYieldSourceAddress;
    address public hatsAddress;

    error DeploymentFailed();

    function setUp() public {
        // Initialize deployment scripts
        deployModuleProxyFactory = new DeployModuleProxyFactory();
        deployLinearAllowanceSingletonForGnosisSafe = new DeployLinearAllowanceSingletonForGnosisSafe();
        deployDragonTokenizedStrategy = new DeployDragonTokenizedStrategy();
        deployDragonRouter = new DeployDragonRouter();
        deployMockStrategy = new DeployMockStrategy();
        deployHatsProtocol = new DeployHatsProtocol();
    }

    function run() public {
        setUp();

        // Deploy Module Proxy Factory
        deployModuleProxyFactory.deploy();
        moduleProxyFactoryAddress = address(deployModuleProxyFactory.moduleProxyFactory());
        if (moduleProxyFactoryAddress == address(0)) revert DeploymentFailed();

        // Deploy LinearAllowanceSingletonForGnosisSafe
        deployLinearAllowanceSingletonForGnosisSafe.deploy();
        linearAllowanceSingletonForGnosisSafeAddress = address(deployLinearAllowanceSingletonForGnosisSafe.linearAllowanceSingletonForGnosisSafe());
        if (linearAllowanceSingletonForGnosisSafeAddress == address(0)) revert DeploymentFailed();

        // Deploy Dragon Tokenized Strategy Implementation
        deployDragonTokenizedStrategy.deploy();
        dragonTokenizedStrategyAddress = address(deployDragonTokenizedStrategy.dragonTokenizedStrategySingleton());
        if (dragonTokenizedStrategyAddress == address(0)) revert DeploymentFailed();

        // Deploy Dragon Router
        deployDragonRouter.deploy();
        dragonRouterAddress = address(deployDragonRouter.dragonRouterProxy());
        if (dragonRouterAddress == address(0)) revert DeploymentFailed();
        splitCheckerAddress = address(deployDragonRouter.splitCheckerProxy());

        // Deploy Mock Strategy
        deployMockStrategy.deploy();
        mockStrategySingletonAddress = address(deployMockStrategy.mockStrategySingleton());
        if (mockStrategySingletonAddress == address(0)) revert DeploymentFailed();
        mockTokenAddress = address(deployMockStrategy.token());
        mockYieldSourceAddress = address(deployMockStrategy.mockYieldSource());

        // Deploy HATS
        deployHatsProtocol.deploy();
        hatsAddress = address(deployHatsProtocol.hats());

        // Log deployment addresses
        console2.log("\nDeployment Summary:");
        console2.log("------------------");
        console2.log("Module Proxy Factory:      ", moduleProxyFactoryAddress);
        console2.log("Dragon Tokenized Strategy: ", dragonTokenizedStrategyAddress);
        console2.log("Dragon Router:             ", dragonRouterAddress);
        console2.log("Split Checker:             ", splitCheckerAddress);
        console2.log("Mock Strategy Singleton:   ", mockStrategySingletonAddress);
        console2.log("Mock token:                ", mockTokenAddress);
        console2.log("Mock yield source:         ", mockYieldSourceAddress);
        console2.log("Linear Allowance Singleton:", linearAllowanceSingletonForGnosisSafeAddress);
        console2.log("Hats contract:             ", hatsAddress);
        console2.log("DragonHatter:              ", address(deployHatsProtocol.dragonHatter()));
        console2.log("Top Hat ID:                ", deployHatsProtocol.topHatId());
        console2.log("Autonomous Admin Hat ID:   ", deployHatsProtocol.autonomousAdminHatId());
        console2.log("Dragon Admin Hat ID:       ", deployHatsProtocol.dragonAdminHatId());
        console2.log("Branch Hat ID:             ", deployHatsProtocol.branchHatId());
        console2.log("------------------");
        console2.log("ENV DRAGON_TOKENIZED_STRATEGY_ADDRESS", dragonTokenizedStrategyAddress);
        console2.log("ENV DRAGON_ROUTER_ADDRESS", dragonRouterAddress);
        console2.log("ENV SPLIT_CHECKER_ADDRESS", splitCheckerAddress);
        console2.log("ENV MOCK_STRATEGY_SINGLETON_ADDRESS", mockStrategySingletonAddress);
        console2.log("ENV MOCK_TOKEN_ADDRESS", mockTokenAddress);
        console2.log("ENV MOCK_YIELD_SOURCE_ADDRESS", mockYieldSourceAddress);
        console2.log("ENV MODULE_PROXY_FACTORY_ADDRESS", moduleProxyFactoryAddress);
    }
}
