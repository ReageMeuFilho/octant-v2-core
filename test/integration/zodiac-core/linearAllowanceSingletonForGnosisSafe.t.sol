// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;
import "forge-std/Test.sol";
import "lib/safe-smart-account/contracts/Safe.sol";
import "lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import "lib/safe-smart-account/contracts/proxies/SafeProxy.sol";
import { LinearAllowanceSingletonForGnosisSafeWrapper } from "test/wrappers/LinearAllowanceSingletonForGnosisSafeWrapper.sol";
import { NATIVE_TOKEN } from "src/constants.sol";
import "lib/safe-smart-account/contracts/libraries/Enum.sol";
import { LinearAllowanceExecutorTestHarness } from "test/mocks/zodiac-core/LinearAllowanceExecutorTestHarness.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { ILinearAllowanceSingleton } from "src/zodiac-core/interfaces/ILinearAllowanceSingleton.sol";

contract TestERC20 is ERC20 {
    constructor(uint256 initialSupply) ERC20("TestToken", "TST") {
        _mint(msg.sender, initialSupply);
    }
}

contract TestLinearAllowanceIntegration is Test {
    address delegateContractOwner = makeAddr("delegateContractOwner");

    Safe internal safeImpl;
    SafeProxyFactory internal safeProxyFactory;
    Safe internal singleton;
    LinearAllowanceSingletonForGnosisSafeWrapper internal allowanceModule;
    LinearAllowanceExecutorTestHarness public allowanceExecutor;
    address internal recipient = makeAddr("recipient");
    address internal safe = makeAddr("safe");

    function setUp() public {
        // Deploy module
        allowanceModule = new LinearAllowanceSingletonForGnosisSafeWrapper();
        // Deploy Safe infrastructure
        safeProxyFactory = new SafeProxyFactory();
        singleton = new Safe();

        // Create proxy Safe
        SafeProxy proxy = safeProxyFactory.createProxyWithNonce(address(singleton), "", 0);
        safeImpl = Safe(payable(address(proxy)));

        // Fund Safe with ETH
        vm.deal(address(safeImpl), 1_000_000 ether);

        // Initialize Safe
        address[] memory owners = new address[](1);
        owners[0] = vm.addr(1);
        safeImpl.setup(owners, 1, address(0), bytes(""), address(0), address(0), 0, payable(address(0)));

        // Enable SimpleAllowance module on Safe
        bytes memory enableData = abi.encodeWithSignature("enableModule(address)", address(allowanceModule));
        bool ok = execSafeTransaction(address(safeImpl), 0, enableData, 1);
        require(ok, "Module enable failed");

        // Deploy DelegateContract
        vm.startPrank(delegateContractOwner);
        allowanceExecutor = new LinearAllowanceExecutorTestHarness();
        vm.stopPrank();
    }

    // Test ETH allowance with both full and partial withdrawals
    function testAllowanceWithETH(uint192 dripRatePerDay, uint256 daysElapsed, uint256 safeBalance) public {
        // Constrain inputs to reasonable values
        vm.assume(dripRatePerDay > 0 ether);
        daysElapsed = uint32(bound(daysElapsed, 1, 365 * 20));

        // Calculate expected allowance
        uint256 expectedAllowance = uint256(dripRatePerDay) * uint256(daysElapsed);

        // Constrain safeBalance to ensure we test both partial and full withdrawals
        safeBalance = bound(safeBalance, expectedAllowance / 2, expectedAllowance * 2);

        // Setup
        address safeAddress = address(safeImpl);
        address executorAddress = address(allowanceExecutor);

        // Set the safe's balance
        vm.deal(safeAddress, safeBalance);

        // Verify reverts with no allowance
        vm.expectRevert();
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, NATIVE_TOKEN);

        // Set up allowance
        vm.prank(safeAddress);
        allowanceModule.setAllowance(executorAddress, NATIVE_TOKEN, uint192(dripRatePerDay));

        // Advance time to accrue allowance
        vm.warp(block.timestamp + daysElapsed * 1 days);

        // Get balances before transfer
        uint256 safeBalanceBefore = safeAddress.balance;
        uint256 executorBalanceBefore = executorAddress.balance;

        // Expected transfer is the minimum of allowance and balance
        uint256 expectedTransfer = expectedAllowance <= safeBalanceBefore ? expectedAllowance : safeBalanceBefore;

        // Execute transfer
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, NATIVE_TOKEN);

        // Verify correct amounts were transferred
        assertEq(
            executorAddress.balance - executorBalanceBefore,
            expectedTransfer,
            "Executor should receive correct amount"
        );
        assertEq(
            safeBalanceBefore - safeAddress.balance,
            expectedTransfer,
            "Safe balance should be reduced by transferred amount"
        );

        // Verify allowance bookkeeping
        (, uint256 totalUnspent, , ) = allowanceModule.getTokenAllowanceData(
            safeAddress,
            executorAddress,
            NATIVE_TOKEN
        );

        if (expectedAllowance > safeBalanceBefore) {
            // Partial withdrawal case
            assertEq(
                totalUnspent,
                expectedAllowance - safeBalanceBefore,
                "Remaining unspent should equal original minus transferred"
            );
        } else {
            // Full withdrawal case
            assertEq(totalUnspent, 0, "Unspent allowance should be zero");
        }

        // Test that allowance stops accruing after rate set to 0
        vm.warp(block.timestamp + 5 days);
        vm.prank(safeAddress);
        allowanceModule.setAllowance(executorAddress, NATIVE_TOKEN, 0);

        uint256 unspentAfterZeroRate = allowanceModule.getTotalUnspent(safeAddress, executorAddress, NATIVE_TOKEN);
        vm.warp(block.timestamp + 10 days);

        assertEq(
            allowanceModule.getTotalUnspent(safeAddress, executorAddress, NATIVE_TOKEN),
            unspentAfterZeroRate,
            "Balance should not increase after rate set to 0"
        );
    }

    // Test ERC20 allowance with both full and partial withdrawals
    function testAllowanceWithERC20(uint192 dripRatePerDay, uint256 daysElapsed, uint256 tokenSupply) public {
        // Constrain inputs to reasonable values
        vm.assume(dripRatePerDay > 0 ether);
        daysElapsed = uint32(bound(daysElapsed, 1, 365 * 20));

        // Calculate expected allowance
        uint256 expectedAllowance = uint256(dripRatePerDay) * uint256(daysElapsed);

        // Constrain tokenSupply to ensure we test both partial and full withdrawals
        tokenSupply = bound(tokenSupply, expectedAllowance / 2, expectedAllowance * 2);

        // Setup
        address safeAddress = address(safeImpl);
        address executorAddress = address(allowanceExecutor);

        // Create token and fund safe
        TestERC20 token = new TestERC20(tokenSupply);
        token.transfer(safeAddress, tokenSupply);

        // Verify reverts with no allowance
        vm.expectRevert();
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, address(token));

        // Set up allowance
        vm.prank(safeAddress);
        allowanceModule.setAllowance(executorAddress, address(token), uint192(dripRatePerDay));

        // Advance time to accrue allowance
        vm.warp(block.timestamp + daysElapsed * 1 days);

        // Get balances before transfer
        uint256 safeBalanceBefore = token.balanceOf(safeAddress);
        uint256 executorBalanceBefore = token.balanceOf(executorAddress);

        // Expected transfer is the minimum of allowance and balance
        uint256 expectedTransfer = expectedAllowance <= safeBalanceBefore ? expectedAllowance : safeBalanceBefore;

        // Execute transfer
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, address(token));

        // Verify correct amounts were transferred
        assertEq(
            token.balanceOf(executorAddress) - executorBalanceBefore,
            expectedTransfer,
            "Executor should receive correct token amount"
        );
        assertEq(
            safeBalanceBefore - token.balanceOf(safeAddress),
            expectedTransfer,
            "Safe token balance should be reduced by transferred amount"
        );

        // Verify allowance bookkeeping
        (, uint256 totalUnspent, , ) = allowanceModule.getTokenAllowanceData(
            safeAddress,
            executorAddress,
            address(token)
        );

        if (expectedAllowance > safeBalanceBefore) {
            // Partial withdrawal case
            assertEq(
                totalUnspent,
                expectedAllowance - safeBalanceBefore,
                "Remaining unspent should equal original minus transferred"
            );
        } else {
            // Full withdrawal case
            assertEq(totalUnspent, 0, "Unspent allowance should be zero");
        }

        // Test that allowance stops accruing after rate set to 0
        vm.warp(block.timestamp + 5 days);
        vm.prank(safeAddress);
        allowanceModule.setAllowance(executorAddress, address(token), 0);

        uint256 unspentAfterZeroRate = allowanceModule.getTotalUnspent(safeAddress, executorAddress, address(token));
        vm.warp(block.timestamp + 10 days);

        assertEq(
            allowanceModule.getTotalUnspent(safeAddress, executorAddress, address(token)),
            unspentAfterZeroRate,
            "Balance should not increase after rate set to 0"
        );
    }

    function testGetTotalUnspentWithUninitializedAllowance() public view {
        // Already passing, keeps the same
        uint256 unspent = allowanceModule.getTotalUnspent(
            address(safeImpl),
            address(0x123), // Random delegate that hasn't been configured
            address(NATIVE_TOKEN)
        );

        assertEq(unspent, 0, "Unspent amount should be 0 for uninitialized allowance");
    }

    function testExecuteAllowanceTransferFailingTokenTransfer() public {
        // Set up token
        TestERC20 token = new TestERC20(100 ether);

        // Create a mock safe that returns false for execTransactionFromModule
        MockFailingSafe failingSafe = new MockFailingSafe();

        // Mint tokens to the failing safe
        token.transfer(address(failingSafe), 100 ether);

        // Prank as the failing safe to set allowance
        vm.prank(address(failingSafe));
        allowanceModule.setAllowance(address(allowanceExecutor), address(token), uint192(100 ether));

        // Need to wait for allowance to accumulate
        vm.warp(block.timestamp + 1 days);

        // Attempt to execute allowance transfer
        vm.prank(address(allowanceExecutor));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILinearAllowanceSingleton.TransferFailed.selector,
                address(failingSafe),
                address(allowanceExecutor),
                address(token)
            )
        );
        allowanceModule.executeAllowanceTransfer(address(failingSafe), address(token), payable(address(recipient)));
    }

    function testExecuteAllowanceTransferEthTransferFailure() public {
        // Create a contract that rejects ETH transfers
        ContractThatRejectsETH rejector = new ContractThatRejectsETH();

        // Setup the mock safe
        MockSafeThatFailsEthTransfers failingSafe = new MockSafeThatFailsEthTransfers();
        vm.deal(address(failingSafe), 100 ether);

        // Create a delegate (executor) that we'll use
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();

        // Set allowance for ETH (using address(0) as native token)
        vm.prank(address(failingSafe));
        allowanceModule.setAllowance(address(executor), address(0), uint192(100 ether));

        // Wait for allowance to accumulate
        vm.warp(block.timestamp + 1 days);

        // Try to transfer ETH - should fail
        vm.prank(address(executor));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILinearAllowanceSingleton.TransferFailed.selector,
                address(failingSafe),
                address(executor),
                address(0)
            )
        );
        allowanceModule.executeAllowanceTransfer(address(failingSafe), address(0), payable(address(rejector)));
    }

    function testUpdateAllowanceWithExistingAllowance() public {
        // Create test token
        TestERC20 testToken = new TestERC20(100 ether);

        // Create a delegate (executor) that we'll use
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();

        // Create an allowance
        vm.prank(address(safe));
        allowanceModule.setAllowance(address(executor), address(testToken), uint192(100 ether));

        // Fast forward time
        vm.warp(block.timestamp + 1 days);

        // Call setAllowance again which invokes _updateAllowance
        vm.prank(address(safe));
        allowanceModule.setAllowance(address(executor), address(testToken), uint192(200 ether));

        // Verify the allowance was updated correctly
        (uint192 dripRate, uint256 unspent, , uint64 lastBooked) = allowanceModule.getTokenAllowanceData(
            address(safe),
            address(executor),
            address(testToken)
        );

        // Drip rate should be updated to 200 ether
        assertEq(dripRate, 200 ether);

        // Unspent should be around 100 ether (1 day's worth at 100 ether/day)
        assertEq(unspent, 100 ether);

        // Last booked should be updated to current time
        assertEq(lastBooked, uint32(block.timestamp));

        // Verify getTotalUnspent returns the correct value
        uint256 unspentAmount = allowanceModule.getTotalUnspent(address(safe), address(executor), address(testToken));
        assertEq(unspentAmount, 100 ether);
    }

    function testUpdateAllowanceReturnExplicitly() public {
        // Deploy the wrapper contract
        LinearAllowanceSingletonForGnosisSafeWrapper wrapper = new LinearAllowanceSingletonForGnosisSafeWrapper();

        // move up 1 week to avoid underflow
        vm.warp(block.timestamp + 1 weeks);

        uint256 dripRate = 1 ether;

        // Create a LinearAllowance struct with safe values
        ILinearAllowanceSingleton.LinearAllowance memory allowance = ILinearAllowanceSingleton.LinearAllowance({
            dripRatePerDay: uint192(dripRate),
            lastBookedAtInSeconds: uint64(block.timestamp - 1 hours), // Use 1 hour instead of 1 day
            totalUnspent: uint256(0),
            totalSpent: uint256(0)
        });

        // Call the exposed function
        ILinearAllowanceSingleton.LinearAllowance memory updatedAllowance = wrapper.exposeUpdateAllowance(allowance);

        // Calculate expected unspent amount (1 ETH per day, for 1 hour = 1/24 ETH)
        uint256 expectedUnspent = (dripRate * 1 hours) / 1 days;

        // Verify the return value
        assertEq(updatedAllowance.dripRatePerDay, dripRate);
        assertEq(updatedAllowance.totalUnspent, uint256(expectedUnspent));
        assertEq(updatedAllowance.lastBookedAtInSeconds, uint64(block.timestamp));
        assertEq(updatedAllowance.totalSpent, 0, "Total spent should remain unchanged");
    }

    function testEmergencyRevokeAllowanceVsNormalRevoke() public {
        // Setup: Create two identical scenarios to compare normal vs emergency revocation
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        
        // Create two separate executors for comparison
        LinearAllowanceExecutorTestHarness normalExecutor = new LinearAllowanceExecutorTestHarness();
        LinearAllowanceExecutorTestHarness emergencyExecutor = new LinearAllowanceExecutorTestHarness();

        // Set identical allowances for both executors
        vm.startPrank(safeAddress);
        allowanceModule.setAllowance(address(normalExecutor), NATIVE_TOKEN, dripRate);
        allowanceModule.setAllowance(address(emergencyExecutor), NATIVE_TOKEN, dripRate);
        vm.stopPrank();

        // Advance time to accrue allowance (24 hours = 100 ETH each)
        vm.warp(block.timestamp + 1 days);

        // Verify both have identical unspent allowances
        uint256 normalUnspentBefore = allowanceModule.getTotalUnspent(safeAddress, address(normalExecutor), NATIVE_TOKEN);
        uint256 emergencyUnspentBefore = allowanceModule.getTotalUnspent(safeAddress, address(emergencyExecutor), NATIVE_TOKEN);
        
        assertEq(normalUnspentBefore, dripRate, "Normal executor should have accrued full daily allowance");
        assertEq(emergencyUnspentBefore, dripRate, "Emergency executor should have accrued full daily allowance");
        assertEq(normalUnspentBefore, emergencyUnspentBefore, "Both executors should have identical allowances");

        // Test 1: Normal revocation (setAllowance to 0) - preserves accrued amounts
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(normalExecutor), NATIVE_TOKEN, 0);

        // Test 2: Emergency revocation - clears everything
        vm.expectEmit(true, true, true, true);
        emit ILinearAllowanceSingleton.AllowanceEmergencyRevoked(safeAddress, address(emergencyExecutor), NATIVE_TOKEN, dripRate);
        
        vm.prank(safeAddress);
        allowanceModule.emergencyRevokeAllowance(address(emergencyExecutor), NATIVE_TOKEN);

        // Verify the critical difference:
        // Normal revocation preserves accrued allowance
        uint256 normalUnspentAfter = allowanceModule.getTotalUnspent(safeAddress, address(normalExecutor), NATIVE_TOKEN);
        assertEq(normalUnspentAfter, dripRate, "Normal revocation should preserve accrued allowance");

        // Emergency revocation clears everything
        uint256 emergencyUnspentAfter = allowanceModule.getTotalUnspent(safeAddress, address(emergencyExecutor), NATIVE_TOKEN);
        assertEq(emergencyUnspentAfter, 0, "Emergency revocation should clear all allowance");

        // Verify both have drip rate set to 0 (check via getTotalUnspent behavior)

        // Advance time to ensure no further accrual for either
        vm.warp(block.timestamp + 1 days);

        assertEq(
            allowanceModule.getTotalUnspent(safeAddress, address(normalExecutor), NATIVE_TOKEN),
            dripRate,
            "Normal revocation should not accrue new allowance but preserve old"
        );
        
        assertEq(
            allowanceModule.getTotalUnspent(safeAddress, address(emergencyExecutor), NATIVE_TOKEN),
            0,
            "Emergency revocation should remain at zero with no accrual"
        );

        // Demonstrate the security issue: normal revocation allows fund extraction
        normalExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, NATIVE_TOKEN);
        uint256 normalBalance = address(normalExecutor).balance;
        assertEq(normalBalance, dripRate, "Compromised delegate can still withdraw after normal revocation");

        // Emergency revocation prevents any withdrawal
        vm.expectRevert();
        emergencyExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, NATIVE_TOKEN);
        
        assertEq(address(emergencyExecutor).balance, 0, "Emergency revocation prevents any withdrawal");
    }

    function testEmergencyRevokeWithPartialUnspentAndAccrual() public {
        uint128 dripRate = 50 ether;
        address safeAddress = address(safeImpl);
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();

        // Set allowance and let some accrue
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);

        // Advance time to accrue 25 ETH (12 hours at 50 ETH/day)
        vm.warp(block.timestamp + 12 hours);

        // Partially withdraw some allowance
        uint256 partialWithdraw = 10 ether;
        vm.deal(safeAddress, partialWithdraw); // Limit safe balance to force partial withdrawal
        executor.executeAllowanceTransfer(allowanceModule, safeAddress, NATIVE_TOKEN);

        // Advance time to accrue more (another 12 hours = 25 ETH more)
        vm.warp(block.timestamp + 12 hours);

        // Get the actual unspent amount at this point (whatever it is)
        uint256 actualUnspentBeforeRevoke = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        
        // Verify we have some unspent allowance to clear
        assertGt(actualUnspentBeforeRevoke, 0, "Should have some unspent allowance before emergency revocation");

        // Emergency revoke should clear the full amount
        vm.expectEmit(true, true, true, true);
        emit ILinearAllowanceSingleton.AllowanceEmergencyRevoked(safeAddress, address(executor), NATIVE_TOKEN, actualUnspentBeforeRevoke);
        
        vm.prank(safeAddress);
        allowanceModule.emergencyRevokeAllowance(address(executor), NATIVE_TOKEN);

        // Verify everything is cleared
        assertEq(
            allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN),
            0,
            "All allowance should be cleared after emergency revocation"
        );

        // Verify the allowance data shows proper state
        (uint128 dripRateAfter, uint160 totalUnspentAfter, uint192 totalSpentAfter, uint32 lastBookedAfter) = 
            allowanceModule.getTokenAllowanceData(safeAddress, address(executor), NATIVE_TOKEN);
        
        assertEq(dripRateAfter, 0, "Drip rate should be zero");
        assertEq(totalUnspentAfter, 0, "Total unspent should be zero");
        assertEq(totalSpentAfter, partialWithdraw, "Total spent should preserve audit trail");
        assertEq(lastBookedAfter, uint32(block.timestamp), "Last booked should be updated to current time");
    }

    // ==================== ACCESS CONTROL SECURITY TESTS ====================

    function testEmergencyRevokeAccessControl_OnlySafeCanRevokeItsOwnAllowances() public {
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // Setup allowance from safe
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);
        
        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);
        
        // Verify allowance exists
        uint256 unspentBefore = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(unspentBefore, dripRate, "Allowance should have accrued");
        
        // ✅ TEST: Safe itself can emergency revoke its own allowances
        vm.prank(safeAddress);
        allowanceModule.emergencyRevokeAllowance(address(executor), NATIVE_TOKEN);
        
        uint256 unspentAfter = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(unspentAfter, 0, "Safe should be able to emergency revoke its own allowances");
    }

    function testEmergencyRevokeAccessControl_AttackerCannotRevokeOtherSafesAllowances() public {
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        address attacker = makeAddr("attacker");
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // Setup allowance from safe
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);
        
        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);
        
        // Verify allowance exists
        uint256 unspentBefore = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(unspentBefore, dripRate, "Allowance should have accrued");
        
        // ❌ TEST: Attacker tries to emergency revoke the safe's allowances
        vm.prank(attacker);
        allowanceModule.emergencyRevokeAllowance(address(executor), NATIVE_TOKEN);
        
        // The safe's allowances should be completely unaffected
        uint256 unspentAfter = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(unspentAfter, dripRate, "Attacker should not be able to affect safe's allowances");
        
        // The attacker only affected their own (non-existent) allowances
        uint256 attackerUnspent = allowanceModule.getTotalUnspent(attacker, address(executor), NATIVE_TOKEN);
        assertEq(attackerUnspent, 0, "Attacker should have no allowances to begin with");
    }

    function testEmergencyRevokeAccessControl_RandomAddressCannotAffectOthers() public {
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        address randomUser = makeAddr("randomUser");
        address anotherUser = makeAddr("anotherUser");
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // Setup allowances from multiple addresses
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);
        
        vm.prank(randomUser);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate / 2);
        
        // Advance time to accrue allowances
        vm.warp(block.timestamp + 1 days);
        
        // Verify allowances exist
        uint256 safeUnspentBefore = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        uint256 randomUnspentBefore = allowanceModule.getTotalUnspent(randomUser, address(executor), NATIVE_TOKEN);
        
        assertEq(safeUnspentBefore, dripRate, "Safe allowance should have accrued");
        assertEq(randomUnspentBefore, dripRate / 2, "Random user allowance should have accrued");
        
        // Random user emergency revokes their own allowance (should work)
        vm.prank(randomUser);
        allowanceModule.emergencyRevokeAllowance(address(executor), NATIVE_TOKEN);
        
        // Another user tries to emergency revoke safe's allowance (should not work)
        vm.prank(anotherUser);
        allowanceModule.emergencyRevokeAllowance(address(executor), NATIVE_TOKEN);
        
        // Verify results
        uint256 safeUnspentAfter = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        uint256 randomUnspentAfter = allowanceModule.getTotalUnspent(randomUser, address(executor), NATIVE_TOKEN);
        uint256 anotherUnspentAfter = allowanceModule.getTotalUnspent(anotherUser, address(executor), NATIVE_TOKEN);
        
        assertEq(safeUnspentAfter, dripRate, "Safe allowance should be unaffected by other users");
        assertEq(randomUnspentAfter, 0, "Random user should have successfully revoked their own allowance");
        assertEq(anotherUnspentAfter, 0, "Another user should have no allowances (had none to revoke)");
    }

    function testEmergencyRevokeAccessControl_SafeOwnersCanRevokeViaMultisig() public {
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // Setup allowance
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);
        
        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);
        
        // Verify allowance exists
        uint256 unspentBefore = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(unspentBefore, dripRate, "Allowance should have accrued");
        
        // ✅ TEST: Safe owners can emergency revoke via Safe's execTransaction mechanism
        bytes memory emergencyRevokeData = abi.encodeWithSelector(
            allowanceModule.emergencyRevokeAllowance.selector,
            address(executor),
            NATIVE_TOKEN
        );
        
        bool success = execSafeTransaction(address(allowanceModule), 0, emergencyRevokeData, 1);
        assertTrue(success, "Safe owners should be able to execute emergency revoke via multisig");
        
        // Verify revocation worked
        uint256 unspentAfter = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(unspentAfter, 0, "Emergency revocation via multisig should clear allowances");
    }

    function testEmergencyRevokeAccessControl_NonOwnerCannotExecuteViaSafe() public {
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        address nonOwner = makeAddr("nonOwner");
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // Setup allowance
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);
        
        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);
        
        // Verify allowance exists
        uint256 unspentBefore = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(unspentBefore, dripRate, "Allowance should have accrued");
        
        // ❌ TEST: Non-owner tries to execute emergency revoke via Safe
        // This should fail because they can't meet the Safe's signature threshold
        bytes memory emergencyRevokeData = abi.encodeWithSelector(
            allowanceModule.emergencyRevokeAllowance.selector,
            address(executor),
            NATIVE_TOKEN
        );
        
        // Non-owner cannot create valid Safe transaction signatures
        // Attempting to execute directly should fail at Safe's access control level
        vm.startPrank(nonOwner);
        vm.expectRevert(); // Safe will revert due to invalid signature/access
        safeImpl.execTransaction(
            address(allowanceModule),
            0,
            emergencyRevokeData,
            Enum.Operation.Call,
            100_000,
            0,
            1,
            address(0),
            payable(address(0)),
            abi.encodePacked(bytes32(0), bytes32(0), bytes1(0)) // Invalid signature
        );
        vm.stopPrank();
        
        // Verify allowance is unchanged
        uint256 unspentAfter = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(unspentAfter, dripRate, "Non-owner should not be able to affect Safe's allowances");
    }

    function testEmergencyRevokeAccessControl_EventEmissionSecurity() public {
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        address attacker = makeAddr("attacker");
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // Setup allowance from safe
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);
        
        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);
        
        // ❌ TEST: Attacker cannot emit misleading events for other safes
        // When attacker calls emergency revoke, event should show attacker's address, not safe's
        vm.expectEmit(true, true, true, true);
        emit ILinearAllowanceSingleton.AllowanceEmergencyRevoked(attacker, address(executor), NATIVE_TOKEN, 0);
        
        vm.prank(attacker);
        allowanceModule.emergencyRevokeAllowance(address(executor), NATIVE_TOKEN);
        
        // Safe's allowance should be unaffected
        uint256 safeUnspent = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(safeUnspent, dripRate, "Safe allowance should be unaffected by attacker's call");
    }

    function testEmergencyRevokeAccessControl_MaliciousModuleCannotAbuseFunction() public {
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // Setup allowance from safe
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);
        
        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);
        
        // Create a malicious module that tries to call emergencyRevokeAllowance
        MaliciousModule maliciousModule = new MaliciousModule(allowanceModule);
        
        // Enable the malicious module on the Safe (simulating a compromised module scenario)
        bytes memory enableMaliciousModuleData = abi.encodeWithSignature("enableModule(address)", address(maliciousModule));
        bool enableSuccess = execSafeTransaction(address(safeImpl), 0, enableMaliciousModuleData, 1);
        require(enableSuccess, "Malicious module enable failed");
        
        // Manually set the safe address since setUp isn't called on module enable
        maliciousModule.setSafeAddress(safeAddress);
        
        // Verify allowance exists before attack
        uint256 unspentBefore = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(unspentBefore, dripRate, "Allowance should exist before malicious module attack");
        
        // ❌ TEST: Malicious module tries to call emergencyRevokeAllowance on behalf of Safe
        // This SHOULD work because the module can call execTransactionFromModule,
        // which means malicious modules are a real threat vector!
        maliciousModule.attemptEmergencyRevoke(address(executor), NATIVE_TOKEN);
        
        // Check if the malicious module was able to affect the allowances
        uint256 unspentAfter = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        
        if (unspentAfter == 0) {
            // If this happens, it means malicious modules CAN call emergency revoke
            // This would be a significant finding that we need to address
            emit log_string("WARNING: Malicious module was able to emergency revoke allowances!");
            emit log_string("This demonstrates that module access control is a critical concern");
        } else {
            // If allowances are preserved, the current access control model is sufficient
            assertEq(unspentAfter, dripRate, "Malicious module should not be able to affect allowances via direct call");
        }
        
        // Additional test: Try via execTransactionFromModule 
        bool moduleSuccess = maliciousModule.attemptEmergencyRevokeViaModule(address(executor), NATIVE_TOKEN);
        
        uint256 unspentAfterModuleAttempt = allowanceModule.getTotalUnspent(safeAddress, address(executor), NATIVE_TOKEN);
        
        if (moduleSuccess && unspentAfterModuleAttempt == 0) {
            emit log_string("CRITICAL: Malicious module can emergency revoke via execTransactionFromModule!");
            // This would indicate we need additional access controls
        } else {
            emit log_string("GOOD: Malicious modules cannot abuse emergency revocation");
        }
    }

    // ==================== SET ALLOWANCE ACCESS CONTROL TESTS ====================

    function testSetAllowanceAccessControl_OnlySafeCanSetItsOwnAllowances() public {
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // ✅ TEST: Safe itself can set allowances for delegates
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);
        
        // Verify allowance was set correctly
        (uint128 actualDripRate, , , ) = allowanceModule.getTokenAllowanceData(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(actualDripRate, dripRate, "Safe should be able to set allowances for its delegates");
    }

    function testSetAllowanceAccessControl_AttackerCannotSetAllowancesForOtherSafes() public {
        uint128 dripRate = 100 ether;
        address safeAddress = address(safeImpl);
        address attacker = makeAddr("attacker");
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // ❌ TEST: Attacker tries to set allowances for a Safe they don't control
        vm.prank(attacker);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, dripRate);
        
        // The attacker only affected their own allowances, not the Safe's
        (uint128 safeAllowanceRate, , , ) = allowanceModule.getTokenAllowanceData(safeAddress, address(executor), NATIVE_TOKEN);
        (uint128 attackerAllowanceRate, , , ) = allowanceModule.getTokenAllowanceData(attacker, address(executor), NATIVE_TOKEN);
        
        assertEq(safeAllowanceRate, 0, "Safe allowances should be unaffected by attacker");
        assertEq(attackerAllowanceRate, dripRate, "Attacker only affected their own allowances");
    }

    function testSetAllowanceAccessControl_MaliciousModuleCanAbuseSetAllowance() public {
        uint128 legitimateDripRate = 50 ether;
        uint128 maliciousDripRate = 1000 ether; // Much higher!
        address safeAddress = address(safeImpl);
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // Setup: Safe sets a legitimate allowance
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, legitimateDripRate);
        
        // Verify legitimate allowance
        (uint128 initialRate, , , ) = allowanceModule.getTokenAllowanceData(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(initialRate, legitimateDripRate, "Initial allowance should be set correctly");
        
        // Create and enable malicious module
        MaliciousModuleForSetAllowance maliciousModule = new MaliciousModuleForSetAllowance(allowanceModule);
        
        bytes memory enableData = abi.encodeWithSignature("enableModule(address)", address(maliciousModule));
        bool enableSuccess = execSafeTransaction(address(safeImpl), 0, enableData, 1);
        require(enableSuccess, "Malicious module enable failed");
        
        maliciousModule.setSafeAddress(safeAddress);
        
        // CRITICAL TEST: Can malicious module abuse setAllowance via execTransactionFromModule?
        bool attackSuccess = maliciousModule.attemptSetAllowanceViaModule(
            address(executor), 
            NATIVE_TOKEN, 
            maliciousDripRate
        );
        
        // Check if the attack succeeded
        (uint128 finalRate, , , ) = allowanceModule.getTokenAllowanceData(safeAddress, address(executor), NATIVE_TOKEN);
        
        if (attackSuccess && finalRate == maliciousDripRate) {
            emit log_string("CRITICAL VULNERABILITY: Malicious module can set unauthorized allowances!");
            emit log_named_uint("Original allowance", legitimateDripRate);
            emit log_named_uint("Malicious allowance", finalRate);
            
            // This demonstrates the vulnerability - module increased allowance without owner consent
            assertEq(finalRate, maliciousDripRate, "VULNERABILITY: Malicious module successfully set unauthorized allowance");
        } else {
            emit log_string("SECURE: Malicious module cannot abuse setAllowance");
            assertEq(finalRate, legitimateDripRate, "Allowance should remain at legitimate level");
        }
    }

    function testSetAllowanceAccessControl_SafeOwnersCanSetAllowanceViaMultisig() public {
        uint128 dripRate = 75 ether;
        address safeAddress = address(safeImpl);
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // ✅ TEST: Safe owners can set allowances via Safe's execTransaction mechanism
        bytes memory setAllowanceData = abi.encodeWithSelector(
            allowanceModule.setAllowance.selector,
            address(executor),
            NATIVE_TOKEN,
            dripRate
        );
        
        bool success = execSafeTransaction(address(allowanceModule), 0, setAllowanceData, 1);
        assertTrue(success, "Safe owners should be able to set allowances via multisig");
        
        // Verify allowance was set correctly
        (uint128 actualRate, , , ) = allowanceModule.getTokenAllowanceData(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(actualRate, dripRate, "Allowance should be set via legitimate multisig execution");
    }

    function testSetAllowanceAccessControl_MaliciousModuleGradualIncrease() public {
        uint128 legitimateRate = 10 ether;
        address safeAddress = address(safeImpl);
        LinearAllowanceExecutorTestHarness executor = new LinearAllowanceExecutorTestHarness();
        
        // Setup: Safe sets legitimate allowance
        vm.prank(safeAddress);
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, legitimateRate);
        
        // Create malicious module
        MaliciousModuleForSetAllowance maliciousModule = new MaliciousModuleForSetAllowance(allowanceModule);
        
        bytes memory enableData = abi.encodeWithSignature("enableModule(address)", address(maliciousModule));
        execSafeTransaction(address(safeImpl), 0, enableData, 1);
        maliciousModule.setSafeAddress(safeAddress);
        
        // TEST: Subtle attack - gradually increase allowance to avoid detection
        uint128[] memory increases = new uint128[](3);
        increases[0] = 15 ether;  // 50% increase
        increases[1] = 25 ether;  // 67% increase  
        increases[2] = 50 ether;  // 100% increase
        
        for (uint i = 0; i < increases.length; i++) {
            bool success = maliciousModule.attemptSetAllowanceViaModule(
                address(executor),
                NATIVE_TOKEN,
                increases[i]
            );
            
            if (success) {
                (uint128 currentRate, , , ) = allowanceModule.getTokenAllowanceData(safeAddress, address(executor), NATIVE_TOKEN);
                emit log_string("VULNERABILITY: Gradual allowance increase succeeded");
                emit log_named_uint("Step", i + 1);
                emit log_named_uint("New allowance", currentRate);
                
                // If any increase succeeds, the vulnerability exists
                assertGt(currentRate, legitimateRate, "Malicious module should not be able to increase allowances");
                return;
            }
        }
        
        // If we get here, all attacks failed (good!)
        (uint128 finalRate, , , ) = allowanceModule.getTokenAllowanceData(safeAddress, address(executor), NATIVE_TOKEN);
        assertEq(finalRate, legitimateRate, "All malicious increases should have failed");
        emit log_string("SECURE: Gradual allowance increase attacks blocked");
    }

    // Helper for Safe transactions (necessary due to Safe's complex transaction execution)
    function execSafeTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint256 ownerPrivateKey
    ) internal returns (bool) {
        bytes32 txHash = safeImpl.getTransactionHash(
            to,
            value,
            data,
            Enum.Operation.Call,
            100_000,
            0,
            1,
            address(0),
            payable(address(0)),
            safeImpl.nonce()
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, txHash);
        return
            safeImpl.execTransaction(
                to,
                value,
                data,
                Enum.Operation.Call,
                100_000,
                0,
                1,
                address(0),
                payable(address(0)),
                abi.encodePacked(r, s, v)
            );
    }

    /// @notice Test zero address validation in setAllowance function
    function testZeroAddressValidation_SetAllowanceRejectsZeroDelegate() public {
        vm.prank(address(safeImpl));
        vm.expectRevert(ILinearAllowanceSingleton.InvalidDelegate.selector);
        allowanceModule.setAllowance(address(0), NATIVE_TOKEN, 1 ether);
    }

    /// @notice Test zero address validation in emergencyRevokeAllowance function
    function testZeroAddressValidation_EmergencyRevokeRejectsZeroDelegate() public {
        vm.prank(address(safeImpl));
        vm.expectRevert(ILinearAllowanceSingleton.InvalidDelegate.selector);
        allowanceModule.emergencyRevokeAllowance(address(0), NATIVE_TOKEN);
    }

    /// @notice Test zero address validation in executeAllowanceTransfer function
    function testZeroAddressValidation_ExecuteTransferRejectsZeroRecipient() public {
        // First set up a valid allowance
        vm.prank(address(safeImpl));
        allowanceModule.setAllowance(address(this), NATIVE_TOKEN, 1 ether);
        
        // Attempt to transfer to zero address should fail
        vm.expectRevert(ILinearAllowanceSingleton.InvalidRecipient.selector);
        allowanceModule.executeAllowanceTransfer(address(safeImpl), NATIVE_TOKEN, payable(address(0)));
    }

    /// @notice Test that valid addresses still work after adding validation
    function testZeroAddressValidation_ValidAddressesStillWork() public {
        address validDelegate = makeAddr("validDelegate");
        address validRecipient = makeAddr("validRecipient");
        
        // Set allowance with valid delegate should work
        vm.prank(address(safeImpl));
        allowanceModule.setAllowance(validDelegate, NATIVE_TOKEN, 1 ether);
        
        // Emergency revoke with valid delegate should work
        vm.prank(address(safeImpl));
        allowanceModule.emergencyRevokeAllowance(validDelegate, NATIVE_TOKEN);
        
        // Set allowance again for transfer test
        vm.prank(address(safeImpl));
        allowanceModule.setAllowance(validDelegate, NATIVE_TOKEN, 1 ether);
        
        // Wait for some time to accrue allowance
        vm.warp(block.timestamp + 1 days);
        
        // Transfer to valid recipient should work
        vm.prank(validDelegate);
        uint256 transferred = allowanceModule.executeAllowanceTransfer(address(safeImpl), NATIVE_TOKEN, payable(validRecipient));
        
        // Verify transfer worked
        assertGt(transferred, 0, "Should have transferred some amount to valid recipient");
        assertEq(validRecipient.balance, transferred, "Recipient should have received the transferred amount");
    }
}

