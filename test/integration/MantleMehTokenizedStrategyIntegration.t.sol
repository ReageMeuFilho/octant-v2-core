// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SetupIntegrationTest } from "./Setup.t.sol";
import { DragonRouter } from "src/dragons/DragonRouter.sol";
import { MantleMehTokenizedStrategy } from "src/dragons/modules/MantleMehTokenizedStrategy.sol";
import { MockMantleMehTokenizedStrategy } from "test/mocks/MockMantleMehTokenizedStrategy.sol";
import { IMantleMehTokenizedStrategy } from "src/interfaces/IMantleMehTokenizedStrategy.sol";
import { IMantleStaking } from "src/interfaces/IMantleStaking.sol";
import { IDragonTokenizedStrategy } from "src/interfaces/IDragonTokenizedStrategy.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { DragonTokenizedStrategy } from "src/dragons/vaults/DragonTokenizedStrategy.sol";

import { MockMETH } from "test/mocks/MockMETH.sol";
import { MockMantleStaking } from "test/mocks/MockMantleStaking.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISplitChecker } from "src/interfaces/ISplitChecker.sol";

/**
 * @title MantleMehTokenizedStrategyIntegrationTest
 * @notice Integration tests for MantleMehTokenizedStrategy with Hats and Dragon Router
 */
