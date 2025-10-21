// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import { BaseGuard } from "zodiac/guard/BaseGuard.sol";
import { Enum } from "zodiac/interfaces/IAvatar.sol";
import { FactoryFriendly } from "zodiac/factory/FactoryFriendly.sol";

/// @notice Thrown when attempting to disable guard before lock period ends
error AntiLoopholeGuard__LockPeriodNotEnded();

/**
 * @title AntiLoopholeGuard
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Zodiac guard preventing dangerous operations during initial lock period
 * @dev Protects Safes from delegatecalls and unauthorized module additions for 25 days
 *
 *      SECURITY MODEL:
 *      During LOCK_DURATION (25 days from deployment):
 *      - Blocks ALL delegatecalls (operation == DelegateCall)
 *      - Blocks enableModule() calls (prevents adding malicious modules)
 *      - Normal calls allowed (operation == Call)
 *
 *      AFTER LOCK_DURATION:
 *      - Owner can call disableGuard() to remove restrictions
 *      - Guard becomes no-op (isDisabled = true)
 *      - Safe regains full functionality
 *
 *      USE CASE:
 *      Prevents immediate rug-pull after Safe deployment by:
 *      1. Blocking delegatecall-based ownership transfers
 *      2. Preventing addition of malicious modules
 *      3. Giving users 25 days to verify Safe configuration
 *
 *      INTEGRATION:
 *      - Attach to Safe via setGuard(address(antiLoopholeGuard))
 *      - Safe owner can disable after 25 days
 *      - Does not prevent normal Safe operations
 *
 * @custom:security Time-based protection - owner must wait LOCK_DURATION to disable
 */
contract AntiLoopholeGuard is FactoryFriendly, BaseGuard {
    /// @notice Timestamp when lock period ends and guard can be disabled
    /// @dev Set to block.timestamp + LOCK_DURATION in setUp()
    uint256 public lockEndTime;

    /// @notice Lock duration in seconds (25 days)
    /// @dev Prevents disabling guard prematurely
    uint256 public constant LOCK_DURATION = 25 days;

    /// @notice Whether guard is disabled
    /// @dev When true, guard performs no checks (allows all operations)
    bool public isDisabled;

    /// @notice Thrown when delegatecall attempted during lock period
    error DelegateCallNotAllowed();

    /// @notice Thrown when enableModule() called during lock period
    error ModuleAdditionNotAllowed();

    /// @notice Thrown when attempting to disable already-disabled guard
    error GuardAlreadyDisabled();

    /**
     * @notice Creates anti-loophole guard with specified owner
     * @param _owner Address that can disable guard after lock period
     */
    constructor(address _owner) {
        bytes memory initializeParams = abi.encode(_owner);
        setUp(initializeParams);
    }

    /**
     * @notice Initializes guard with owner and lock period
     * @dev Sets lockEndTime to block.timestamp + 25 days
     * @param initializeParams ABI-encoded owner address
     */
    function setUp(bytes memory initializeParams) public override initializer {
        address _owner = abi.decode(initializeParams, (address));
        lockEndTime = block.timestamp + LOCK_DURATION;
        __Ownable_init(_owner);
    }

    /**
     * @notice Pre-transaction check enforcing guard rules
     * @dev Called by Safe before every transaction execution
     *
     *      CHECKS DURING LOCK PERIOD:
     *      - Reverts if operation is DelegateCall
     *      - Reverts if calling enableModule()
     *
     *      BYPASSES:
     *      - If isDisabled == true (guard permanently disabled)
     *      - If to == address(0) (contract creation)
     *      - If block.timestamp >= lockEndTime (lock expired)
     * @param to Transaction target address
     * @param data Transaction calldata
     * @param operation Operation type (Call or DelegateCall)
     */
    // solhint-disable-next-line code-complexity
    function checkTransaction(
        address to,
        uint256,
        bytes memory data,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external view virtual override {
        if (isDisabled) {
            return;
        }
        if (to == address(0)) {
            return;
        }
        if (block.timestamp < lockEndTime) {
            if (operation == Enum.Operation.DelegateCall) {
                revert DelegateCallNotAllowed();
            }

            bytes4 functionSig = bytes4(data);
            if (functionSig == bytes4(keccak256("enableModule(address)"))) {
                // maybe whilelist some modules here
                revert ModuleAdditionNotAllowed();
            }
        }
    }

    /**
     * @notice Post-transaction check (currently no-op)
     * @dev Can be overridden for balance/state checks
     */
    function checkAfterExecution(bytes32, bool) external view virtual override {
        // balance checks against Avatar go here, leave the function virtual and override
    }

    /**
     * @notice Permanently disables guard after lock period
     * @dev Can only be called by owner after lockEndTime
     *      Once disabled, guard allows all operations (cannot be re-enabled)
     */
    function disableGuard() external onlyOwner {
        require(block.timestamp >= lockEndTime, AntiLoopholeGuard__LockPeriodNotEnded());
        if (isDisabled) revert GuardAlreadyDisabled();
        isDisabled = true;
    }
}
