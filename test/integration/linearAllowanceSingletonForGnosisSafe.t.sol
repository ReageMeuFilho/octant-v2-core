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

contract TestERC20 is ERC20 {
    constructor(uint256 initialSupply) ERC20("TestToken", "TST") {
        _mint(msg.sender, initialSupply);
    }
}

contract TestLinearAllowanceIntegration is Test {
    address delegateContractOwner = makeAddr("delegateContractOwner");
    address public ETH = address(0x0); // Native ETH

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
        bool ok = safeExecTransaction(
            address(safeImpl), // Target: Safe itself
            0, // Value
            enableData, // Enable module call
            1 // Owner private key
        );
        require(ok, "Module enable failed");

        // Deploy DelegateContract
        vm.startPrank(delegateContractOwner);
        allowanceExecutor = new LinearAllowanceExecutor();
        vm.stopPrank();
    }

    function testSetAndUseAllowance(uint256 dripRatePerDay, uint256 daysElapsed) public {
        vm.assume(dripRatePerDay > 0 && dripRatePerDay < 1e8);
        vm.assume(daysElapsed > 0 && daysElapsed < 1e8);
        vm.assume(daysElapsed * dripRatePerDay < address(safeImpl).balance);
        uint256 safeBalance = address(safeImpl).balance;
        address safeAddress = address(safeImpl);
        address allowanceExecutorAddress = address(allowanceExecutor);

        vm.expectRevert();
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, ETH);

        // Set allowance with drip rate
        vm.prank(safeAddress);
        allowanceModule.setAllowance(allowanceExecutorAddress, ETH, dripRatePerDay);

        // Advance time
        vm.warp(block.timestamp + daysElapsed * 1 days);

        // Execute transfer (no amount parameter needed, spends all available allowance)
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, ETH);

        // Verify balances (1000 ether drip rate * 1 day)
        assertEq(
            address(allowanceExecutor).balance,
            dripRatePerDay * daysElapsed,
            "Delegate should receive daily drip"
        );
        assertEq(
            address(safeImpl).balance,
            safeBalance - (dripRatePerDay * daysElapsed),
            "Safe balance should reduce by drip amount"
        );

        vm.warp(block.timestamp + 10 days);
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, ETH);
        assertEq(
            address(allowanceExecutor).balance,
            dripRatePerDay * (daysElapsed + 10),
            "Delegate should receive daily drip"
        );

        vm.warp(block.timestamp + 10 days);

        vm.prank(safeAddress);
        allowanceModule.setAllowance(allowanceExecutorAddress, ETH, 0);

        uint256 totalUnspent = allowanceModule.getTotalUnspent(safeAddress, allowanceExecutorAddress, ETH);
        assertEq(totalUnspent, dripRatePerDay * 10, "Balance mismatch");

        vm.warp(block.timestamp + 15 days);
        totalUnspent = allowanceModule.getTotalUnspent(safeAddress, allowanceExecutorAddress, ETH);
        assertEq(totalUnspent, dripRatePerDay * 10, "Balance mismatch");

        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, ETH);
        assertEq(
            address(allowanceExecutor).balance,
            dripRatePerDay * (daysElapsed + 20),
            "Delegate should receive daily drip"
        );
    }

    function testSetAndUseAllowanceWithERC20(uint256 dripRatePerDay, uint256 daysElapsed) public {
        // Deploy test ERC20 token
        TestERC20 tokenContract = new TestERC20(2000 ether);
        address token = address(tokenContract);

        // Fund Safe with tokens
        tokenContract.transfer(address(safeImpl), tokenContract.balanceOf(address(this)));

        vm.assume(dripRatePerDay > 0 && dripRatePerDay < 1e8);
        vm.assume(daysElapsed > 0 && daysElapsed < 1e8);
        vm.assume(daysElapsed * dripRatePerDay < tokenContract.balanceOf(address(safeImpl)));

        address safeAddress = address(safeImpl);
        address allowanceExecutorAddress = address(allowanceExecutor);

        vm.expectRevert();
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, token);

        // Set allowance with drip rate
        vm.prank(safeAddress);
        allowanceModule.setAllowance(allowanceExecutorAddress, token, dripRatePerDay);

        // Advance time
        vm.warp(block.timestamp + daysElapsed * 1 days);

        // Execute transfer
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, token);

        // Verify token balances
        assertEq(
            tokenContract.balanceOf(allowanceExecutorAddress),
            dripRatePerDay * daysElapsed,
            "Delegate should receive daily drip"
        );
        assertEq(
            tokenContract.balanceOf(safeAddress),
            2000 ether - (dripRatePerDay * daysElapsed),
            "Safe balance should reduce by drip amount"
        );

        vm.warp(block.timestamp + 10 days);
        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, token);
        assertEq(
            tokenContract.balanceOf(allowanceExecutorAddress),
            dripRatePerDay * (daysElapsed + 10),
            "Delegate should receive accumulated drip"
        );

        vm.warp(block.timestamp + 10 days);
        vm.prank(safeAddress);
        allowanceModule.setAllowance(allowanceExecutorAddress, token, 0);

        uint256 totalUnspent = allowanceModule.getTotalUnspent(safeAddress, allowanceExecutorAddress, token);
        assertEq(totalUnspent, dripRatePerDay * 10, "Balance mismatch after rate change");

        vm.warp(block.timestamp + 15 days);
        totalUnspent = allowanceModule.getTotalUnspent(safeAddress, allowanceExecutorAddress, token);
        assertEq(totalUnspent, dripRatePerDay * 10, "Balance should stop accruing after rate set to 0");

        allowanceExecutor.executeAllowanceTransfer(allowanceModule, safeAddress, token);
        assertEq(
            tokenContract.balanceOf(allowanceExecutorAddress),
            dripRatePerDay * (daysElapsed + 20),
            "Final balance should match total accrued"
        );
    }

    function safeExecTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint256 ownerPrivateKey
    ) internal returns (bool success) {
        uint256 safeTxGas = 100_000;
        uint256 baseGas = 0;
        uint256 gasPrice = 1;

        bytes32 txHash = safeImpl.getTransactionHash(
            to,
            value,
            data,
            Enum.Operation.Call,
            safeTxGas,
            baseGas,
            gasPrice,
            address(0),
            payable(address(0)),
            safeImpl.nonce()
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, txHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        success = safeImpl.execTransaction(
            to,
            value,
            data,
            Enum.Operation.Call,
            safeTxGas,
            0, // baseGas parameter removed from variable since it was always 0
            gasPrice,
            address(0),
            payable(address(0)),
            signature
        );
    }
}