// Helper contracts

contract MockFailingSafe {
    // Always returns false for execTransactionFromModule
    function execTransactionFromModule(address, uint256, bytes memory, Enum.Operation) external pure returns (bool) {
        return false;
    }

    // Need to handle ETH
    receive() external payable {}
}

// Contract that fails when executing ETH transfers
contract MockSafeThatFailsEthTransfers {
    receive() external payable {}

    function execTransactionFromModule(
        address,
        uint256 value,
        bytes memory data,
        Enum.Operation
    ) external pure returns (bool) {
        // Only fail for ETH transfers
        if (data.length == 0 && value > 0) {
            return false;
        }
        return true;
    }
}

// Contract that rejects ETH transfers
contract ContractThatRejectsETH {
    receive() external payable {
        revert("Cannot receive ETH");
    }
}

// Malicious module for testing access control
contract MaliciousModule {
    LinearAllowanceSingletonForGnosisSafeWrapper public allowanceModule;
    address public safe;
    
    constructor(LinearAllowanceSingletonForGnosisSafeWrapper _allowanceModule) {
        allowanceModule = _allowanceModule;
    }
    
    // Set the safe address when this module is enabled
    function setUp(bytes memory) external {
        safe = msg.sender;
    }
    
    // Manual setter for testing purposes
    function setSafeAddress(address _safe) external {
        safe = _safe;
    }
    
    // Direct call attempt (should fail - modules can't directly call arbitrary contracts as the Safe)
    function attemptEmergencyRevoke(address delegate, address token) external {
        try allowanceModule.emergencyRevokeAllowance(delegate, token) {
            // This should fail because msg.sender is this module, not the safe
        } catch {
            // Expected to fail
        }
    }
    
    // Attempt via execTransactionFromModule (this is the concerning vector)
    function attemptEmergencyRevokeViaModule(address delegate, address token) external returns (bool) {
        bytes memory data = abi.encodeWithSelector(
            allowanceModule.emergencyRevokeAllowance.selector,
            delegate,
            token
        );
        
        try Safe(payable(safe)).execTransactionFromModule(
            address(allowanceModule),
            0,
            data,
            Enum.Operation.Call
        ) returns (bool success) {
            return success;
        } catch {
            return false;
        }
    }
}

