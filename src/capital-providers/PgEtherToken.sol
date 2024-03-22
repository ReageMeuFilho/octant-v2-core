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
import {IErrors} from "@diva/contracts/interfaces/IErrors.sol";

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

contract PgEthToken is ERC20, Ownable, ICapitalSourceProvider, IPgStaking, IErrors {
    /**
     * Errors
     */
    error PgEtherToken__NoEligibleRewards();
    error PgEtherToken__RequestInProgress();
    error PgEtherToken__PgAmountIsTheSame();

    DivaEtherToken public immutable divaERC20;
    IDivaWithdrawer public immutable divaWithdrawer;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          UUPS ADMIN                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    IOctantRouter public octantRouter;
    uint256 public totalPgShares;
    // mapping(uint256 withdrawalRequestId => uint256 estimatedTimeToWithdraw) withdrawalRequests;
    uint256 public currentWithdrawalRequestId;
    mapping(address user => uint256 shares) pgShares;

    constructor(address _divaERC20, IOctantRouter router, IDivaWithdrawer withdrawer) {
        divaERC20 = DivaEtherToken(payable(_divaERC20));
        octantRouter = router;
        divaWithdrawer = withdrawer;
        _initializeOwner(msg.sender);
    }

    function name() public pure override returns (string memory) {
        return "Wrapped PG Diva Ether Token";
    }

    function symbol() public pure override returns (string memory) {
        return "pgDivETH";
    }

    function deposit(uint256 pgAmount) external payable {
        depositFor(msg.sender, pgAmount);
    }

    function depositFor(address user, uint256 pgAmount) public payable {
        uint256 divEthDeposit = msg.value - pgAmount;
        divaERC20.depositFor{value: divEthDeposit}(user);
        mint(pgAmount);
    }
    
    function updatePgAmount(uint256 pgAmount) external {
        if (pgAmount == 0) revert PgEtherToken__PgAmountIsTheSame();
        uint256 currentPgAmount = pgShares[msg.sender];
        int256 pgAmountDiff = int256(pgAmount) - int256(currentPgAmount); // @audit use conversion below or just switch operands
        if (pgAmountDiff > 0) {
            mint(uint256(pgAmountDiff));
        } else {
            burn(uint256(pgAmountDiff));
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
        uint256 allRewards = divaERC20.totalShares() - divaERC20.totalEther(); // @audit make sure there is no overflow
        uint256 pgSharesPercentage = totalPgShares / divaERC20.totalShares(); // Get the percentage of PG shares in relation to all shares
        return allRewards * pgSharesPercentage;
    }

    function mint(uint256 amount) public {
        // @dev assumption DIVA is a compatible ERC20 that will revert on failure, no need to check return value
        uint256 shares = divaERC20.convertToShares(amount);

        divaERC20.transferSharesFrom(msg.sender, address(this), shares);

        _mint(msg.sender, shares);
        pgShares[msg.sender] += shares;

        totalPgShares += shares;
    }

    function burn(uint256 shares) public {
        if (shares == 0) revert ZeroAmount();

        _burn(msg.sender, shares);

        divaERC20.transferShares(msg.sender, shares);

        totalPgShares -= shares;
    }

    // leave original audit comment, instead of receive shoul i add a named function?
    // @audit we need a receive() fallback that wraps ETH into wdivETH
    function depositETH() public payable {
        if (msg.value == 0) revert ZeroAmount();

        uint256 depositedShares = divaERC20.deposit{value: msg.value}();

        _mint(msg.sender, depositedShares);
    }

    receive() external payable {
        depositETH();
    }
}
