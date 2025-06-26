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

contract OctantRewardsSafe is Module {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev address of the user operating the validators
    address public keeper;
    /// @dev address of the treasury used to hold principal amount.
    address public treasury;
    /// @dev address of the contract to route yield to.
    address public dragonRouter;
    /// @dev total number of validators currently active.
    uint256 public totalValidators;
    /// @dev amount of new validators to be added.
    uint256 public newValidators;
    /// @dev amount of validators currently being exited.
    uint256 public exitedValidators;
    /// @dev total amount of yield harvested
    uint256 public totalYield;
    /// @dev latest timestamp of harvest()
    uint256 public lastHarvested;
    /// @dev Maximum yield that can be harvested
    uint256 public maxYield;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when `amount` of ETH is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @dev Emitted when `treasury` is updated from `oldAddress` to `newAddress` by the owner.
    event TreasuryUpdated(address oldAddress, address newAddress);
    /// @dev Emitted when `dragonRouter` is updated from `oldAddress` to `newAddress` by the owner.
    event DragonRouterUpdated(address oldAddress, address newAddress);
    /// @dev Emitted when yield is harvested
    event Report(uint256 yield, uint256 totalDepositedAssets, uint256 timePeriod);
    /// @dev Emitted when owner requests `amount` of validators to be exited.
    event RequestExitValidators(uint256 amount, uint256 totalExitedValidators);
    /// @dev Emitted when owner requests `amount` of validators to be added.
    event RequestNewValidators(uint256 amount, uint256 totalNewValidators);
    /// @dev Emitted when `maxYield` is updated from `oldMaxYield` to `newMaxYield` by the owner.
    event MaxYieldUpdated(uint256 oldMaxYield, uint256 newMaxYield);
    /// @dev Emitted when keeper confirm new `amount` of validators are added.
    event NewValidatorsConfirmed(uint256 newValidators, uint256 totalValidators);
    /// @dev Emitted when keeper confirm `amount` of validators are exited.
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

    /// @dev transfers the yield to the dragon router from safe and principal to treasury.
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

    /// @dev Request to increase the number of total validators.
    ///      Can be only called by the owner of the module.
    /// @param amount Amount of validators to be added.
    function requestNewValidators(uint256 amount) external onlyOwner {
        require(amount != 0, OctantRewardsSafe__InvalidNumberOfValidators(amount));
        newValidators += amount;
        emit RequestNewValidators(amount, newValidators);
    }

    /// @dev Request the number of validators to be exited.
    ///      Can be only called by the owner of the module.
    /// @param amount Amount of validators to be exited.
    function requestExitValidators(uint256 amount) external onlyOwner {
        require(amount != 0, OctantRewardsSafe__InvalidNumberOfValidators(amount));
        exitedValidators += amount;
        emit RequestExitValidators(amount, exitedValidators);
    }

    /// @dev sets treasury address. Can be only called by the owner of the module.
    /// @param _treasury address of the new treasury to set.
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), OctantRewardsSafe__InvalidAddress(_treasury));
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    /// @dev sets dragon router address. Can be only called by the owner of the module.
    /// @param _dragonRouter address of the new dragon router to set.
    function setDragonRouter(address _dragonRouter) external onlyOwner {
        require(_dragonRouter != address(0), OctantRewardsSafe__InvalidAddress(_dragonRouter));
        emit DragonRouterUpdated(dragonRouter, _dragonRouter);
        dragonRouter = _dragonRouter;
    }

    /// @dev sets max yield that can be harvested.
    /// @param _maxYield maximum yield that can be harvested
    function setMaxYield(uint256 _maxYield) external onlyOwner {
        require(_maxYield > 0 && _maxYield < 32 ether, OctantRewardsSafe__InvalidMaxYield(_maxYield));
        emit MaxYieldUpdated(maxYield, _maxYield);
        maxYield = _maxYield;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ONLY KEEPER FUNCTIONS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Increases the number of total validators.
    ///      Can be only called by the keeper.
    function confirmNewValidators() external onlyKeeper {
        require(newValidators != 0, OctantRewardsSafe__InvalidNumberOfValidators(newValidators));
        totalValidators += newValidators;
        emit NewValidatorsConfirmed(newValidators, totalValidators);
        newValidators = 0;
    }

    /// @dev Confirm's validators are exited and withdraws principal to treasury.
    ///      Can be only called by the owner of the module.
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

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @dev owner of this module will the safe multisig that calls setUp function
    /// @param initializeParams Parameters of initialization encoded
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
