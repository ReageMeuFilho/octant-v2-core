// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { LinearAllowanceExecutorTestHarness } from "test/mocks/zodiac-core/LinearAllowanceExecutorTestHarness.sol";
import { LinearAllowanceSingletonForGnosisSafe } from "src/zodiac-core/modules/LinearAllowanceSingletonForGnosisSafe.sol";
import { LinearAllowanceExecutor } from "src/zodiac-core/LinearAllowanceExecutor.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockSafe } from "test/mocks/zodiac-core/MockSafe.sol";
import { NATIVE_TOKEN } from "src/constants.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";

contract LinearAllowanceExecutorTest is Test {
    LinearAllowanceExecutorTestHarness public executor;
    LinearAllowanceSingletonForGnosisSafe public allowanceModule;
    MockSafe public mockSafe;
    MockERC20 public mockToken;
    Whitelist public moduleWhitelist;

    uint192 constant DRIP_RATE = 1 ether; // 1 token per day

    function setUp() public {
        // Deploy contracts
        executor = new LinearAllowanceExecutorTestHarness();
        allowanceModule = new LinearAllowanceSingletonForGnosisSafe();
        mockSafe = new MockSafe();
        mockToken = new MockERC20(18);
        moduleWhitelist = new Whitelist();

        // Set the whitelist on the executor
        executor.setModuleWhitelist(IWhitelist(address(moduleWhitelist)));

        // Whitelist the allowance module
        moduleWhitelist.addToWhitelist(address(allowanceModule));

        // Enable module on mock Safe
        mockSafe.enableModule(address(allowanceModule));

        // Fund Safe with ETH and tokens
        vm.deal(address(mockSafe), 10 ether);
        mockToken.mint(address(mockSafe), 10 ether);
    }

    function testExecuteAllowanceTransferWithNativeToken() public {
        // Set up allowance for executor
        vm.prank(address(mockSafe));
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, DRIP_RATE);

        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);

        // Get executor's balance before transfer
        uint256 executorBalanceBefore = address(executor).balance;

        // Execute allowance transfer
        uint256 transferredAmount = executor.executeAllowanceTransfer(allowanceModule, address(mockSafe), NATIVE_TOKEN);

        // Verify transfer
        assertEq(transferredAmount, DRIP_RATE, "Should transfer the exact drip rate amount");
        assertEq(
            address(executor).balance - executorBalanceBefore,
            DRIP_RATE,
            "Executor balance should increase by the transferred amount"
        );
    }

    function testExecuteAllowanceTransferWithERC20() public {
        // Set up allowance for executor
        vm.prank(address(mockSafe));
        allowanceModule.setAllowance(address(executor), address(mockToken), DRIP_RATE);

        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);

        // Get executor's token balance before transfer
        uint256 executorBalanceBefore = mockToken.balanceOf(address(executor));

        // Execute allowance transfer
        uint256 transferredAmount = executor.executeAllowanceTransfer(
            allowanceModule,
            address(mockSafe),
            address(mockToken)
        );

        // Verify transfer
        assertEq(transferredAmount, DRIP_RATE, "Should transfer the exact drip rate amount");
        assertEq(
            mockToken.balanceOf(address(executor)) - executorBalanceBefore,
            DRIP_RATE,
            "Executor token balance should increase by the transferred amount"
        );
    }

    function testGetTotalUnspent() public {
        // Set up allowance for executor
        vm.prank(address(mockSafe));
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, DRIP_RATE);

        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);

        // Get total unspent allowance
        uint256 totalUnspent = executor.getTotalUnspent(allowanceModule, address(mockSafe), NATIVE_TOKEN);

        // Verify result
        assertEq(totalUnspent, DRIP_RATE, "Total unspent should equal the drip rate after 1 day");
    }

    function testReceiveEther() public {
        uint256 sendAmount = 1 ether;
        vm.deal(address(this), sendAmount);

        uint256 executorBalanceBefore = address(executor).balance;

        (bool success, ) = address(executor).call{ value: sendAmount }("");
        assertTrue(success, "Ether transfer should succeed");

        uint256 executorBalanceAfter = address(executor).balance;
        assertEq(executorBalanceAfter - executorBalanceBefore, sendAmount, "Should receive the sent ether");
    }

    function testPartialAllowanceTransfer() public {
        // Set up allowance for executor
        vm.prank(address(mockSafe));
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, DRIP_RATE);

        // Advance time to accrue allowance
        vm.warp(block.timestamp + 1 days);

        // Reduce Safe's balance to be less than allowance
        uint256 safeBalance = 0.5 ether;
        vm.deal(address(mockSafe), safeBalance);

        // Execute allowance transfer
        uint256 transferredAmount = executor.executeAllowanceTransfer(allowanceModule, address(mockSafe), NATIVE_TOKEN);

        // Verify transfer
        assertEq(transferredAmount, safeBalance, "Should transfer only the available balance");
    }

    function testModuleWhitelistValidation() public {
        // Deploy a new module that is not whitelisted
        LinearAllowanceSingletonForGnosisSafe nonWhitelistedModule = new LinearAllowanceSingletonForGnosisSafe();

        // Try to use non-whitelisted module - should revert
        vm.expectRevert(
            abi.encodeWithSelector(LinearAllowanceExecutor.ModuleNotWhitelisted.selector, address(nonWhitelistedModule))
        );
        executor.executeAllowanceTransfer(nonWhitelistedModule, address(mockSafe), NATIVE_TOKEN);

        // Whitelist the module
        moduleWhitelist.addToWhitelist(address(nonWhitelistedModule));

        // Now it should work (will revert for different reason - no allowance set)
        vm.expectRevert(); // Different revert reason
        executor.executeAllowanceTransfer(nonWhitelistedModule, address(mockSafe), NATIVE_TOKEN);

        // Remove from whitelist
        moduleWhitelist.removeFromWhitelist(address(nonWhitelistedModule));

        // Should revert again with whitelist error
        vm.expectRevert(
            abi.encodeWithSelector(LinearAllowanceExecutor.ModuleNotWhitelisted.selector, address(nonWhitelistedModule))
        );
        executor.executeAllowanceTransfer(nonWhitelistedModule, address(mockSafe), NATIVE_TOKEN);
    }

    function testExecuteMultipleTransfersWithChangingAllowance() public {
        // Set up allowance for executor
        vm.prank(address(mockSafe));
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, DRIP_RATE);

        // Advance time to accrue allowance
        skip(1 days);
        vm.roll(1);

        // First transfer
        uint256 transferredAmount1 = executor.executeAllowanceTransfer(
            allowanceModule,
            address(mockSafe),
            NATIVE_TOKEN
        );

        // Increase drip rate
        vm.prank(address(mockSafe));
        allowanceModule.setAllowance(address(executor), NATIVE_TOKEN, DRIP_RATE * 2);

        // Advance time to accrue more allowance
        skip(1 days);
        vm.roll(block.number + 1);

        // Second transfer
        uint256 transferredAmount2 = executor.executeAllowanceTransfer(
            allowanceModule,
            address(mockSafe),
            NATIVE_TOKEN
        );

        // Verify transfers
        assertEq(transferredAmount1, DRIP_RATE, "First transfer should use original drip rate");
        assertEq(transferredAmount2, DRIP_RATE * 2, "Second transfer should use updated drip rate");
    }
}
