// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { Module } from "zodiac/core/Module.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { Unauthorized } from "src/errors.sol";

error OctantRewardsSafe__YieldNotInRange(uint256 yield, uint256 maxYield);
error OctantRewardsSafe__TransferFailed(uint256 yield);
error OctantRewardsSafe__InvalidNumberOfValidators(uint256 amount);
error OctantRewardsSafe__InvalidAddress(address a);
error OctantRewardsSafe__InvalidMaxYield(uint256 maxYield);

/**
 * @title OctantRewardsSafe
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Gnosis Safe module for managing validator yield distribution in Octant
 * @dev Zodiac module that routes ETH staking yield to dragon router while managing validator lifecycle
 *
 *      VALIDATOR MANAGEMENT:
 *      - Owner requests new validators or exits via requestNewValidators/requestExitValidators
 *      - Keeper confirms validator changes via confirmNewValidators/confirmExitValidators
 *      - Principal (32 ETH per validator) returned to treasury on exit
 *
 *      YIELD FLOW:
 *      1. Safe accumulates validator yield as ETH balance
 *      2. harvest() callable by anyone when yield available
 *      3. Yield transferred to dragonRouter via Safe.execTransactionFromModule()
 *      4. Principal stays in Safe or returned to treasury on exit
 *
 *      SAFETY LIMITS:
 *      - maxYield prevents excessive single harvest (32 ETH per validator max)
 *      - Protects against MEV/manipulation via harvest front-running
 *
 *      ROLES:
 *      - Owner (Safe): Requests validator changes, updates addresses
 *      - Keeper: Confirms validator status changes on-chain
 *      - Treasury: Receives principal when validators exit
 *      - DragonRouter: Receives harvested yield
 *
 *      INVARIANTS:
 *      - totalValidators * 32 ETH = expected principal in Safe
 *      - harvest() yield must be > 0 and < maxYield
 *      - Validator changes require two-step owner → keeper flow
 *
 * @custom:security Permissionless harvest but yield-limited via maxYield
 * @custom:security Two-step validator management prevents unauthorized changes
 */
