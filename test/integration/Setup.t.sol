// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {DeploySafe} from "script/deploy/DeploySafe.sol";
import {DeployDragonRouter} from "script/deploy/DeployDragonRouter.sol";
import {DeployModuleProxyFactory} from "script/deploy/DeployModuleProxyFactory.sol";
import {DeployDragonTokenizedStrategy} from "script/deploy/DeployDragonTokenizedStrategy.sol";
import {DeployHatsProtocol} from "script/deploy/DeployHatsProtocol.sol";

contract SetupIntegrationTest is
    DeploySafe,
    DeployDragonTokenizedStrategy,
    DeployDragonRouter,
    DeployModuleProxyFactory,
    DeployHatsProtocol,
    TestPlus
{
    uint256 constant TEST_THRESHOLD = 3;
    uint256 constant TEST_TOTAL_OWNERS = 5;
    address constant SAFE_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    
    MockERC20 public token;

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

    /// ============ DeployHatsProtocol ===================
    /// Hats public hats;
    /// DragonHatter public dragonHatter;
    /// uint256 public topHatId;
    /// uint256 public autonomousAdminHatId;
    /// uint256 public dragonAdminHatId;
    /// uint256 public branchHatId;
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

        // Add Hats Protocol labels
        vm.label(address(HATS), "Hats Protocol");
        vm.label(address(dragonHatter), "Dragon Hatter");
    }

    function deploy()
        public
        override(
            DeploySafe, DeployDragonTokenizedStrategy, DeployDragonRouter, DeployModuleProxyFactory, DeployHatsProtocol
        )
    {
        // Deploy Safe first as it will be the admin
        DeploySafe.deploy();

        // Deploy Hats Protocol and setup roles
        DeployHatsProtocol.deploy();

        // Deploy remaining components
        DeployDragonTokenizedStrategy.deploy();
        DeployDragonRouter.deploy();
        DeployModuleProxyFactory.deploy();
    }

    function setUp() public virtual {
        // Fork mainnet
        vm.createSelectFork(vm.envString("TEST_RPC_URL"));

        // Create test owners and store their private keys
        address[] memory testOwners = _createTestOwners(TEST_TOTAL_OWNERS);

        // Set up Safe deployment parameters
        setUpSafeDeployParams(SAFE_SINGLETON, SAFE_PROXY_FACTORY, testOwners, TEST_THRESHOLD);

        deploy();

        // Deploy test token
        token = new MockERC20();

        // Verify deployment
        require(address(deployedSafe) != address(0), "Safe not deployed");
        require(deployedSafe.getThreshold() == TEST_THRESHOLD, "Invalid threshold");
        require(deployedSafe.getOwners().length == TEST_TOTAL_OWNERS, "Invalid number of owners");

        // Verify other components
        require(address(dragonTokenizedStrategySingleton) != address(0), "Strategy not deployed");
        require(address(moduleProxyFactory) != address(0), "ModuleProxyFactory not deployed");
        require(address(dragonRouterSingleton) != address(0), "DragonRouter implementation not deployed");
        require(address(dragonRouterProxy) != address(0), "DragonRouter proxy not deployed");
        require(address(splitCheckerSingleton) != address(0), "SplitChecker not deployed");

        // Verify Hats Protocol deployment
        require(address(HATS) != address(0), "Hats Protocol not deployed");
        require(address(dragonHatter) != address(0), "DragonHatter not deployed");
        require(HATS.isWearerOfHat(msg.sender, topHatId), "Safe not wearing top hat");
        require(HATS.isWearerOfHat(address(msg.sender), dragonAdminHatId), "Safe not wearing branch hat");
        require(HATS.isWearerOfHat(address(dragonHatter), branchHatId), "DragonHatter not wearing branch hat");
        // Get role hat IDs
        uint256 keeperHatId = dragonHatter.getRoleHat(dragonHatter.KEEPER_ROLE());
        uint256 managementHatId = dragonHatter.getRoleHat(dragonHatter.MANAGEMENT_ROLE());
        uint256 emergencyHatId = dragonHatter.getRoleHat(dragonHatter.EMERGENCY_ROLE());
        uint256 regenGovernanceHatId = dragonHatter.getRoleHat(dragonHatter.REGEN_GOVERNANCE_ROLE());

        // Log role hat IDs
        console.log("Keeper Role Hat ID:", keeperHatId);
        console.log("Management Role Hat ID:", managementHatId);
        console.log("Emergency Role Hat ID:", emergencyHatId);
        console.log("Regen Governance Role Hat ID:", regenGovernanceHatId);

        // Verify deployer is wearing all role hats
        require(HATS.isWearerOfHat(msg.sender, keeperHatId), "Deployer not wearing keeper hat");
        require(HATS.isWearerOfHat(msg.sender, managementHatId), "Deployer not wearing management hat");
        require(HATS.isWearerOfHat(msg.sender, emergencyHatId), "Deployer not wearing emergency hat");
        require(HATS.isWearerOfHat(msg.sender, regenGovernanceHatId), "Deployer not wearing regen governance hat");

        // Verify role hats were created properly
        require(keeperHatId != 0, "Keeper role hat not created");
        require(managementHatId != 0, "Management role hat not created");
        require(emergencyHatId != 0, "Emergency role hat not created");
        require(regenGovernanceHatId != 0, "Regen Governance role hat not created");

        // Verify role hats are under branch hat
        require(HATS.isValidHatId(branchHatId), "Keeper hat not under branch");
        require(HATS.isValidHatId(managementHatId), "Management hat not under branch");
        require(HATS.isValidHatId(emergencyHatId), "Emergency hat not under branch");
        require(HATS.isValidHatId(regenGovernanceHatId), "Regen Governance hat not under branch");
        // addLabels();
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
    function execTransaction(address to, uint256 value, bytes memory data, uint256[] memory signerIndices) public {
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
