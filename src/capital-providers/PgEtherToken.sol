// SPDX-License-Identifier: GPL-3.0

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.23;

import {Ownable} from "@solady/auth/Ownable.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";

import {DivaEtherToken} from "@diva/contracts/DivaEtherToken.sol";

import {ICapitalSourceProvider} from "../interfaces/ICapitalSourceProvider.sol";
import {IPgStaking} from "../interfaces/IPgStaking.sol";
import {IOctantRouter} from "../interfaces/IOctantRouter.sol";

interface IDivaWithdrawer {
    // function requestRewardsWithdawal(address account) external returns (uint256 withdrawalRequestId, uint256 estimatedTimeToWithdraw);
    function requestWithdrawal(uint256 amount)
        external
        returns (uint256 withdrawalRequestId, uint256 estimatedTimeToWithdraw);
    function claim(uint256 withdrawalRequestId) external;
    function isRequestFulfilled(uint256 withdrawalRequestId) external returns (bool);
}

contract PgEtherToken is ERC20, Ownable, ICapitalSourceProvider, IPgStaking {
    /**
     * Errors
     */
    error PgEtherToken__ZeroAmount();
    error PgEtherToken__PgAssetsMustBeBelowDeposit();
    error PgEtherToken__NoEligibleRewards();
    error PgEtherToken__RequestInProgress();
    error PgEtherToken__PgAmountIsTheSame();

    DivaEtherToken public immutable divaToken;
    IDivaWithdrawer public immutable divaWithdrawer;
    IOctantRouter public octantRouter;

    uint256 public totalPgShares;
    // mapping(uint256 withdrawalRequestId => uint256 estimatedTimeToWithdraw) withdrawalRequests;
    uint256 public currentWithdrawalRequestId;

    constructor(address token, address withdrawer, address router) {
        divaToken = DivaEtherToken(payable(token));
        divaWithdrawer = IDivaWithdrawer(withdrawer);
        octantRouter = IOctantRouter(router);
        _initializeOwner(msg.sender);
    }

    function name() public pure override returns (string memory) {
        return "Wrapped PG Diva Ether Token";
    }

    function symbol() public pure override returns (string memory) {
        return "pgDivETH";
    }

    function deposit(uint256 pgAssets) public payable returns (uint256 shares, uint256 pgShares) {
        return depositFor(msg.sender, pgAssets);
    }

    function depositFor(address user, uint256 pgAssets) public payable returns (uint256 shares, uint256 pgShares) {
        if (pgAssets < msg.value) revert PgEtherToken__PgAssetsMustBeBelowDeposit();
        shares = divaToken.depositFor{value: msg.value}(user);
        pgShares = divaToken.convertToShares(pgAssets);
        mint(pgShares);
    }
    
    function updatePgShares(uint256 pgShares) external {
        if (pgShares == 0) revert PgEtherToken__ZeroAmount();
        uint256 currentPgShares = balanceOf(msg.sender);
        if (pgShares == currentPgShares) revert PgEtherToken__PgAmountIsTheSame();
        if (pgShares > currentPgShares) {
            mint(pgShares - currentPgShares);
        } else {
            burn(currentPgShares - pgShares);
        }
    }

    function isWithdrawalRequestRequired() external pure returns (bool) {
        return true;
    }

    function availableToWithdraw() external returns (bool) {
        return divaWithdrawer.isRequestFulfilled(currentWithdrawalRequestId);
    }

    function requestPgWithdrawal() external returns (uint256 estimatedTimeToWithdraw) {
        if (currentWithdrawalRequestId != 0) revert PgEtherToken__RequestInProgress();
        uint256 eligibleRewards = getEligibleRewards();
        if (eligibleRewards == 0) revert PgEtherToken__NoEligibleRewards();
        (uint256 withdrawalRequestId, uint256 requestTimeToWithdraw) = divaWithdrawer.requestWithdrawal(eligibleRewards);
        currentWithdrawalRequestId = withdrawalRequestId;
        // withdrawalRequests[withdrawalRequestId] = requestTimeToWithdraw;
        estimatedTimeToWithdraw = requestTimeToWithdraw;
    }

    function withdrawAccumulatedPgCapital() external returns (uint256 pgAmount) {
        divaWithdrawer.claim(currentWithdrawalRequestId);
        currentWithdrawalRequestId = 0;
        pgAmount = 0; // @audit-issue temp
        // Transfer to Octant here?
        // octantRouter.route{value: address(this).balance}(address[], uint256[]);
    }

    function getEligibleRewards() public view returns (uint256) {
        uint256 allRewards = divaToken.totalShares() - divaToken.totalEther(); // @audit make sure there is no overflow
        uint256 pgSharesPercentage = totalPgShares / divaToken.totalShares(); // Get the percentage of PG shares in relation to all shares
        return allRewards * pgSharesPercentage;
    }

    function mint(uint256 pgShares) public {
        if (pgShares == 0) revert PgEtherToken__ZeroAmount();
        totalPgShares += pgShares;

        _mint(msg.sender, pgShares);
        divaToken.transferSharesFrom(msg.sender, address(this), pgShares);
    }

    function burn(uint256 pgShares) public {
        if (pgShares == 0) revert PgEtherToken__ZeroAmount();
        totalPgShares -= pgShares;

        _burn(msg.sender, pgShares);
        divaToken.transferShares(msg.sender, pgShares);
    }

    receive() external payable {
        deposit(msg.value);
    }
}