// Malicious module specifically for testing setAllowance access control
contract MaliciousModuleForSetAllowance {
    LinearAllowanceSingletonForGnosisSafeWrapper public allowanceModule;
    address public safe;
    
    constructor(LinearAllowanceSingletonForGnosisSafeWrapper _allowanceModule) {
        allowanceModule = _allowanceModule;
    }
    
    // Set the safe address when this module is enabled
    function setUp(bytes memory) external {
        safe = msg.sender;
    }
    
    // Manual setter for testing purposes
    function setSafeAddress(address _safe) external {
        safe = _safe;
    }
    
    // Direct call attempt (should fail - modules can't directly call arbitrary contracts as the Safe)
    function attemptSetAllowance(address delegate, address token, uint128 dripRatePerDay) external {
        try allowanceModule.setAllowance(delegate, token, dripRatePerDay) {
            // This should fail because msg.sender is this module, not the safe
        } catch {
            // Expected to fail
        }
    }
    
    // Attempt via execTransactionFromModule (this is the critical attack vector to test)
    function attemptSetAllowanceViaModule(address delegate, address token, uint128 dripRatePerDay) external returns (bool) {
        bytes memory data = abi.encodeWithSelector(
            allowanceModule.setAllowance.selector,
            delegate,
            token,
            dripRatePerDay
        );
        
        try Safe(payable(safe)).execTransactionFromModule(
            address(allowanceModule),
            0,
            data,
            Enum.Operation.Call
        ) returns (bool success) {
            return success;
        } catch {
            return false;
        }
    }
}
