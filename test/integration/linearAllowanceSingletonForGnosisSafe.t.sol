// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;
import "forge-std/Test.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxy.sol";
import { LinearAllowanceSingletonForGnosisSafe } from "src/dragons/modules/LinearAllowanceSingletonForGnosisSafe.sol";
import { NATIVE_TOKEN } from "src/constants.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { LinearAllowanceExecutor } from "../../src/dragons/LinearAllowanceExecutor.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
    LinearAllowanceSingletonForGnosisSafe internal allowanceModule;
    LinearAllowanceExecutor public allowanceExecutor;

    function setUp() public {
        // Deploy module
        allowanceModule = new LinearAllowanceSingletonForGnosisSafe();
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
