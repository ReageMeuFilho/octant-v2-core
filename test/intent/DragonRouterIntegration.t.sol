// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "./MockStrategy.sol";
import "./MockIntentProtocol.sol";
import "./MockDragonRouter.sol";
import "./MockESF.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MockETH is ERC20 {
    constructor() ERC20("Mock ETH", "mETH") {
        _mint(msg.sender, 1000_000_000 * 1e18);
    }
}

contract MockGLM is ERC20 {
    constructor() ERC20("Mock GLM", "GLM") {
        _mint(msg.sender, 1000_000_000 * 1e18);
    }
}

contract DragonRouterIntegrationTest is Test {
    using ECDSA for bytes32;

    MockETH public mockEth;
    MockGLM public mockGlm;
    MockStrategy public strategy;
    MockIntentProtocol public intentProtocol;
    MockDragonRouter public dragonRouter;
    MockESF public esf;
    address public operator = address(0x1);
    address public solver = address(0x3);
    uint256 private operatorKey;

    function setUp() public {
        operatorKey = 0xA11CE;
        operator = vm.addr(operatorKey);

        mockEth = new MockETH();
        mockGlm = new MockGLM();
        strategy = new MockStrategy(address(mockEth));
        mockEth.transfer(address(strategy), 1000000 * 1e18);

        intentProtocol = new MockIntentProtocol();
        dragonRouter = new MockDragonRouter(address(strategy), address(intentProtocol));
        esf = new MockESF(operator);

        // Setup ESF as recipient
        dragonRouter.addRecipient(address(esf), 5000, address(mockGlm)); // 50%

        // Fund the mock protocol with GLM for swaps
        mockGlm.transfer(address(intentProtocol), 100000 * 1e18);

        // ESF allows intentProtocol to spend mockETH
        vm.startPrank(address(esf));
        mockEth.approve(address(intentProtocol), 100000 * 1e18);
        vm.stopPrank();
    }

    function testWithdrawAndConvertFlow() public {
        // Generate yield by reporting
        dragonRouter.report();

        // Create signature for operator
        uint256 deadline = block.timestamp + 1 days;
        uint256 minOut = 40 * 1e18;

        bytes32 hash = keccak256(abi.encodePacked(deadline, minOut));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Operator calls withdrawAndConvert on behalf of ESF
        vm.startPrank(operator);
        bytes32 intentId = dragonRouter.withdrawAndConvert(
            address(esf), // sharesOwner
            deadline,
            minOut,
            signature
        );
        vm.stopPrank();

        // Execute the intent
        vm.startPrank(solver);
        intentProtocol.executeIntent(intentId, 50 * 1e18);
        vm.stopPrank();

        // Verify ESF received GLM
        assertEq(mockGlm.balanceOf(address(esf)), 50 * 1e18);

        // Try to withdraw again (should get 0 new shares)
        vm.startPrank(operator);
        vm.expectRevert("No new shares to claim");
        dragonRouter.withdrawAndConvert(address(esf), deadline, minOut, signature);
        vm.stopPrank();

        // Generate more yield
        dragonRouter.report();

        // Create new signature for new withdrawal
        deadline = block.timestamp + 1 days;
        minOut = 40 * 1e18;

        hash = keccak256(abi.encodePacked(deadline, minOut));
        (v, r, s) = vm.sign(operatorKey, hash);
        signature = abi.encodePacked(r, s, v);

        // Now operator should be able to withdraw again
        vm.startPrank(operator);
        bytes32 intentId2 = dragonRouter.withdrawAndConvert(address(esf), deadline, minOut, signature);
        vm.stopPrank();

        // Execute the second intent
        intentProtocol.executeIntent(intentId2, 50 * 1e18);

        // Verify ESF received more GLM
        assertEq(mockGlm.balanceOf(address(esf)), 100 * 1e18);
    }
}
