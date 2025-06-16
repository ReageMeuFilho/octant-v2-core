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
