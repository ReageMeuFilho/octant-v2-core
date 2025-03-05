// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "../Base.t.sol";
import { MantleMehTokenizedStrategy } from "src/dragons/modules/MantleMehTokenizedStrategy.sol";
import { DragonTokenizedStrategy } from "src/dragons/vaults/DragonTokenizedStrategy.sol";
import { IMantleStaking } from "src/interfaces/IMantleStaking.sol";
import { IMantleMehTokenizedStrategy } from "src/interfaces/IMantleMehTokenizedStrategy.sol";
import { IDragonTokenizedStrategy } from "src/interfaces/IDragonTokenizedStrategy.sol";
import { TokenizedStrategy__DepositMoreThanMax } from "src/errors.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { MockMETH } from "../../mocks/MockMETH.sol";
import { MockMantleStaking } from "../../mocks/MockMantleStaking.sol";
import { MockMantleMehTokenizedStrategy } from "../../mocks/MockMantleMehTokenizedStrategy.sol";

/**
 * @title MantleMehTokenizedStrategyTest
 * @notice Unit tests for the MantleMehTokenizedStrategy
 * @dev Uses mock contracts to simulate Mantle's staking and mETH behavior
 */
contract MantleMehTokenizedStrategyTest is BaseTest {
    // Strategy parameters
    address management = makeAddr("management");
    address keeper = makeAddr("keeper");
    address dragonRouter = makeAddr("dragonRouter");
    address regenGovernance = makeAddr("regenGovernance");

    uint256 internal constant MAX_BPS = 10_000;

    // Test wallets
    address user1;
    address user2;

    // Mock contracts
    MockMETH mockMeth;
    MockMantleStaking mockMantleStaking;

    // Test environment
    testTemps temps;
    address tokenizedStrategyImplementation;
    address moduleImplementation;
    IMantleMehTokenizedStrategy strategy;

    // The actual constant addresses for reference
    address constant REAL_MANTLE_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    address constant REAL_METH_TOKEN = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setUp() public {
        _configure(true, "eth");

        // Set up users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock contracts
        mockMeth = new MockMETH();
        mockMantleStaking = new MockMantleStaking(address(mockMeth));

        // Configure mock relationships
        mockMeth.setMantleStaking(address(mockMantleStaking));
        mockMantleStaking.setExchangeRate(1e18); // 1:1 for simplicity

        // Fund mock staking contract with ETH
        vm.deal(address(mockMantleStaking), 100 ether);

        // Mock all calls to the real Mantle staking contract

        // redirect all calls to the real Mantle staking contract to our mock staking contract
        vm.etch(REAL_MANTLE_STAKING, address(mockMantleStaking).code);

        // redirect all calls to the real mETH token to our mock mETH
        vm.etch(REAL_METH_TOKEN, address(mockMeth).code);

        // Since etch only copies code, not state, we need to initialize the state at the real addresses
        vm.startPrank(address(this));
        // Initialize exchange rate at the real address
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setExchangeRate(1e18);
        // Set the mETH token reference in the staking contract
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setMETHToken(REAL_METH_TOKEN);
        vm.stopPrank();

        // Fund the real address with ETH as well
        vm.deal(REAL_MANTLE_STAKING, 100 ether);

        // Create implementations
        moduleImplementation = address(new MockMantleMehTokenizedStrategy());
        tokenizedStrategyImplementation = address(new DragonTokenizedStrategy());

        uint256 maxReportDelay = 7 days;

        // Use _testTemps to set up the test environment
        temps = _testTemps(
            moduleImplementation,
            abi.encode(
                tokenizedStrategyImplementation,
                management,
                keeper,
                dragonRouter,
                maxReportDelay,
                regenGovernance
            )
        );

        // Cast the module to our strategy type
        strategy = IMantleMehTokenizedStrategy(payable(temps.module));

        // Set mock addresses
        MockMantleMehTokenizedStrategy(payable(temps.module)).setMockAddresses(
            address(mockMantleStaking),
            address(mockMeth)
        );

        // Fund users with ETH for testing
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    /**
     * @notice Test that the strategy has the correct constants
     */
    function testContractConstants() public {
        assertEq(
            MockMantleMehTokenizedStrategy(payable(temps.module)).MANTLE_STAKING(),
            REAL_MANTLE_STAKING,
            "Real Mantle staking address should match"
        );
        assertEq(
            MockMantleMehTokenizedStrategy(payable(temps.module)).METH_TOKEN(),
            REAL_METH_TOKEN,
            "Real mETH token address should match"
        );
    }

    /**
     * @notice Test deposit with 0 lockup
     */
    function testDepositNoLockup() public {
        uint256 depositAmount = 1 ether;

        // Check initial balances
        assertEq(user1.balance, 10 ether);
        assertEq(ITokenizedStrategy(address(strategy)).balanceOf(user1), 0);

        // Check if strategy is in dragon-only mode and toggle if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();

        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Try to perform deposit with no lockup
        vm.startPrank(user1);

        try IDragonTokenizedStrategy(address(strategy)).deposit{ value: depositAmount }(depositAmount, user1) returns (
            uint256 shares
        ) {
            // Verify user received shares
            assertGt(shares, 0, "User should have received shares");
            assertEq(
                ITokenizedStrategy(address(strategy)).balanceOf(user1),
                shares,
                "Balance should match shares received"
            );

            // Verify user ETH decreased
            assertEq(user1.balance, 9 ether, "User ETH balance should have decreased");
        } catch Error(string memory reason) {
            assertFalse(true, "Deposit failed");
        } catch (bytes memory lowLevelData) {
            assertFalse(true, "Low level error in deposit function");
        }

        vm.stopPrank();
    }

    /**
     * @notice Test deposit with lockup
     */
    function testDepositWithLockup() public {
        uint256 depositAmount = 1 ether;
        uint256 lockupDuration = 90 days;

        // Check if strategy is in dragon-only mode and toggle if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Perform deposit with lockup
        vm.startPrank(user1);
        uint256 shares = IDragonTokenizedStrategy(address(strategy)).depositWithLockup{ value: depositAmount }(
            depositAmount,
            user1,
            lockupDuration
        );
        vm.stopPrank();

        // Verify user received shares
        assertGt(shares, 0, "User should have received shares");
        assertEq(
            ITokenizedStrategy(address(strategy)).balanceOf(user1),
            shares,
            "Balance should match shares received"
        );

        // Verify withdrawal limit due to lockup
        assertLt(
            ITokenizedStrategy(address(strategy)).maxWithdraw(user1),
            depositAmount,
            "Should have a withdrawal limit"
        );

        // Advance time past lockup
        vm.warp(block.timestamp + lockupDuration + 1);

        // Verify limit is lifted - after lockup, user can withdraw their entire deposit
        assertEq(
            ITokenizedStrategy(address(strategy)).maxWithdraw(user1),
            depositAmount,
            "After lockup, user should be able to withdraw full deposit amount"
        );
    }

    /**
     * @notice Test basic withdraw flow
     */
    function testWithdraw() public {
        uint256 depositAmount = 1 ether;

        // Check if strategy is in dragon-only mode and toggle if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Deposit first
        vm.startPrank(user1);
        uint256 shares = IDragonTokenizedStrategy(address(strategy)).deposit{ value: depositAmount }(
            depositAmount,
            user1
        );
        vm.stopPrank();

        // Calculate withdraw amount (half of shares)
        uint256 sharesToWithdraw = shares / 2;
        uint256 assetsToWithdraw = ITokenizedStrategy(address(strategy)).convertToAssets(sharesToWithdraw);

        // Withdraw
        vm.startPrank(user1);
        IDragonTokenizedStrategy(address(strategy)).withdraw(assetsToWithdraw, user1, user1, MAX_BPS);
        vm.stopPrank();

        // Verify shares reduced
        assertEq(
            ITokenizedStrategy(address(strategy)).balanceOf(user1),
            shares - sharesToWithdraw,
            "User shares should be reduced"
        );

        // Verify unstake request was created
        (uint256[] memory requests, , ) = strategy.getUserUnstakeRequests(user1);
        assertEq(requests.length, 1, "Should have created 1 unstake request");
    }

    /**
     * @notice Test claiming an unstake request
     */
    function testClaimUnstakeRequest() public {
        uint256 depositAmount = 1 ether;

        // Check if strategy is in dragon-only mode and toggle if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Deposit first
        vm.startPrank(user1);
        uint256 shares = IDragonTokenizedStrategy(address(strategy)).deposit{ value: depositAmount }(
            depositAmount,
            user1
        );
        vm.stopPrank();

        // Calculate withdraw amount (half of shares)
        uint256 sharesToWithdraw = shares / 2;
        uint256 assetsToWithdraw = ITokenizedStrategy(address(strategy)).convertToAssets(sharesToWithdraw);

        // Withdraw to create unstake request
        vm.startPrank(user1);
        IDragonTokenizedStrategy(address(strategy)).withdraw(assetsToWithdraw, user1, user1, MAX_BPS);
        vm.stopPrank();

        // Get the request ID
        (uint256[] memory requests, , ) = strategy.getUserUnstakeRequests(user1);
        uint256 requestId = requests[0];

        // Finalize the request in our mock
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).finalizeRequest(requestId);

        // Record balance before claiming
        uint256 balanceBefore = user1.balance;

        // Claim the request
        vm.prank(user1);
        strategy.claimUnstakeRequest(requestId, user1);

        // Verify ETH was received
        assertGt(user1.balance, balanceBefore, "User should have received ETH");

        // Verify request is marked as claimed
        assertTrue(strategy.unstakeRequestClaimed(requestId), "Request should be marked as claimed");
    }

    /**
     * @notice Test multiple users depositing and withdrawing
     */
    function testMultipleUsersDepositWithdraw() public {
        // Check if strategy is in dragon-only mode and toggle if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // User 1 deposits
        uint256 user1DepositAmount = 2 ether;
        vm.prank(user1);
        uint256 user1Shares = IDragonTokenizedStrategy(address(strategy)).deposit{ value: user1DepositAmount }(
            user1DepositAmount,
            user1
        );

        // User 2 deposits
        uint256 user2DepositAmount = 3 ether;
        vm.prank(user2);
        uint256 user2Shares = IDragonTokenizedStrategy(address(strategy)).deposit{ value: user2DepositAmount }(
            user2DepositAmount,
            user2
        );

        // Verify both users got shares
        assertGt(user1Shares, 0, "User1 should have shares");
        assertGt(user2Shares, 0, "User2 should have shares");

        // Calculate assets for partial withdrawals
        uint256 user1AssetsToWithdraw = ITokenizedStrategy(address(strategy)).convertToAssets(user1Shares / 2);
        uint256 user2AssetsToWithdraw = ITokenizedStrategy(address(strategy)).convertToAssets(user2Shares / 3);

        // User 1 withdraws
        vm.prank(user1);
        IDragonTokenizedStrategy(address(strategy)).withdraw(user1AssetsToWithdraw, user1, user1, MAX_BPS);

        // User 2 withdraws
        vm.prank(user2);
        IDragonTokenizedStrategy(address(strategy)).withdraw(user2AssetsToWithdraw, user2, user2, MAX_BPS);

        // Verify both users have unstake requests
        (uint256[] memory user1Requests, , ) = strategy.getUserUnstakeRequests(user1);
        (uint256[] memory user2Requests, , ) = strategy.getUserUnstakeRequests(user2);

        assertEq(user1Requests.length, 1, "User1 should have 1 unstake request");
        assertEq(user2Requests.length, 1, "User2 should have 1 unstake request");
    }

    /**
     * @notice Test error when trying to claim someone else's request
     */
    function testCannotClaimOthersRequest() public {
        // Check if strategy is in dragon-only mode and toggle if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();

        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Create an actual unstake request for user1 through normal means
        // User1 deposits
        vm.startPrank(user1);
        uint256 shares = IDragonTokenizedStrategy(address(strategy)).deposit{ value: 1 ether }(1 ether, user1);

        // User1 withdraws to create unstake request
        uint256 assetsToWithdraw = ITokenizedStrategy(address(strategy)).convertToAssets(shares / 2);
        IDragonTokenizedStrategy(address(strategy)).withdraw(assetsToWithdraw, user1, user1, MAX_BPS);
        vm.stopPrank();

        // Get the request ID from user1's requests
        (uint256[] memory requests, , ) = strategy.getUserUnstakeRequests(user1);
        assertEq(requests.length, 1, "Should have 1 unstake request");
        uint256 requestId = requests[0];

        // Finalize the request in the mock staking contract
        mockMantleStaking.finalizeRequest(requestId);
        mockMantleStaking.setRequestAmount(requestId, 1 ether);

        // Verify the request is ready to claim
        (bool isFinalized, uint256 amount) = mockMantleStaking.unstakeRequestInfo(requestId);
        assertTrue(isFinalized, "Request should be finalized");
        assertGt(amount, 0, "Request should have ETH amount");

        // User2 tries to claim user1's request (should fail)
        vm.prank(user2);
        vm.expectRevert(IMantleMehTokenizedStrategy.NotYourRequest.selector);
        strategy.claimUnstakeRequest(requestId, user1);
    }

    /**
     * @notice Test error when trying to claim a request that's not ready
     */
    function testCannotClaimUnreadyRequest() public {
        // Check if strategy is in dragon-only mode and toggle if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Setup: user1 deposits and withdraws
        vm.startPrank(user1);
        uint256 shares = IDragonTokenizedStrategy(address(strategy)).deposit{ value: 1 ether }(1 ether, user1);
        uint256 assetsToWithdraw = ITokenizedStrategy(address(strategy)).convertToAssets(shares / 2);
        IDragonTokenizedStrategy(address(strategy)).withdraw(assetsToWithdraw, user1, user1, MAX_BPS);
        vm.stopPrank();

        // Get user1's request (it's not finalized yet)
        (uint256[] memory requests, , ) = strategy.getUserUnstakeRequests(user1);
        uint256 requestId = requests[0];

        // Attempt to claim before finalization
        vm.prank(user1);
        vm.expectRevert(IMantleMehTokenizedStrategy.RequestNotReady.selector);
        strategy.claimUnstakeRequest(requestId, user1);
    }

    /**
     * @notice Test error when trying to claim an already claimed request
     */
    function testCannotClaimTwice() public {
        // Check if strategy is in dragon-only mode and toggle if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // Setup: user1 deposits and withdraws
        vm.startPrank(user1);
        uint256 shares = IDragonTokenizedStrategy(address(strategy)).deposit{ value: 1 ether }(1 ether, user1);
        vm.stopPrank();

        // Calculate withdraw amount (half of shares)
        uint256 sharesToWithdraw = shares / 2;
        uint256 assetsToWithdraw = ITokenizedStrategy(address(strategy)).convertToAssets(sharesToWithdraw);

        // Withdraw to create unstake request
        vm.startPrank(user1);
        IDragonTokenizedStrategy(address(strategy)).withdraw(assetsToWithdraw, user1, user1, MAX_BPS);
        vm.stopPrank();

        // Get the request ID
        (uint256[] memory requests, , ) = strategy.getUserUnstakeRequests(user1);
        uint256 requestId = requests[0];

        // Finalize the request using the actual address the strategy interacts with
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).finalizeRequest(requestId);

        // First claim should succeed
        vm.prank(user1);
        strategy.claimUnstakeRequest(requestId, user1);

        // Second claim should fail
        vm.prank(user1);
        vm.expectRevert(IMantleMehTokenizedStrategy.RequestAlreadyClaimed.selector);
        strategy.claimUnstakeRequest(requestId, user1);
    }

    /**
     * @notice Test error when deposit amount doesn't match msg.value
     */
    function testInvalidDepositAmount() public {
        // Check if strategy is in dragon-only mode and toggle if needed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        vm.prank(user1);
        vm.expectRevert(TokenizedStrategy__DepositMoreThanMax.selector);
        IDragonTokenizedStrategy(address(strategy)).deposit{ value: 1 ether }(2 ether, user1); // value != assets
    }

    /**
     * @notice Test converting mETH to ETH
     */
    function testConvertMETHToAssets() public {
        // Set a specific exchange rate in the mock
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setExchangeRate(1.05e18); // 1 mETH = 1.05 ETH

        uint256 methAmount = 10e18;
        uint256 expectedEth = 10.5e18; // 10 * 1.05

        uint256 result = strategy.convertMETHToAssets(methAmount);
        assertEq(result, expectedEth, "Conversion calculation should be correct");
    }

    /**
     * @notice Test emergency withdraw functionality
     */
    function testEmergencyWithdraw() public {
        // First deposit some ETH to be managed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        vm.prank(user1);
        IDragonTokenizedStrategy(address(strategy)).deposit{ value: 5 ether }(5 ether, user1);

        // Get initial mETH balance
        uint256 initialMethBalance = IERC20(REAL_METH_TOKEN).balanceOf(address(strategy));
        assertGt(initialMethBalance, 0, "Strategy should have mETH after deposit");

        // Set temps.safe as the emergencyAdmin
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setEmergencyAdmin(temps.safe);

        // First shutdown the strategy before emergency withdraw
        vm.prank(temps.safe);
        ITokenizedStrategy(address(strategy)).shutdownStrategy();

        // Trigger emergency withdraw from the owner
        vm.prank(temps.safe);
        IDragonTokenizedStrategy(address(strategy)).emergencyWithdraw(0);

        // Verify an unstake request was created for the owner
        (uint256[] memory requests, , ) = strategy.getUserUnstakeRequests(temps.safe);
        assertGt(requests.length, 0, "Owner should have an unstake request after emergency withdraw");
    }

    /**
     * @notice Test harvest and report functionality
     */
    function testHarvestAndReport() public {
        // Setup: deposit some ETH to be managed
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        vm.prank(user1);
        IDragonTokenizedStrategy(address(strategy)).deposit{ value: 5 ether }(5 ether, user1);

        // Add some ETH directly to the strategy contract to test both balance sources
        vm.deal(address(strategy), 1 ether);

        // Trigger a harvest via the report function
        vm.prank(keeper);
        (uint256 profit, ) = ITokenizedStrategy(address(strategy)).report();

        // Verify the profit equals the 1 ETH we added directly to the strategy
        // since report() returns profit since last report, not total assets
        assertEq(profit, 1 ether, "Reported profit should equal the 1 ETH added directly");
    }

    /**
     * @notice Test tend functionality
     */
    function testTend() public {
        // Add ETH directly to the strategy to be staked during tend
        vm.deal(address(strategy), 3 ether);

        uint256 initialMethBalance = IERC20(REAL_METH_TOKEN).balanceOf(address(strategy));

        // Call tend
        vm.prank(keeper);
        IDragonTokenizedStrategy(address(strategy)).tend();

        // Verify ETH was staked and converted to mETH
        uint256 newMethBalance = IERC20(REAL_METH_TOKEN).balanceOf(address(strategy));
        assertGt(newMethBalance, initialMethBalance, "mETH balance should increase after tend");
        assertEq(address(strategy).balance, 0, "ETH balance should be 0 after tend");
    }

    /**
     * @notice Test tend trigger functionality
     */
    // function testTendTrigger() public {
    //     // Call tendTrigger
    //     bool shouldTend = IDragonTokenizedStrategy(address(strategy)).tend();

    //     // Verify it returns true
    //     assertTrue(shouldTend, "tendTrigger should return true");
    // }

    /**
     * @notice Test all branch conditions in claimUnstakeRequest
     */
    function testClaimUnstakeRequestEdgeCases() public {
        // Setup: user deposits and withdraws to create a request
        bool isDragonOnly = IDragonTokenizedStrategy(address(strategy)).isDragonOnly();
        if (isDragonOnly) {
            vm.prank(temps.safe);
            IDragonTokenizedStrategy(address(strategy)).toggleDragonMode(false);
        }

        // User deposits
        vm.startPrank(user1);
        uint256 shares = IDragonTokenizedStrategy(address(strategy)).deposit{ value: 2 ether }(2 ether, user1);

        // User withdraws to create request
        uint256 assetsToWithdraw = ITokenizedStrategy(address(strategy)).convertToAssets(shares / 2);
        IDragonTokenizedStrategy(address(strategy)).withdraw(assetsToWithdraw, user1, user1, MAX_BPS);
        vm.stopPrank();

        // Get request ID
        (uint256[] memory requests, , ) = strategy.getUserUnstakeRequests(user1);
        uint256 requestId = requests[0];

        // Test case: request is finalized but filledAmount is 0
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).finalizeRequest(requestId);
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setRequestAmount(requestId, 0);

        vm.prank(user1);
        vm.expectRevert(IMantleMehTokenizedStrategy.RequestNotReady.selector);
        strategy.claimUnstakeRequest(requestId, user1);

        // Test case: request is not finalized
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).unfinalizeRequest(requestId);
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setRequestAmount(requestId, 1 ether);

        vm.prank(user1);
        vm.expectRevert(IMantleMehTokenizedStrategy.RequestNotReady.selector);
        strategy.claimUnstakeRequest(requestId, user1);

        // Test successful case with both conditions met
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).finalizeRequest(requestId);
        MockMantleStaking(payable(REAL_MANTLE_STAKING)).setRequestAmount(requestId, 1 ether);

        vm.prank(user1);
        strategy.claimUnstakeRequest(requestId, user1);

        assertTrue(strategy.unstakeRequestClaimed(requestId), "Request should be marked as claimed");
    }
}
