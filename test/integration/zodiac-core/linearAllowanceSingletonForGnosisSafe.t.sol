// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;
import "forge-std/Test.sol";
import "lib/safe-smart-account/contracts/Safe.sol";
import "lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import "lib/safe-smart-account/contracts/proxies/SafeProxy.sol";
import { LinearAllowanceSingletonForGnosisSafeWrapper } from "test/wrappers/LinearAllowanceSingletonForGnosisSafeWrapper.sol";
import { NATIVE_TOKEN } from "src/constants.sol";
import "lib/safe-smart-account/contracts/libraries/Enum.sol";
import { LinearAllowanceExecutor } from "src/zodiac-core/LinearAllowanceExecutor.sol";
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
    LinearAllowanceExecutor public allowanceExecutor;
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
        allowanceExecutor = new LinearAllowanceExecutor();
        vm.stopPrank();
    }

    // Test ETH allowance with both full and partial withdrawals
    function testAllowanceWithETH(uint128 dripRatePerDay, uint256 daysElapsed, uint256 safeBalance) public {
        // Constrain inputs to reasonable values
        vm.assume(dripRatePerDay > 0 ether);
        daysElapsed = uint32(bound(daysElapsed, 1, 365 * 20));

        // Calculate expected allowance
        uint160 expectedAllowance = uint160(dripRatePerDay) * uint160(daysElapsed);

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
        allowanceModule.setAllowance(executorAddress, NATIVE_TOKEN, uint128(dripRatePerDay));

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
        (, uint160 totalUnspent, , ) = allowanceModule.getTokenAllowanceData(
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
    function testAllowanceWithERC20(uint128 dripRatePerDay, uint256 daysElapsed, uint256 tokenSupply) public {
        // Constrain inputs to reasonable values
        vm.assume(dripRatePerDay > 0 ether);
        daysElapsed = uint32(bound(daysElapsed, 1, 365 * 20));

        // Calculate expected allowance
        uint160 expectedAllowance = uint160(dripRatePerDay) * uint160(daysElapsed);

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
        allowanceModule.setAllowance(executorAddress, address(token), uint128(dripRatePerDay));

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
        (, uint160 totalUnspent, , ) = allowanceModule.getTokenAllowanceData(
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
        allowanceModule.setAllowance(address(allowanceExecutor), address(token), uint128(100 ether));

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
        LinearAllowanceExecutor executor = new LinearAllowanceExecutor();

        // Set allowance for ETH (using address(0) as native token)
        vm.prank(address(failingSafe));
        allowanceModule.setAllowance(address(executor), address(0), uint128(100 ether));

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
        LinearAllowanceExecutor executor = new LinearAllowanceExecutor();

        // Create an allowance
        vm.prank(address(safe));
        allowanceModule.setAllowance(address(executor), address(testToken), uint128(100 ether));

        // Fast forward time
        vm.warp(block.timestamp + 1 days);

        // Call setAllowance again which invokes _updateAllowance
        vm.prank(address(safe));
        allowanceModule.setAllowance(address(executor), address(testToken), uint128(200 ether));

        // Verify the allowance was updated correctly
        (uint128 dripRate, uint160 unspent, , uint32 lastBooked) = allowanceModule.getTokenAllowanceData(
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
            dripRatePerDay: uint128(dripRate),
            totalUnspent: uint160(0),
            totalSpent: uint192(0),
            // Set a more recent timestamp to avoid large time differences
            lastBookedAtInSeconds: uint32(block.timestamp - 1 hours) // Use 1 hour instead of 1 day
        });

        // Call the exposed function
        ILinearAllowanceSingleton.LinearAllowance memory updatedAllowance = wrapper.exposeUpdateAllowance(allowance);

        // Calculate expected unspent amount (1 ETH per day, for 1 hour = 1/24 ETH)
        uint256 expectedUnspent = (dripRate * 1 hours) / 1 days;

        // Verify the return value
        assertEq(updatedAllowance.dripRatePerDay, dripRate);
        assertEq(updatedAllowance.totalUnspent, uint160(expectedUnspent));
        assertEq(updatedAllowance.lastBookedAtInSeconds, uint32(block.timestamp));
        assertEq(updatedAllowance.totalSpent, 0, "Total spent should remain unchanged");
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
