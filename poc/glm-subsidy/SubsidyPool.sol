// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "solady/src/tokens/ERC20.sol";
import "../interfaces/ISubsidyPool.sol";
import "../interfaces/IUserDeposits.sol";
import "../interfaces/ITimeTracker.sol";

contract SubsidyPool is ISubsidyPool {
    error SubsidyPool__ZeroAddress();
    error SubsidyPool__DepositZeroAmount();
    error SubsidyPool__TokenTransferFailed();
    error SubsidyPool__NotEligibleForSubsidy();
    error SubsidyPool__SubsidyClaimNotOpenedYet();

    event Deposited(uint256 depositBefore, uint256 amount, uint256 when, address depositor);

    event Claimed(uint256 amount, uint256 when, address user);

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

    function deposit(uint256 _amount) external {
        //TODO Only PpfGlmTransformer
        if (_amount == 0) revert SubsidyPool__DepositZeroAmount();

        (uint256 periodNumber, , ) = timeTracker.getCurrentAccumulationPeriod();
        uint256 oldDeposit = subsidies[periodNumber];
        subsidies[periodNumber] = oldDeposit + _amount;
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert SubsidyPool__TokenTransferFailed();
        }

        emit Deposited(oldDeposit, _amount, block.timestamp, msg.sender);
    }

    function getUserEntitlement(
        address _user,
        uint256 _period,
        bytes memory _data
    ) public view returns (uint256 _amount) {
        uint256 individualShare = userDeposits.getIndividualShare(_user, _period, _data);
        uint256 totalSubsidy = subsidies[_period];

        return totalSubsidy * individualShare;
    }

    //TODO only our contract
    function claimUserEntitlement(address _user, bytes memory _data) external {
        (, uint256 attributionPeriodStart, uint256 attributionPeriodEnd) = timeTracker.getSubsidyAttributionPeriod();
        (uint256 claimPeriod, uint256 claimPeriodStart, uint256 claimPeriodEnd) = timeTracker.getSubsidyClaimPeriod();

        if (block.timestamp < claimPeriodStart) revert SubsidyPool__SubsidyClaimNotOpenedYet();

        uint256 alreadyClaimed = claimed[claimPeriod][_user];
        uint256 userEntitlement = getUserEntitlement(_user, claimPeriod, _data);

        uint256 tokensUnlocked = userDeposits.getTokensUnlocked(
            _user,
            attributionPeriodStart,
            attributionPeriodEnd,
            _data
        );
        uint256 tokensLocked = userDeposits.getTokensLocked(_user, claimPeriodStart, claimPeriodEnd, _data);

        if (tokensLocked == 0 || userEntitlement == 0 || tokensUnlocked > 0 || alreadyClaimed >= userEntitlement) {
            revert SubsidyPool__NotEligibleForSubsidy();
        }

        uint256 amountToTransfer;
        if (tokensLocked >= userEntitlement) {
            amountToTransfer = userEntitlement;
        } else {
            amountToTransfer = tokensLocked - alreadyClaimed;
        }
        claimed[claimPeriod][_user] = alreadyClaimed + amountToTransfer;

        bool success = token.transfer(_user, amountToTransfer);
        if (!success) {
            revert SubsidyPool__TokenTransferFailed();
        }

        emit Claimed(amountToTransfer, block.timestamp, _user);
    }
}