contract MantleMehTokenizedStrategyIntegrationTest is SetupIntegrationTest {
    // Test addresses
    address public keeper = address(0x123);
    address public manager = address(0x456);
    address public emergency = address(0x789);
    address public regenGov = address(0xabc);
    address public metapool = address(0x432);
    address public user1 = address(0xdef);
    address public user2 = address(0xbcd);

    // Constants
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant MAX_BPS = 10_000;

    // Mock contracts
    MockMETH public mockMeth;
    MockMantleStaking public mockMantleStaking;

    // The actual constant addresses used in MantleMehTokenizedStrategy
    address public constant REAL_MANTLE_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    address public constant REAL_METH_TOKEN = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;

    // MantleStrategy contracts
    DragonTokenizedStrategy public tokenizedStrategyImplementation;
    MockMantleMehTokenizedStrategy public mantleStrategyImplementation;
    IMantleMehTokenizedStrategy public mantleStrategy;

    // Signature indices for safe transactions
    uint256[] public signerIndices;

    function setUp() public override {
        // Initialize base test first
        super.setUp();

        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(address(deployedSafe), 100 ether);

        // Deploy mock contracts
        mockMeth = new MockMETH();
        mockMantleStaking = new MockMantleStaking(address(mockMeth));

        // Configure mock relationships
        mockMeth.setMantleStaking(address(mockMantleStaking));
        mockMantleStaking.setExchangeRate(1e18); // 1:1 for simplicity

        // Fund mock staking contract
        vm.deal(address(mockMantleStaking), 100 ether);

        // Redirect calls to the real contracts to our mocks
        vm.etch(REAL_MANTLE_STAKING, address(mockMantleStaking).code);
        vm.etch(REAL_METH_TOKEN, address(mockMeth).code);

        // Initialize state at the real addresses
        vm.startPrank(deployer);
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setExchangeRate(1e18);
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setMETHToken(REAL_METH_TOKEN);
        vm.stopPrank();

        // Fund the real address with ETH as well
        vm.deal(REAL_MANTLE_STAKING, 100 ether);

        // Create signature array for safe transactions
        signerIndices = new uint256[](TEST_THRESHOLD);
        for (uint256 i = 0; i < TEST_THRESHOLD; i++) {
            signerIndices[i] = i;
        }
    }

    function testHatsIntegration() public {
        // Get hat IDs
        uint256 keeperHatId = dragonHatter.getRoleHat(dragonHatter.KEEPER_ROLE());
        uint256 managementHatId = dragonHatter.getRoleHat(dragonHatter.MANAGEMENT_ROLE());
        uint256 emergencyHatId = dragonHatter.getRoleHat(dragonHatter.EMERGENCY_ROLE());
        uint256 regenGovernanceHatId = dragonHatter.getRoleHat(dragonHatter.REGEN_GOVERNANCE_ROLE());

        // Setup Hats Protocol for mock strategy
        bytes memory setupHatsData = abi.encodeWithSignature(
            "setupHatsProtocol(address,uint256,uint256,uint256,uint256)",
            address(HATS),
            keeperHatId,
            managementHatId,
            emergencyHatId,
            regenGovernanceHatId
        );

        execTransaction(address(mockStrategyProxy), 0, setupHatsData, signerIndices);

        // Grant roles using DragonHatter
        vm.startPrank(deployer);
        dragonHatter.grantRole(dragonHatter.KEEPER_ROLE(), keeper);
        dragonHatter.grantRole(dragonHatter.MANAGEMENT_ROLE(), manager);
        dragonHatter.grantRole(dragonHatter.EMERGENCY_ROLE(), emergency);
        dragonHatter.grantRole(dragonHatter.REGEN_GOVERNANCE_ROLE(), regenGov);
        vm.stopPrank();

        // Test access control
        vm.prank(keeper);
        mockStrategyProxy.tend();

        // Verify management role
        vm.prank(manager);
        mockStrategyProxy.adjustPosition(100);

        // Verify regen governance role works - set rage quit cooldown period
        vm.prank(regenGov);
        mockStrategyProxy.setRageQuitCooldownPeriod(90 days);

        // Verify emergency role works for shutdown
        vm.prank(emergency);
        mockStrategyProxy.shutdownStrategy();
    }

    function testHatsIntegrationSimplified() public {
        // Get hat IDs
        uint256 keeperHatId = dragonHatter.getRoleHat(dragonHatter.KEEPER_ROLE());
        uint256 managementHatId = dragonHatter.getRoleHat(dragonHatter.MANAGEMENT_ROLE());
        uint256 emergencyHatId = dragonHatter.getRoleHat(dragonHatter.EMERGENCY_ROLE());
        uint256 regenGovernanceHatId = dragonHatter.getRoleHat(dragonHatter.REGEN_GOVERNANCE_ROLE());

        // Verify hat IDs are valid
        assertGt(keeperHatId, 0, "Keeper hat ID should be set");
        assertGt(managementHatId, 0, "Management hat ID should be set");
        assertGt(emergencyHatId, 0, "Emergency hat ID should be set");
        assertGt(regenGovernanceHatId, 0, "Regen governance hat ID should be set");

        // Grant roles using DragonHatter
        vm.startPrank(deployer);
        dragonHatter.grantRole(dragonHatter.KEEPER_ROLE(), keeper);
        dragonHatter.grantRole(dragonHatter.MANAGEMENT_ROLE(), manager);
        dragonHatter.grantRole(dragonHatter.EMERGENCY_ROLE(), emergency);
        dragonHatter.grantRole(dragonHatter.REGEN_GOVERNANCE_ROLE(), regenGov);
        vm.stopPrank();

        // Check if roles were assigned properly using the Hats protocol
        assertTrue(HATS.isWearerOfHat(keeper, keeperHatId), "Keeper should be wearing keeper hat");
        assertTrue(HATS.isWearerOfHat(manager, managementHatId), "Manager should be wearing management hat");
        assertTrue(HATS.isWearerOfHat(emergency, emergencyHatId), "Emergency admin should be wearing emergency hat");
        assertTrue(
            HATS.isWearerOfHat(regenGov, regenGovernanceHatId),
            "Regen gov should be wearing regen governance hat"
        );
    }

    function testFullMantleWorkflow() public {
        // =============== STEP 1: Deploy Mantle Strategy ===============
        _deployMantleStrategy();

        // =============== STEP 2: Setup Hats Protocol ===============
        _setupHatsForMantleStrategy();

        // =============== STEP 3: Setup Dragon Router ================
        _setupDragonRouterForMantle();

        // =============== STEP 4: Test Deposit Flow ==================
        uint256 depositAmount = 2 ether;

        // Toggle dragon mode if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(mantleStrategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(address(deployedSafe));
            IDragonTokenizedStrategy(address(mantleStrategy)).toggleDragonMode(false);
        }

        // Get initial balances
        uint256 initialBalance = user1.balance;
        uint256 initialShares = ITokenizedStrategy(address(mantleStrategy)).balanceOf(user1);

        // Perform deposit as user1
        vm.prank(user1);
        uint256 shares = IDragonTokenizedStrategy(address(mantleStrategy)).deposit{ value: depositAmount }(
            depositAmount,
            user1
        );

        // Verify user received shares
        assertGt(shares, 0, "User should have received shares");
        assertEq(
            ITokenizedStrategy(address(mantleStrategy)).balanceOf(user1),
            initialShares + shares,
            "Balance should match shares received"
        );

        // Verify user ETH decreased
        assertEq(user1.balance, initialBalance - depositAmount, "User ETH balance should have decreased");

        // Verify mETH was minted (strategy staked the ETH)
        assertGt(
            IERC20(REAL_METH_TOKEN).balanceOf(address(mantleStrategy)),
            0,
            "Strategy should have mETH tokens after staking"
        );

        // =============== STEP 5: Test Withdrawal Flow ================
        // Calculate withdraw amount (half of shares)
        uint256 sharesToWithdraw = shares / 2;
        uint256 assetsToWithdraw = ITokenizedStrategy(address(mantleStrategy)).convertToAssets(sharesToWithdraw);

        // Withdraw
        vm.prank(user1);
        IDragonTokenizedStrategy(address(mantleStrategy)).withdraw(assetsToWithdraw, user1, user1, MAX_BPS);

        // Verify shares reduced
        assertEq(
            ITokenizedStrategy(address(mantleStrategy)).balanceOf(user1),
            shares - sharesToWithdraw,
            "User shares should be reduced"
        );

        // Verify unstake request was created
        (uint256[] memory requests, , ) = mantleStrategy.getUserUnstakeRequests(user1);
        assertEq(requests.length, 1, "Should have created 1 unstake request");

        // =============== STEP 6: Test Claiming Unstake Request ================
        // Get the request ID
        uint256 requestId = requests[0];

        // Finalize the request in our mock
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).finalizeRequest(requestId);
        // Set a filled amount for the request
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setRequestAmount(requestId, assetsToWithdraw);

        // Record balance before claiming
        uint256 balanceBefore = user1.balance;

        // Claim the request
        vm.prank(user1);
        mantleStrategy.claimUnstakeRequest(requestId, user1);

        // Verify ETH was received
        assertGt(user1.balance, balanceBefore, "User should have received ETH");

        // Verify request is marked as claimed
        assertTrue(mantleStrategy.unstakeRequestClaimed(requestId), "Request should be marked as claimed");

        // =============== STEP 7: Test Split Distribution ================
        // Make profits in the strategy by directly adding ETH
        vm.deal(address(mantleStrategy), 1 ether);

        // Report profits to update share price
        vm.prank(keeper);
        ITokenizedStrategy(address(mantleStrategy)).report();

        // Check that metapool has claimable split
        uint256 claimableSplit = DragonRouter(payable(address(dragonRouterProxy))).balanceOf(
            metapool,
            address(mantleStrategy)
        );
        assertGt(claimableSplit, 0, "Metapool should have claimable split");

        // Get metapool's initial balance
        uint256 initialMetapoolBalance = metapool.balance;

        // Claim split as metapool
        vm.prank(metapool);
        DragonRouter(payable(address(dragonRouterProxy))).claimSplit(metapool, address(mantleStrategy), claimableSplit);

        // Verify split request was created
        (uint256[] memory metapoolRequests, , ) = mantleStrategy.getUserUnstakeRequests(metapool);
        assertEq(metapoolRequests.length, 1, "Should have created 1 unstake request for metapool");

        // Finalize the request
        uint256 metapoolRequestId = metapoolRequests[0];
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).finalizeRequest(metapoolRequestId);
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setRequestAmount(metapoolRequestId, claimableSplit);

        // Claim the request
        vm.prank(metapool);
        mantleStrategy.claimUnstakeRequest(metapoolRequestId, metapool);

        // Verify metapool received ETH
        assertGt(metapool.balance, initialMetapoolBalance, "Metapool should have received ETH");
    }

    function testSimpleMantleDeposit() public {
        // =============== STEP 1: Deploy Mantle Strategy ===============
        _deployMantleStrategy();

        // =============== STEP 2: Setup Hats Protocol ===============
        _setupHatsForMantleStrategy();

        // Toggle dragon mode to allow direct deposits
        bool isDragonOnly = IDragonTokenizedStrategy(address(mantleStrategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(address(deployedSafe));
            IDragonTokenizedStrategy(address(mantleStrategy)).toggleDragonMode(false);
        }

        // =============== STEP 3: Test Deposit Flow ==================
        uint256 depositAmount = 2 ether;

        // Get initial balances
        uint256 initialBalance = user1.balance;
        uint256 initialShares = ITokenizedStrategy(address(mantleStrategy)).balanceOf(user1);

        // Perform deposit as user1
        vm.prank(user1);
        uint256 shares = IDragonTokenizedStrategy(address(mantleStrategy)).deposit{ value: depositAmount }(
            depositAmount,
            user1
        );

        // Verify user received shares
        assertGt(shares, 0, "User should have received shares");
        assertEq(
            ITokenizedStrategy(address(mantleStrategy)).balanceOf(user1),
            initialShares + shares,
            "Balance should match shares received"
        );

        // Verify user ETH decreased
        assertEq(user1.balance, initialBalance - depositAmount, "User ETH balance should have decreased");

        // Verify mETH was minted (strategy staked the ETH)
        assertGt(
            IERC20(REAL_METH_TOKEN).balanceOf(address(mantleStrategy)),
            0,
            "Strategy should have mETH tokens after staking"
        );
    }

    function testBasicMantleStrategy() public {
        // =============== STEP 1: Deploy Mantle Strategy ===============
        _deployMantleStrategy();

        // Check Mantle-specific constants
        address mETHToken = mantleStrategy.METH_TOKEN();
        assertEq(mETHToken, REAL_METH_TOKEN, "mETH token should be set correctly");

        address mantleStaking = mantleStrategy.MANTLE_STAKING();
        assertEq(mantleStaking, REAL_MANTLE_STAKING, "Mantle staking should be set correctly");

        // Verify totalAssets starts at 0
        uint256 totalAssets = ITokenizedStrategy(address(mantleStrategy)).totalAssets();
        assertEq(totalAssets, 0, "Total assets should start at 0");
    }

    function _deployMantleStrategy() internal {
        // Deploy implementations
        tokenizedStrategyImplementation = new DragonTokenizedStrategy();
        mantleStrategyImplementation = new MockMantleMehTokenizedStrategy();

        // Set mock addresses for the implementation
        MockMantleMehTokenizedStrategy(payable(address(mantleStrategyImplementation))).setMockAddresses(
            address(mockMantleStaking),
            address(mockMeth)
        );

        // Create the proxy WITHOUT initializing it first
        bytes memory emptyData = "";
        ERC1967Proxy proxy = new ERC1967Proxy(address(mantleStrategyImplementation), emptyData);

        // Cast to interface
        mantleStrategy = IMantleMehTokenizedStrategy(payable(address(proxy)));

        // Set mock addresses for proxy instance BEFORE initialization
        MockMantleMehTokenizedStrategy(payable(address(proxy))).setMockAddresses(
            address(mockMantleStaking),
            address(mockMeth)
        );

        // Now initialize the proxy
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,string,address,address,address,address,address)",
            ETH,
            "Octant Mantle ETH Strategy",
            address(deployedSafe),
            manager,
            keeper,
            address(dragonRouterProxy),
            regenGov
        );

        (bool success, ) = address(proxy).call(initData);
        require(success, "Initialization failed");

        // Label for debugging
        vm.label(address(mantleStrategyImplementation), "MantleMehTokenizedStrategy Implementation");
        vm.label(address(mantleStrategy), "MantleMehTokenizedStrategy Proxy");
    }

    function _setupHatsForMantleStrategy() internal {
        // Get hat IDs
        uint256 keeperHatId = dragonHatter.getRoleHat(dragonHatter.KEEPER_ROLE());
        uint256 managementHatId = dragonHatter.getRoleHat(dragonHatter.MANAGEMENT_ROLE());
        uint256 emergencyHatId = dragonHatter.getRoleHat(dragonHatter.EMERGENCY_ROLE());
        uint256 regenGovernanceHatId = dragonHatter.getRoleHat(dragonHatter.REGEN_GOVERNANCE_ROLE());

        // Setup Hats Protocol for strategy
        bytes memory setupHatsData = abi.encodeWithSignature(
            "setupHatsProtocol(address,uint256,uint256,uint256,uint256)",
            address(HATS),
            keeperHatId,
            managementHatId,
            emergencyHatId,
            regenGovernanceHatId
        );

        execTransaction(address(mantleStrategy), 0, setupHatsData, signerIndices);

        // Grant roles using DragonHatter
        vm.startPrank(deployer);
        dragonHatter.grantRole(dragonHatter.KEEPER_ROLE(), keeper);
        dragonHatter.grantRole(dragonHatter.MANAGEMENT_ROLE(), manager);
        dragonHatter.grantRole(dragonHatter.EMERGENCY_ROLE(), emergency);
        dragonHatter.grantRole(dragonHatter.REGEN_GOVERNANCE_ROLE(), regenGov);
        vm.stopPrank();
    }

    function _setupDragonRouterForMantle() internal {
        // Create a new split configuration
        address[] memory recipients = new address[](1);
        uint256[] memory allocations = new uint256[](1);

        recipients[0] = metapool;
        allocations[0] = 1e18; // 100% to metapool

        ISplitChecker.Split memory newSplit = ISplitChecker.Split({
            recipients: recipients,
            allocations: allocations,
            totalAllocations: 1e18
        });

        // Add strategy to DragonRouter
        bytes memory addStrategyData = abi.encodeWithSignature("addStrategy(address)", address(mantleStrategy));

        execTransaction(address(dragonRouterProxy), 0, addStrategyData, signerIndices);

        // Set the split configuration
        bytes memory setSplitData = abi.encodeWithSignature("setSplit((address[],uint256[],uint256))", newSplit);

        execTransaction(address(dragonRouterProxy), 0, setSplitData, signerIndices);
    }

    function testSimplifiedDragonRouterAndHatsIntegration() public {
        // We will test a simpler version focusing only on adding a strategy to the router

        // Test adding a strategy to the Dragon Router using the multisig
        bytes memory addStrategyData = abi.encodeWithSignature("addStrategy(address)", address(mockStrategyProxy));

        execTransaction(address(dragonRouterProxy), 0, addStrategyData, signerIndices);

        // Check if the strategy was added successfully by checking the strategyData mapping
        (address asset, , , ) = dragonRouterProxy.strategyData(address(mockStrategyProxy));
        assertNotEq(asset, address(0), "Strategy should be supported by Dragon Router");

        // Verify the strategy is in the strategies array
        bool strategyFound = false;
        uint256 strategiesCount = 0;

        while (true) {
            try dragonRouterProxy.strategies(strategiesCount) returns (address listedStrategy) {
                if (listedStrategy == address(mockStrategyProxy)) {
                    strategyFound = true;
                    break;
                }
                strategiesCount++;
            } catch {
                break; // End of array reached
            }
        }

        assertTrue(strategyFound, "Strategy should be in the strategies array");
    }

    function testMantleHatsIntegrationBasic() public {
        // This is a minimal test to verify that the Hats protocol integration works with our test setup

        // Get hat IDs
        uint256 keeperHatId = dragonHatter.getRoleHat(dragonHatter.KEEPER_ROLE());
        uint256 managementHatId = dragonHatter.getRoleHat(dragonHatter.MANAGEMENT_ROLE());
        uint256 emergencyHatId = dragonHatter.getRoleHat(dragonHatter.EMERGENCY_ROLE());
        uint256 regenGovernanceHatId = dragonHatter.getRoleHat(dragonHatter.REGEN_GOVERNANCE_ROLE());

        // Setup Hats Protocol for mock strategy
        bytes memory setupHatsData = abi.encodeWithSignature(
            "setupHatsProtocol(address,uint256,uint256,uint256,uint256)",
            address(HATS),
            keeperHatId,
            managementHatId,
            emergencyHatId,
            regenGovernanceHatId
        );

        execTransaction(address(mockStrategyProxy), 0, setupHatsData, signerIndices);

        // Grant roles using DragonHatter
        vm.startPrank(deployer);
        dragonHatter.grantRole(dragonHatter.KEEPER_ROLE(), keeper);
        dragonHatter.grantRole(dragonHatter.MANAGEMENT_ROLE(), manager);
        dragonHatter.grantRole(dragonHatter.EMERGENCY_ROLE(), emergency);
        dragonHatter.grantRole(dragonHatter.REGEN_GOVERNANCE_ROLE(), regenGov);
        vm.stopPrank();

        // Test keeper access control
        vm.prank(keeper);
        mockStrategyProxy.tend();

        // Test successful completion
        assertTrue(true, "Hats protocol integration test completed successfully");
    }
}
