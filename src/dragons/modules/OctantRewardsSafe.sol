// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Module } from "zodiac/core/Module.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract OctantRewardsSafe is Module {
    address public keeper;
    address public treasury;
    address public dragonRouter;
    uint256 public totalValidators;
    uint256 public exitedValidators; // stores the amount of validators currently being exited.

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event TreasuryUpdated(address oldAddress, address newAddress);
    event DragonRouterUpdated(address oldAddress, address newAddress);

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

    function harvest() public returns (bool success) {
        if (exitedValidators != 0) {
            success = exec(treasury, exitedValidators * 32 ether, "", Enum.Operation.Call);
            require(success, "Failed to transfer principal to treasury");
            emit Transfer(owner(), treasury, exitedValidators * 32 ether);
            exitedValidators = 0;
        }
        uint256 yield = owner().balance;
        if (yield != 0) {
            success = exec(dragonRouter, yield, "", Enum.Operation.Call);
            require(success, "Failed to transfer yield to Dragon Router");
            emit Transfer(owner(), dragonRouter, yield);
        }
    }

    function addNewValidators(uint256 amount) external onlyKeeper {
        totalValidators += amount;
    }

    function exitValidators(uint256 amount) external onlyKeeper {
        totalValidators -= amount;
        harvest();
        exitedValidators = amount;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid address");
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    function setDragonRouter(address _dragonRouter) external onlyOwner {
        require(_dragonRouter != address(0), "Invalid address");
        emit DragonRouterUpdated(dragonRouter, _dragonRouter);
        dragonRouter = _dragonRouter;
    }
}
