pragma solidity >=0.8.0 <0.9.0;
import "forge-std/Test.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxy.sol";
import { AllowanceModule } from "src/dragons/modules/Allowance.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { AllowanceExecutor } from "../../src/dragons/AllowanceExecutor.sol";

contract TestAllowanceIntegration is Test {
    address public token = address(0x0); // address(0) is the native token in Gnosis Safe Allowance Module

    // References to your Safe and Allowance Module
    Safe internal safeImpl; // We'll do direct calls with Safe methods
    AllowanceModule internal allowanceModule;

    // Proxy factory references
    SafeProxyFactory internal safeProxyFactory;
    Safe internal singleton;

    AllowanceExecutor public allowanceExecutor;

    function setUp() public {
        // 1. Deploy module FIRST
        allowanceModule = new AllowanceModule();

        // 2. Deploy factory/singleton
        safeProxyFactory = new SafeProxyFactory();
        singleton = new Safe();

        // 3. Create proxy
        SafeProxy proxy = safeProxyFactory.createProxyWithNonce(address(singleton), "", 0);
        safeImpl = Safe(payable(address(proxy)));

        // Fund Safe with Ether after deployment
        vm.deal(address(safeImpl), 2000 ether);

        // 4. Initialize Safe with basic config
        address[] memory owners = new address[](1);
        owners[0] = vm.addr(1);

        safeImpl.setup(owners, 1, address(0), bytes(""), address(0), address(0), 0, payable(address(0)));

        // 5. Enable module via proper Safe transaction
        bytes memory enableData = abi.encodeWithSignature("enableModule(address)", address(allowanceModule));
        bool ok = safeExecTransaction(address(safeImpl), 0, enableData, Enum.Operation.Call, 1);
        assertEq(ok, true, "Module enable failed");

        // Initialize timestamp
        vm.warp(60);

        // Deploy executor contract
        allowanceExecutor = new AllowanceExecutor(address(allowanceModule));
    }

    function testSetAndUseAllowance() public {
        address safeAddress = address(safeImpl);
        address allowanceExecutorAddress = address(allowanceExecutor);

        // Set allowance for contract delegate
        vm.startPrank(safeAddress);
        allowanceModule.addDelegate(allowanceExecutorAddress);
        assertTrue(allowanceModule.isDelegate(safeAddress, allowanceExecutorAddress), "Delegate not registered");

        allowanceModule.setAllowance(
            allowanceExecutorAddress,
            address(token),
            1000 ether,
            1,
            uint32(block.timestamp / 60)
        );

        uint256[5] memory dataBefore = allowanceModule.getTokenAllowance(
            safeAddress,
            allowanceExecutorAddress,
            address(token)
        );
        assertEq(dataBefore[0], 1000 ether, "Initial allowance mismatch");
        assertEq(dataBefore[1], 0, "Initial spent allowance should be 0");
        assertEq(dataBefore[2], 60, "Reset time mismatch");
        assertEq(dataBefore[3], 60, "Last reset time mismatch");

        vm.warp(block.timestamp + 61);
        vm.stopPrank();

        // Execute transfer
        allowanceExecutor.executeTransfer(safeAddress, address(token), 200 ether);

        // Verify balances
        assertEq(address(allowanceExecutor).balance, 200 ether, "Contract ETH balance mismatch");
        assertEq(address(safeAddress).balance, 1800 ether, "Safe ETH balance mismatch");
    }

    function safeExecTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 ownerPrivateKey
    ) internal returns (bool success) {
        uint256 safeTxGas = 100_000;
        uint256 gasPrice = 1;

        bytes32 txHash = safeImpl.getTransactionHash(
            to,
            value,
            data,
            operation,
            safeTxGas,
            0,
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
            operation,
            safeTxGas,
            0,
            gasPrice,
            address(0),
            payable(address(0)),
            signature
        );
    }
}