contract OctantRewardsSafe is Module {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Address authorized to confirm validator changes
    /// @dev Operator managing validator nodes, confirms on-chain status
    address public keeper;

    /// @notice Address receiving principal when validators exit
    /// @dev Receives 32 ETH per exited validator
    address public treasury;

    /// @notice Address receiving harvested yield
    /// @dev Typically DragonRouter for yield distribution
    address public dragonRouter;

    /// @notice Current number of active validators
    /// @dev Each validator represents 32 ETH of principal
    uint256 public totalValidators;

    /// @notice Pending validators requested by owner
    /// @dev Cleared to 0 after keeper confirms via confirmNewValidators()
    uint256 public newValidators;

    /// @notice Pending validator exits requested by owner
    /// @dev Cleared to 0 after keeper confirms via confirmExitValidators()
    uint256 public exitedValidators;

    /// @notice Cumulative yield harvested to dragon router
    /// @dev Incremented on each harvest() call, measured in wei
    uint256 public totalYield;

    /// @notice Timestamp of most recent harvest
    /// @dev Used to calculate time period between harvests for reporting
    uint256 public lastHarvested;

    /// @notice Maximum yield harvestable in single harvest() call
    /// @dev Must be > 0 and < 32 ETH. Prevents excessive single harvests
    uint256 public maxYield;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when ETH is transferred from Safe
    /// @param from Address sending ETH (Safe)
    /// @param to Address receiving ETH
    /// @param amount Amount of ETH transferred in wei
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when treasury address is updated
    /// @param oldAddress Previous treasury address
    /// @param newAddress New treasury address
    event TreasuryUpdated(address oldAddress, address newAddress);
    /// @notice Emitted when dragon router address is updated
    /// @param oldAddress Previous dragon router address
    /// @param newAddress New dragon router address
    event DragonRouterUpdated(address oldAddress, address newAddress);
    /// @notice Emitted when yield is harvested and reported
    /// @param yield Amount of yield harvested in wei
    /// @param totalDepositedAssets Total principal deposited (32 ETH * validators)
    /// @param timePeriod Time since last harvest in seconds
    event Report(uint256 yield, uint256 totalDepositedAssets, uint256 timePeriod);
    /// @notice Emitted when owner requests validator exits
    /// @param amount Number of validators requested to exit
    /// @param totalExitedValidators Total validators requested to exit (pending confirmation)
    event RequestExitValidators(uint256 amount, uint256 totalExitedValidators);
    /// @notice Emitted when owner requests new validators
    /// @param amount Number of new validators requested
    /// @param totalNewValidators Total new validators requested (pending confirmation)
    event RequestNewValidators(uint256 amount, uint256 totalNewValidators);
    /// @notice Emitted when max yield per harvest is updated
    /// @param oldMaxYield Previous max yield in wei
    /// @param newMaxYield New max yield in wei
    event MaxYieldUpdated(uint256 oldMaxYield, uint256 newMaxYield);
    /// @notice Emitted when keeper confirms new validators are active
    /// @param newValidators Number of validators confirmed as active
    /// @param totalValidators New total active validator count
    event NewValidatorsConfirmed(uint256 newValidators, uint256 totalValidators);
    /// @notice Emitted when keeper confirms validators have exited
    /// @param validatorsExited Number of validators confirmed as exited
    /// @param totalValidators New total active validator count
    event ExitValidatorsConfirmed(uint256 validatorsExited, uint256 totalValidators);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Throws if called by any account other than the keeper.
     */
    modifier onlyKeeper() {
        require(msg.sender == keeper, Unauthorized());
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Harvests accumulated yield and transfers to dragon router
     * @dev Permissionless but yield-limited. Safe's ETH balance must be > 0 and < maxYield
     *
     *      FLOW:
     *      1. Query Safe's ETH balance (accumulated yield)
     *      2. Validate yield > 0 and < maxYield
     *      3. Transfer yield to dragonRouter via Safe.exec
     *      4. Update lastHarvested timestamp and totalYield
     *      5. Emit events for tracking
     *
     *      REVERT CONDITIONS:
     *      - Yield == 0 (nothing to harvest)
     *      - Yield >= maxYield (exceeds safety limit)
     *      - Transfer to dragonRouter fails
     *
     * @custom:security Permissionless but protected by maxYield limit
     */
    function harvest() external {
        uint256 yield = owner().balance;
        require(yield != 0 && yield < maxYield, OctantRewardsSafe__YieldNotInRange(yield, maxYield));

        uint256 lastHarvestTime = lastHarvested;
        lastHarvested = block.timestamp;
        totalYield += yield;
        // False positive: only events emitted after the call
        //slither-disable-next-line reentrancy-no-eth
        bool success = exec(dragonRouter, yield, "", Enum.Operation.Call);
        require(success, OctantRewardsSafe__TransferFailed(yield));
        emit Transfer(owner(), dragonRouter, yield);
        emit Report(yield, totalValidators * 32 ether, block.timestamp - lastHarvestTime);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ONLY OWNER FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Requests adding new validators (step 1 of 2)
     * @dev Owner-only. Keeper must confirm via confirmNewValidators()
     * @param amount Number of validators to add (must be > 0)
     */
    function requestNewValidators(uint256 amount) external onlyOwner {
        require(amount != 0, OctantRewardsSafe__InvalidNumberOfValidators(amount));
        newValidators += amount;
        emit RequestNewValidators(amount, newValidators);
    }

    /**
     * @notice Requests exiting validators (step 1 of 2)
     * @dev Owner-only. Keeper must confirm via confirmExitValidators()
     *      Principal (32 ETH each) returned to treasury after confirmation
     * @param amount Number of validators to exit (must be > 0)
     */
    function requestExitValidators(uint256 amount) external onlyOwner {
        require(amount != 0, OctantRewardsSafe__InvalidNumberOfValidators(amount));
        exitedValidators += amount;
        emit RequestExitValidators(amount, exitedValidators);
    }

    /**
     * @notice Updates treasury address
     * @dev Owner-only. Treasury receives principal on validator exits
     * @param _treasury New treasury address (cannot be zero)
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), OctantRewardsSafe__InvalidAddress(_treasury));
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    /**
     * @notice Updates dragon router address
     * @dev Owner-only. Dragon router receives harvested yield
     * @param _dragonRouter New dragon router address (cannot be zero)
     */
    function setDragonRouter(address _dragonRouter) external onlyOwner {
        require(_dragonRouter != address(0), OctantRewardsSafe__InvalidAddress(_dragonRouter));
        emit DragonRouterUpdated(dragonRouter, _dragonRouter);
        dragonRouter = _dragonRouter;
    }

    /**
     * @notice Updates maximum harvestable yield per harvest() call
     * @dev Owner-only. Must be > 0 and < 32 ETH
     * @param _maxYield New maximum yield in wei (0 < _maxYield < 32e18)
     */
    function setMaxYield(uint256 _maxYield) external onlyOwner {
        require(_maxYield > 0 && _maxYield < 32 ether, OctantRewardsSafe__InvalidMaxYield(_maxYield));
        emit MaxYieldUpdated(maxYield, _maxYield);
        maxYield = _maxYield;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ONLY KEEPER FUNCTIONS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Confirms new validators are active (step 2 of 2)
     * @dev Keeper-only. Increments totalValidators and clears newValidators
     */
    function confirmNewValidators() external onlyKeeper {
        require(newValidators != 0, OctantRewardsSafe__InvalidNumberOfValidators(newValidators));
        totalValidators += newValidators;
        emit NewValidatorsConfirmed(newValidators, totalValidators);
        newValidators = 0;
    }

    /**
     * @notice Confirms validators exited and returns principal to treasury (step 2 of 2)
     * @dev Keeper-only. Transfers 32 ETH per validator to treasury and updates totalValidators
     */
    function confirmExitValidators() external onlyKeeper {
        uint256 validatorsExited = exitedValidators;
        require(validatorsExited != 0, OctantRewardsSafe__InvalidNumberOfValidators(validatorsExited));

        totalValidators -= validatorsExited;
        exitedValidators = 0;
        bool success = exec(treasury, validatorsExited * 32 ether, "", Enum.Operation.Call);
        require(success, OctantRewardsSafe__TransferFailed(validatorsExited * 32 ether));
        emit Transfer(owner(), treasury, validatorsExited * 32 ether);
        emit ExitValidatorsConfirmed(validatorsExited, totalValidators);
    }

    /**
     * @notice Initializes the OctantRewardsSafe module
     * @dev Called once during proxy deployment. Sets initial validator count and addresses
     * @param initializeParams ABI-encoded: (owner, (keeper, treasury, dragonRouter, totalValidators, maxYield))
     */
    function setUp(bytes memory initializeParams) public override initializer {
        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));

        (address _keeper, address _treasury, address _dragonRouter, uint256 _totalValidators, uint256 _maxYield) = abi
            .decode(data, (address, address, address, uint256, uint256));

        __Ownable_init(msg.sender);

        keeper = _keeper;
        treasury = _treasury;
        dragonRouter = _dragonRouter;
        totalValidators = _totalValidators;
        maxYield = _maxYield;
        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);
    }
}
