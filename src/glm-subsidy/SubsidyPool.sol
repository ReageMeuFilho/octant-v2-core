// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/ISubsidyPool.sol";
import "../interfaces/IUserDeposits.sol";
import "../interfaces/IPeriodTracker.sol";
import "../interfaces/ITimeTracker.sol";

contract SubsidyPool is ISubsidyPool {

    error SubsidyPool__ZeroAddress();
    error SubsidyPool__DepositZeroAmount();
    error SubsidyPool__TokenTransferFailed();
    error SubsidyPool__NotEligibleForSubsidy();
    error SubsidyPool__SubsidyClaimClosed();

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
    IUserDeposits public userDeposits;
    ITimeTracker public timeTracker;

    mapping(uint256 => uint256) public subsidies;
    mapping(uint256 => mapping(address => uint256)) public claimed;


    constructor(address _tokenAddress, address _userDeposits, address _timeTracker) {
        if (_tokenAddress == address(0) || _userDeposits == address(0)) revert SubsidyPool__ZeroAddress();
        token = ERC20(_tokenAddress);
        userDeposits = IUserDeposits(_userDeposits);
        timeTracker = ITimeTracker(_timeTracker);
    }

    function deposit(uint256 _amount) external { //TODO Only PpfGlmTransformer
        if (_amount == 0) revert SubsidyPool__DepositZeroAmount();

        uint256 period = timeTracker.getCurrentPeriod();
        uint256 oldDeposit = subsidies[period];
        subsidies[period] = oldDeposit + _amount;
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert SubsidyPool__TokenTransferFailed();
        }

        emit Deposited(oldDeposit, _amount, block.timestamp, msg.sender);
    }

    function getUserEntitlement(address _user, uint256 _period, bytes memory _data) external view returns (uint256 _amount) {
        uint256 individualShare = userDeposits.getIndividualShare(_user, _period, _data);
        uint256 totalSubsidy = subsidies(_period);

        return totalSubsidy * individualShare;
    }

    //TODO only our contract
    function claimUserEntitlement(address _user, uint256 _period, bytes memory _data) external {
        uint256 previousPeriod = _period - 1;
        uint256 decisionWindowEnd = timeTracker.getDecisionWindowEnd(_period);
        uint256 previousDecisionWindowEnd = timeTracker.getDecisionWindowEnd(previousPeriod);

        if (block.timestamp < decisionWindowEnd) revert SubsidyPool__SubsidyClaimClosed();

        uint256 alreadyClaimed = claimed[previousPeriod][_user];
        uint256 userEntitlement = getUserEntitlement(_user, previousPeriod, _data);

        uint256 tokensUnlockedPrevious = userDeposits.getTokensLocked(_user, previousPeriod, previousDecisionWindowEnd, type(uint256).max, _data);
        uint256 tokensUnlockedCurrent = userDeposits.getTokensLocked(_user, _period, 0, decisionWindowEnd, _data);

        uint256 tokensLocked = userDeposits.getTokensLocked(_user, _period, 0, type(uint256).max, _data);

        if (tokensLocked == 0 ||
            userEntitlement == 0 ||
            tokensUnlockedPrevious > 0 ||
            tokensUnlockedCurrent > 0 ||
            alreadyClaimed == userEntitlement)
        {
            revert SubsidyPool__NotEligibleForSubsidy();
        }

        uint256 amountToTransfer;
        if (tokensLocked >= userEntitlement) {
            amountToTransfer = userEntitlement;
        } else {
            amountToTransfer = tokensLocked - alreadyClaimed;
        }
        claimed[previousPeriod][_user] = alreadyClaimed + amountToTransfer;

        bool success = token.transfer(_user, amount);
        if (!success) {
            revert SubsidyPool__TokenTransferFailed();
        }

        emit Deposited(amount, block.timestamp, _user);
    }
}
