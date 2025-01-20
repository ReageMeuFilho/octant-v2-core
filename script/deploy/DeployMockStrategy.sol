// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {console2} from "forge-std/Test.sol";
import {ModuleProxyFactory} from "src/dragons/ModuleProxyFactory.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {MockYieldSource} from "test/mocks/MockYieldSource.sol";
import {DeployModuleProxyFactory} from "./DeployModuleProxyFactory.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {ISafe} from "src/interfaces/Safe.sol";
import {IMockStrategy} from "test/mocks/IMockStrategy.sol";

contract DeployMockStrategy is DeployModuleProxyFactory {
    // DeployModuleProxyFactory public moduleProxyFactory;
    MockStrategy public mockStrategySingleton;
    IMockStrategy public mockStrategyProxy;
    MockYieldSource public mockYieldSource;
    MockERC20 public token;

    address public safeAddress;
    address public dragonTokenizedStrategyAddress;
    address public dragonRouterProxyAddress;

    function deploy(
        address _safeAddress,
        address _dragonTokenizedStrategyAddress,
        address _dragonRouterProxyAddress
    ) public virtual {
        // Store addresses in storage
        safeAddress = _safeAddress;
        dragonTokenizedStrategyAddress = _dragonTokenizedStrategyAddress;
        dragonRouterProxyAddress = _dragonRouterProxyAddress;

        // Deploy module proxy factory first
        DeployModuleProxyFactory.deploy();
        
        // Deploy test token
        token = new MockERC20();
        
        // Deploy implementation
        mockStrategySingleton = new MockStrategy();

        // Deploy mock yield source
        mockYieldSource = new MockYieldSource(address(token));

        uint256 _maxReportDelay = 1 days;
        string memory _name = "Mock Dragon Strategy";

        // console2.log("Safe Address:", safeAddress);
        // console2.log("Dragon Tokenized Strategy Address:", dragonTokenizedStrategyAddress);
        // console2.log("Mock Token:", address(token));
        // console2.log("MockYieldSource:", address(mockYieldSource));
        // console2.log("Management:", safeAddress);
        // console2.log("Keeper:", safeAddress);
        // console2.log("Dragon Router Proxy Address:", dragonRouterProxyAddress);
        // console2.log("Max Report Delay:", _maxReportDelay);
        // console2.log("Name:", _name);
        // console2.log("MockStrategy Implementation:", address(mockStrategySingleton));

        // Prepare initialization data
        // First encode the strategy initialization parameters
        bytes memory strategyParams = abi.encode(
            dragonTokenizedStrategyAddress,
            address(token),
            address(mockYieldSource),
            safeAddress, // management
            safeAddress, // keeper
            dragonRouterProxyAddress,
            _maxReportDelay, // maxReportDelay
            _name,
            safeAddress // regenGovernance
        );

        // Then encode the full initialization call with owner and params
        bytes memory initData = abi.encodeWithSignature(
            "setUp(bytes)", 
            abi.encode(safeAddress, strategyParams)
        );

        // Deploy and enable module on safe
        address proxy = moduleProxyFactory.deployModule(
            address(mockStrategySingleton),
            initData,
            block.timestamp
        );
        mockStrategyProxy = IMockStrategy(payable(address(proxy)));
        
        ISafe(safeAddress).enableModule(address(mockStrategyProxy));

        // Log deployments
        // console2.log("MockStrategy Implementation:", address(mockStrategySingleton));
        // console2.log("MockStrategy Proxy:", address(mockStrategyProxy));
        // console2.log("MockYieldSource:", address(mockYieldSource));
        // console2.log("Mock Token:", address(token));
        // console2.log("library address", address(mockStrategyProxy.tokenizedStrategyImplementation()));
        // console2.log("hats initialized", dragonTokenizedStrategyAddress);
    }
}
