// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {ModuleProxyFactory} from "../src/dragons/ModuleProxyFactory.sol";
import {DeployModuleProxyFactory} from "script/deploy/ModuleProxyFactory.s.sol";
import {TestERC20} from "src/test/TestERC20.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import {DeploySafe} from "script/deploy/Safe.s.sol";
import {DeployDragonTokenizedStrategy} from "script/deploy/DragonTokenizedStrategy.s.sol";
import {DeployDragonRouter} from "script/deploy/DragonRouter.s.sol";
import {DragonTokenizedStrategy} from "src/dragons/vaults/DragonTokenizedStrategy.sol";

contract SetupIntegrationTest is DeploySafe, DeployDragonTokenizedStrategy, DeployDragonRouter, DeployModuleProxyFactory, Test, TestPlus {

    uint256 constant TEST_THRESHOLD = 3;
    uint256 constant TEST_TOTAL_OWNERS = 5;
    address constant SAFE_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    
    TestERC20 public token;

    /// ============ DeploySafe ===========================
    /// uint256 public threshold;
    /// uint256 public totalOwners;
    /// address[] public owners;
    /// address public safeSingleton;
    /// address public safeProxyFactory;
    /// Safe public deployedSafe;
    /// ===================================================

    
    /// ========== DeployDragonTokenizedStrategy ==========
    /// DragonTokenizedStrategy public dragonTokenizedStrategySingleton;
    /// ===================================================  

    /// ============ DeploySplitChecker ==================
    /// SplitChecker public splitCheckerSingleton;
    /// SplitChecker public splitCheckerProxy;
    /// ===================================================

    /// ============ DeployDragonRouter ==================
    /// DragonRouter public dragonRouterSingleton;
    /// DragonRouter public dragonRouterProxy;
    /// ===================================================

    /// ============ DeployModuleProxyFactory ============
    /// ModuleProxyFactory public moduleProxyFactory;
    /// ===================================================

    function addLabels() internal {
        vm.label(SAFE_SINGLETON, "Safe Singleton");
        vm.label(SAFE_PROXY_FACTORY, "Safe Proxy Factory");
        vm.label(address(deployedSafe), "Safe Proxy");
        vm.label(address(dragonTokenizedStrategySingleton), "DragonTokenizedStrategy Implementation");
        vm.label(address(splitCheckerSingleton), "SplitChecker Implementation");
        vm.label(address(splitCheckerProxy), "SplitChecker Proxy");
        vm.label(address(dragonRouterSingleton), "DragonRouter Implementation");
        vm.label(address(dragonRouterProxy), "DragonRouter Proxy");
        vm.label(address(moduleProxyFactory), "ModuleProxyFactory");
        //loop over owners
        for (uint256 i = 0; i < TEST_TOTAL_OWNERS; i++) {
            vm.label(owners[i], string.concat("Owner ", vm.toString(i + 1)));
        }
        vm.label(address(token), "Test Token");

    }

    function run() public override(DeploySafe, DeployDragonTokenizedStrategy, DeployDragonRouter, DeployModuleProxyFactory) {
        DeploySafe.run();
        DeployDragonTokenizedStrategy.run();
        DeployDragonRouter.run();
        DeployModuleProxyFactory.run();
    }

    function setUp() public virtual {
        // Fork mainnet
        vm.createSelectFork(vm.envString("TEST_RPC_URL"));

        // Create test owners and store their private keys
        address[] memory testOwners = _createTestOwners(TEST_TOTAL_OWNERS);

        // Set up Safe deployment parameters
        setUpSafeDeployParams(
            SAFE_SINGLETON,
            SAFE_PROXY_FACTORY,
            testOwners,
            TEST_THRESHOLD
        );

        run();

        // Deploy test token
        token = new TestERC20();

        // Verify deployment
        require(address(deployedSafe) != address(0), "Safe not deployed");
        require(deployedSafe.getThreshold() == TEST_THRESHOLD, "Invalid threshold");
        require(deployedSafe.getOwners().length == TEST_TOTAL_OWNERS, "Invalid number of owners");
        require(address(dragonTokenizedStrategySingleton) != address(0), "Strategy not deployed");
        require(address(splitCheckerSingleton) != address(0), "SplitChecker not deployed");
        require(address(dragonRouterSingleton) != address(0), "DragonRouter implementation not deployed");
        require(address(dragonRouterProxy) != address(0), "DragonRouter proxy not deployed");
        require(address(moduleProxyFactory) != address(0), "ModuleProxyFactory not deployed");

        addLabels();
    }
    

    /**
    * @notice Creates an array of test owner addresses and stores their private keys
    * @dev Uses _randomSigner() to generate deterministic addresses and private keys
    * @return _owners Array of owner addresses for Safe setup
    */    
    function _createTestOwners(uint256 _totalOwners) internal returns (address[] memory _owners) {
            _owners = new address[](_totalOwners);
            for (uint256 i = 0; i < _totalOwners; i++) {
                // Generate private key and address
                (address owner, uint256 privateKey) = _randomSigner();
                vm.rememberKey(privateKey);
                // Store owner and their private key
                _owners[i] = owner;
            }
        }

    /**
     * @notice Execute a transaction through the Safe with direct signing
     * @dev This uses vm.sign for testing purposes
     */
    function execTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint256[] memory signerIndices
    ) public {
        require(address(deployedSafe) != address(0), "Safe not deployed");
        require(signerIndices.length >= TEST_THRESHOLD, "Not enough signers");

        // Prepare transaction data
        bytes32 txHash = deployedSafe.getTransactionHash(
            to,
            value,
            data,
            Enum.Operation.Call,
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            uint256(deployedSafe.nonce())
        );

        // Collect signatures
        bytes memory signatures = new bytes(signerIndices.length * 65);
        uint256 pos = 0;
        
        for (uint256 i = 0; i < signerIndices.length; i++) {
            require(signerIndices[i] < TEST_TOTAL_OWNERS, "Invalid signer index");
            
            // Get the owner's private key from the mapping
            address owner = owners[signerIndices[i]];
            vm.startPrank(owner);
            // Sign with the owner's private key
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner, txHash);
            vm.stopPrank();
            assembly {
                mstore(add(signatures, add(pos, 32)), r)
                mstore(add(signatures, add(pos, 64)), s)
                mstore8(add(signatures, add(pos, 96)), v)
            }
            pos += 65;
        }

        // Execute transaction
        bool success = deployedSafe.execTransaction(
            to,
            value,
            data,
            Enum.Operation.Call,
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            signatures
        );

        require(success, "Transaction execution failed");
    }
}
