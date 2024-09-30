// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Module } from "zodiac/core/Module.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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
    /// @dev amount of validators currently being exited.
    uint256 public exitedValidators;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when `amount` of ETH is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @dev Emitted when `treasury` from `oldAddress` to `newAddress` by the owner.
    event TreasuryUpdated(address oldAddress, address newAddress);
    /// @dev Emitted when `dragonRouter` from `oldAddress` to `newAddress` by the owner.
    event DragonRouterUpdated(address oldAddress, address newAddress);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Throws if called by any account other than the keeper.
     */
    modifier onlyKeeper() {
        require(msg.sender == keeper, "Unauthorized");
        _;
    }

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @dev owner of this module will the safe multisig that calls setUp function
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public override initializer {
        (address _owner, , , address _keeper, address _treasury, address _dragonRouter, uint256 _totalValidators) = abi
            .decode(initializeParams, (address, bytes32, bytes32, address, address, address, uint256));

        __Ownable_init(msg.sender);

        keeper = _keeper;
        treasury = _treasury;
        dragonRouter = _dragonRouter;
        totalValidators = _totalValidators;
        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev transfers the yield to the dragon router from safe and principal to treasury.
    function harvest() public returns (bool success) {
        if (exitedValidators != 0) {
            uint256 validtorsExited = exitedValidators;
            exitedValidators = 0;
            success = exec(treasury, validtorsExited * 32 ether, "", Enum.Operation.Call);
            require(success, "Failed to transfer principal to Treasury");
            emit Transfer(owner(), treasury, validtorsExited * 32 ether);
        }
        uint256 yield = owner().balance;
        if (yield != 0) {
            success = exec(dragonRouter, yield, "", Enum.Operation.Call);
            require(success, "Failed to transfer yield to Dragon Router");
            emit Transfer(owner(), dragonRouter, yield);
        }
    }

    /// @dev increases the number of total validators.
    ///      Can be only called by the owner of the module.
    /// @param amount Amount of validators to be added.
    function addNewValidators(uint256 amount) external onlyKeeper {
        totalValidators += amount;
    }

    /// @dev Sets the number of validtors to be exited. This function should be called before exiting the validators.
    ///      Can be only called by the keeper.
    /// @param amount Amount of validators to be exited.
    function exitValidators(uint256 amount) external onlyKeeper {
        totalValidators -= amount;
        harvest();
        exitedValidators = amount;
    }

    /// @dev sets treasury address. Can be only called by the owner of the module.
    /// @param _treasury address of the new treasury to set.
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid address");
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    /// @dev sets dragon router address. Can be only called by the owner of the module.
    /// @param _dragonRouter address of the new dragon router to set.
    function setDragonRouter(address _dragonRouter) external onlyOwner {
        require(_dragonRouter != address(0), "Invalid address");
        emit DragonRouterUpdated(dragonRouter, _dragonRouter);
        dragonRouter = _dragonRouter;
    }
}
