// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/ISubsidyPool.sol";

contract SubsidyPool is ISubsidyPool {

    error SubsidyPool__TokenZeroAddress();
    error SubsidyPool__DepositZeroAmount();
    error SubsidyPool__TokenTransferFailed();
    error SubsidyPool__NotEligibleForSubsidy();
    error SubsidyPool__SubsidyAlreadyClaimed();

     event Deposited(
        uint256 depositBefore,
        uint256 amount,
        uint256 when,
        address depositor
    );

    event Claimed(
        uint256 amount,
        uint256 when,
        address user
    );

    ERC20 public immutable token;

    mapping(uint256 => uint256) public deposits;
    mapping(uint256 => mapping(address => bool)) public claimed;


    constructor(address _tokenAddress) {
        if (_tokenAddress == address(0)) revert SubsidyPool__TokenZeroAddress();
        token = ERC20(_tokenAddress);
    }

    function deposit(uint256 _amount) external { //TODO Only PpfGlmTransformer
        if (_amount == 0) revert SubsidyPool__DepositZeroAmount();

        uint256 subsidyPeriod = 1; //TODO interface to get subsidyPeriod
        uint256 oldDeposit = deposits[subsidyPeriod];
        deposits[subsidyPeriod] = oldDeposit + _amount;
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert SubsidyPool__TokenTransferFailed();
        }

        emit Deposited(oldDeposit, _amount, block.timestamp, msg.sender);
    }

    function getUserEntitlement(address _user, uint256 _period, bytes memory _data) external view returns (uint256 _amount) {
        uint256 individualShare = 1; //TODO interface to get individualShare
        uint256 totalSubsidy = deposits(subsidyPeriod);

        return totalSubsidy * individualShare;
    }

    function claimUserEntitlement(address _user, bytes memory _data) external { //TODO only user or our contract
        uint256 subsidyPeriod = 1; //TODO interface to get subsidyPeriod
        if (claimed[subsidyPeriod][_user]) revert SubsidyPool__SubsidyAlreadyClaimed();

        uint256 tokensLocked = 1; //TODO interface to get tokensLocked
        uint256 userEntitlement = getUserEntitlement(_user); //TODO shouldn't it be interface as well?

        if (tokensLocked == 0 || userEntitlement == 0) revert SubsidyPool__NotEligibleForSubsidy();

        uint256 amount;
        if (tokensLocked >= userEntitlement) {
            amount = userEntitlement;
        } else {
            amount = tokensLocked;
        }
        token.transfer(_user, amount);

        emit Deposited(amount, block.timestamp, _user);
    }
}
