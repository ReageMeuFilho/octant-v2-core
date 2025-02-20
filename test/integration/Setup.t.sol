// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { TestPlus } from "lib/solady/test/utils/TestPlus.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockYieldSource } from "test/mocks/MockYieldSource.sol";
import { MockStrategy } from "test/mocks/MockStrategy.sol";
import { IMockStrategy } from "test/mocks/IMockStrategy.sol";
import { DeploySafe } from "script/deploy/DeploySafe.sol";
import { DeployDragonRouter } from "script/deploy/DeployDragonRouter.sol";
import { DeployModuleProxyFactory } from "script/deploy/DeployModuleProxyFactory.sol";
import { DeployDragonTokenizedStrategy } from "script/deploy/DeployDragonTokenizedStrategy.sol";
import { DeployHatsProtocol } from "script/deploy/DeployHatsProtocol.sol";
import { DeployMockStrategy } from "script/deploy/DeployMockStrategy.sol";
import { DeployNonfungibleDepositManager } from "script/deploy/DeployNonfungibleDepositManager.sol";

import { TokenizedStrategy__StrategyNotInShutdown, TokenizedStrategy__NotEmergencyAuthorized, TokenizedStrategy__HatsAlreadyInitialized, TokenizedStrategy__NotKeeperOrManagement, TokenizedStrategy__NotManagement } from "src/errors.sol";

contract SetupIntegrationTest is
    DeploySafe,
    DeployDragonTokenizedStrategy,
    DeployDragonRouter,
    DeployHatsProtocol,
    DeployMockStrategy,
    DeployNonfungibleDepositManager,
    TestPlus
{
    uint256 constant TEST_THRESHOLD = 3;
    uint256 constant TEST_TOTAL_OWNERS = 5;
    address constant SAFE_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    mapping(uint256 => uint256) public testPrivateKeys;
    address public deployer;
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

    /// ============ DeployNonfungibleDepositManager ===================
    /// NonfungibleDepositManager public nonfungibleDepositManager;
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

        // Add ETH2StakeVault label
        vm.label(address(nonfungibleDepositManager), "NonfungibleDepositManager");
    }

    function deploy()
        public
        override(
            DeploySafe,
            DeployDragonTokenizedStrategy,
            DeployDragonRouter,
            DeployModuleProxyFactory,
            DeployHatsProtocol,
            DeployNonfungibleDepositManager
        )
    {
        deployer = msg.sender;
        // Deploy Safe first as it will be the admin
        DeploySafe.deploy();

        // Deploy Hats Protocol and setup roles
        DeployHatsProtocol.deploy();

        // Deploy remaining components
        DeployDragonTokenizedStrategy.deploy();
        DeployDragonRouter.deploy();
        DeployNonfungibleDepositManager.deploy();

        vm.startPrank(address(deployedSafe));
        DeployMockStrategy.deploy(
            address(deployedSafe),
            address(dragonTokenizedStrategySingleton),
            address(dragonRouterProxy)
        );
        vm.stopPrank();
    }

    function setUp() public virtual {
        // Fork mainnet
        vm.createSelectFork(vm.envString("TEST_RPC_URL"));

        // Create test owners and store their private keys
        address[] memory testOwners = _createTestOwners(TEST_TOTAL_OWNERS);

        // Set up Safe deployment parameters
        setUpSafeDeployParams(SAFE_SINGLETON, SAFE_PROXY_FACTORY, testOwners, TEST_THRESHOLD);

        deploy();

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

        // Add ETH2StakeVault verification
        require(address(nonfungibleDepositManager) != address(0), "NonfungibleDepositManager not deployed");

        // addLabels();
    }

    /**
     * @notice Creates an array of test owner addresses and stores their private keys
     * @dev Uses _randomSigner() to generate deterministic addresses and private keys
     *      and sorts them in ascending order
     * @return _owners Array of owner addresses for Safe setup
     */
    function _createTestOwners(uint256 _totalOwners) internal returns (address[] memory _owners) {
        _owners = new address[](_totalOwners);
        uint256[] memory privateKeys = new uint256[](_totalOwners);

        // Generate all owners first
        for (uint256 i = 0; i < _totalOwners; i++) {
            (address owner, uint256 privateKey) = _randomSigner();
            _owners[i] = owner;
            privateKeys[i] = privateKey;
        }

        // Sort owners and private keys together (bubble sort)
        for (uint256 i = 0; i < _totalOwners - 1; i++) {
            for (uint256 j = 0; j < _totalOwners - i - 1; j++) {
                if (uint160(_owners[j]) > uint160(_owners[j + 1])) {
                    // Swap owners
                    address tempAddr = _owners[j];
                    _owners[j] = _owners[j + 1];
                    _owners[j + 1] = tempAddr;

                    // Swap corresponding private keys
                    uint256 tempKey = privateKeys[j];
                    privateKeys[j] = privateKeys[j + 1];
                    privateKeys[j + 1] = tempKey;
                }
            }
        }

        // Store sorted private keys
        for (uint256 i = 0; i < _totalOwners; i++) {
            testPrivateKeys[i] = privateKeys[i];
            vm.rememberKey(privateKeys[i]);
        }
    }

    /**
     * @notice Execute a transaction through the Safe with direct signing
     * @dev Uses pre-sorted signer indices to generate signatures in ascending order
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
            deployedSafe.nonce()
        );

        // Collect signatures using pre-sorted indices
        bytes memory signatures = new bytes(signerIndices.length * 65);
        uint256 pos = 0;
        // log all the owner public keys
        for (uint256 i = 0; i < TEST_TOTAL_OWNERS; i++) {
            // check they are all owners of the safe
            require(deployedSafe.isOwner(owners[i]), "Owner not owner of safe");
        }

        for (uint256 i = 0; i < signerIndices.length; i++) {
            uint256 ownerSk = testPrivateKeys[signerIndices[i]];
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerSk, txHash);

            assembly {
                mstore(add(signatures, add(pos, 32)), r)
                mstore(add(signatures, add(pos, 64)), s)
                mstore8(add(signatures, add(pos, 96)), v)
            }
            pos += 65;
        }
        vm.startBroadcast(testPrivateKeys[0]);
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
        vm.stopBroadcast();
        require(success, "Transaction execution failed");
    }
}
