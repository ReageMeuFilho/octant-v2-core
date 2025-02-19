// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;
import "forge-std/Test.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxy.sol";
import {LinearAllowance} from "src/dragons/modules/LinearAllowance.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import {AllowanceExecutor} from "../../src/dragons/AllowanceExecutor.sol";

contract TestLinearAllowanceIntegration is Test {
    address delegateContractOwner = makeAddr("delegateContractOwner");
    address public token = address(0x0); // Native ETH

    Safe internal safeImpl;
    SafeProxyFactory internal safeProxyFactory;
    Safe internal singleton;
    LinearAllowance internal allowanceModule;
    AllowanceExecutor public allowanceExecutor;

    function setUp() public {
        // Deploy module
        allowanceModule = new LinearAllowance();

        // Deploy Safe infrastructure
        safeProxyFactory = new SafeProxyFactory();
        singleton = new Safe();
        
        // Create proxy Safe
        SafeProxy proxy = safeProxyFactory.createProxyWithNonce(
            address(singleton),
            "",
            0
        );
        safeImpl = Safe(payable(address(proxy)));

        // Fund Safe with ETH
        vm.deal(address(safeImpl), 2000 ether);

        // Initialize Safe
        address[] memory owners = new address[](1);
        owners[0] = vm.addr(1);
        safeImpl.setup(
            owners,
            1,
            address(0),
            bytes(""),
            address(0),
            address(0),
            0,
            payable(address(0))
        );

        // Enable SimpleAllowance module on Safe
        bytes memory enableData = abi.encodeWithSignature(
            "enableModule(address)", 
            address(allowanceModule)
        );
        bool ok = safeExecTransaction(
            address(safeImpl),  // Target: Safe itself
            0,                  // Value
            enableData,         // Enable module call
            1                   // Owner private key
        );
        require(ok, "Module enable failed");

        // Deploy DelegateContract
        vm.startPrank(delegateContractOwner);
        allowanceExecutor = new AllowanceExecutor(address(allowanceModule));
        vm.stopPrank();
    }

    function testSetAndUseAllowance() public {
        address safeAddress = address(safeImpl);
        address allowanceExecutorAddress = address(allowanceExecutor);

        // Add delegate through module
        vm.prank(safeAddress);
        allowanceModule.addDelegate(allowanceExecutorAddress);

        // Set allowance with drip rate
        vm.prank(safeAddress);
        allowanceModule.setAllowance(
            allowanceExecutorAddress,
            token,
            1000 ether   // Drip rate per day
        );

        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days); 

        // Execute transfer (no amount parameter needed, spends all available allowance)
        vm.prank(delegateContractOwner);
        allowanceExecutor.executeTransferLinear( 
            safeAddress,
            token
        );

        // Verify balances (1000 ether drip rate * 1 day)
        assertEq(address(allowanceExecutor).balance, 1000 ether, "Delegate should receive daily drip");
        assertEq(address(safeImpl).balance, 1000 ether, "Safe balance should reduce by drip amount");
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
            0,  // baseGas parameter removed from variable since it was always 0
            gasPrice,
            address(0),
            payable(address(0)),
            signature
        );
    }
}
