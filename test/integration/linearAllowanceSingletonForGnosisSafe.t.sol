// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;
import "forge-std/Test.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxy.sol";
import { LinearAllowanceSingletonForGnosisSafe } from "src/dragons/modules/LinearAllowanceSingletonForGnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { LinearAllowanceExecutor } from "../../src/dragons/LinearAllowanceExecutor.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { NoAllowanceToTransfer } from "src/dragons/modules/LinearAllowanceSingletonForGnosisSafe.sol";

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

        // Initialize Safe
        address[] memory owners = new address[](1);
        owners[0] = vm.addr(1);
        safeImpl.setup(
            owners,
            1,
            address(0),
            bytes(""),
            address(0),
            allowanceModule.NATIVE_TOKEN(),
            0,
            payable(address(0))
        );

        // Enable SimpleAllowance module on Safe
        bytes memory enableData = abi.encodeWithSignature("enableModule(address)", address(allowanceModule));
        bool ok = execSafeTransaction(address(safeImpl), 0, enableData, 1);
        require(ok, "Module enable failed");

        // Deploy DelegateContract
        vm.startPrank(delegateContractOwner);
        allowanceExecutor = new LinearAllowanceExecutor();
        vm.stopPrank();
    }

    function decompress80to112(uint80 input) internal view returns (uint112) {
        return uint112(input) << allowanceModule.NUMBER_OF_LEAST_SIGNIFICANT_BITS_TO_TRIM();
    }

    function decompress64to96(uint64 input) internal view returns (uint96) {
        return uint96(input) << allowanceModule.NUMBER_OF_LEAST_SIGNIFICANT_BITS_TO_TRIM();
    }

    function compress112to80(uint112 input) internal view returns (uint80) {
        return uint80(input >> allowanceModule.NUMBER_OF_LEAST_SIGNIFICANT_BITS_TO_TRIM());
    }

    function compress96to64(uint96 input) internal view returns (uint64) {
        return uint64(input >> allowanceModule.NUMBER_OF_LEAST_SIGNIFICANT_BITS_TO_TRIM());
    }

    function trimLast32BitsOf256(uint256 input) internal pure returns (uint256) {
        // Mask to preserve all bits except the last 32 bits
        uint256 mask = uint256(0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_00000000);
        return input & mask;
    }

    // Test ETH allowance with both full and partial withdrawals
    function testAllowanceWithETH(uint64 compressedDripRate, uint256 daysElapsed, uint256 safeBalance) public {
        vm.assume(compressedDripRate > 0);
        daysElapsed = bound(daysElapsed, 1, (2 ** 15));

        uint96 decompressedDripRate = decompress64to96(compressedDripRate);

        uint112 expectedAllowance = uint112(decompressedDripRate * daysElapsed);

        safeBalance = bound(safeBalance, expectedAllowance / 10, expectedAllowance * 2);

        // Setup
        address safeAddress = address(safeImpl);
        address executorAddress = address(allowanceExecutor);

        // Set the safe's balance
        vm.deal(safeAddress, safeBalance);

        // First store the address
        address nativeToken = allowanceModule.NATIVE_TOKEN();

        // Then use the stored address in the expectRevert
        vm.expectRevert(
            abi.encodeWithSelector(NoAllowanceToTransfer.selector, safeAddress, address(allowanceExecutor), nativeToken)
        );
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, nativeToken);

        vm.prank(safeAddress);
        allowanceModule.setAllowance(executorAddress, nativeToken, uint96(decompressedDripRate));

        // Advance time to accrue allowance
        vm.warp(block.timestamp + daysElapsed * 1 days);

        // Get balances before transfer
        uint256 safeBalanceBefore = safeAddress.balance;
        uint256 executorBalanceBefore = executorAddress.balance;

        // Expected transfer is the minimum of allowance and balance
        uint256 expectedTransfer = expectedAllowance <= trimLast32BitsOf256(safeBalanceBefore)
            ? expectedAllowance
            : trimLast32BitsOf256(safeBalanceBefore);

        uint112 actualTransferred = allowanceExecutor.executeAllowanceTransfer(
            allowanceModule,
            safeAddress,
            nativeToken
        );

        assertEq(
            executorAddress.balance - executorBalanceBefore,
            actualTransferred,
            "Executor should receive correct amount"
        );

        assertEq(
            safeBalanceBefore - safeAddress.balance,
            actualTransferred,
            "Safe balance should be reduced by transferred amount"
        );

        assertEq(actualTransferred, expectedTransfer, "Transferred amount should match expected");

        // Verify allowance bookkeeping
        uint112[4] memory allowanceData = allowanceModule.getTokenAllowanceData(
            safeAddress,
            executorAddress,
            nativeToken
        );

        if (expectedAllowance > safeBalanceBefore) {
            // Partial withdrawal case - there should be remaining allowance
            uint112 expectedRemainingDecompressed = uint112(expectedAllowance - actualTransferred);
            assertEq(allowanceData[1], expectedRemainingDecompressed, "Remaining unspent should match expected");
        } else {
            // Full withdrawal case - allowance should be zero
            assertEq(allowanceData[1], 0, "Unspent allowance should be zero");
        }

        // Test that allowance stops accruing after rate set to 0
        vm.warp(block.timestamp + 5 days);
        vm.prank(safeAddress);
        allowanceModule.setAllowance(executorAddress, nativeToken, 0);

        uint256 unspentAfterZeroRate = allowanceModule.getTotalUnspent(safeAddress, executorAddress, nativeToken);
        vm.warp(block.timestamp + 10 days);

        assertEq(
            allowanceModule.getTotalUnspent(safeAddress, executorAddress, nativeToken),
            unspentAfterZeroRate,
            "Balance should not increase after rate set to 0"
        );
    }

    // Test ERC20 allowance with both full and partial withdrawals
    function testAllowanceWithERC20(uint64 compressedDripRate, uint256 daysElapsed, uint256 tokenSupply) public {
        vm.assume(compressedDripRate > 0);
        daysElapsed = bound(daysElapsed, 1, (2 ** 15));

        uint96 decompressedDripRate = decompress64to96(compressedDripRate);

        uint256 expectedAllowance = decompressedDripRate * daysElapsed;

        tokenSupply = bound(tokenSupply, expectedAllowance / 10, expectedAllowance * 2);

        // Setup
        address safeAddress = address(safeImpl);
        address executorAddress = address(allowanceExecutor);

        // Create token and fund safe
        TestERC20 token = new TestERC20(tokenSupply);
        token.transfer(safeAddress, tokenSupply);

        vm.expectRevert(
            abi.encodeWithSelector(NoAllowanceToTransfer.selector, safeAddress, address(allowanceExecutor), token)
        );
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, address(token));

        vm.prank(safeAddress);
        allowanceModule.setAllowance(executorAddress, address(token), decompressedDripRate);

        // Advance time to accrue allowance
        vm.warp(block.timestamp + daysElapsed * 1 days);

        // Get balances before transfer
        uint256 safeBalanceBefore = token.balanceOf(safeAddress);
        uint256 executorBalanceBefore = token.balanceOf(executorAddress);

        // Expected transfer is the minimum of allowance and balance
        uint256 expectedTransfer = expectedAllowance <= trimLast32BitsOf256(safeBalanceBefore)
            ? expectedAllowance
            : trimLast32BitsOf256(safeBalanceBefore);

        // Execute transfer
        uint256 actualTransferred = allowanceExecutor.executeAllowanceTransfer(
            allowanceModule,
            safeAddress,
            address(token)
        );

        // Verify actual transferred amounts
        assertEq(
            token.balanceOf(executorAddress) - executorBalanceBefore,
            actualTransferred,
            "Executor should receive correct token amount"
        );

        assertEq(
            safeBalanceBefore - token.balanceOf(safeAddress),
            actualTransferred,
            "Safe token balance should be reduced by transferred amount"
        );

        assertEq(actualTransferred, expectedTransfer, "Transferred amount should match expected");

        uint112[4] memory allowanceData = allowanceModule.getTokenAllowanceData(
            safeAddress,
            executorAddress,
            address(token)
        );

        if (expectedAllowance > safeBalanceBefore) {
            // Partial withdrawal case - there should be remaining allowance
            uint112 expectedRemainingDecompressed = uint112(expectedAllowance - actualTransferred);
            assertEq(allowanceData[1], expectedRemainingDecompressed, "Remaining unspent should match expected");
        } else {
            // Full withdrawal case - allowance should be zero
            assertEq(allowanceData[1], 0, "Unspent allowance should be zero");
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
