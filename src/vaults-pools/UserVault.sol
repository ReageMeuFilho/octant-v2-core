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

import {ERC20} from "@solady/tokens/ERC20.sol";
import {TokenAccountingVault} from "./TokenAccountingVault.sol";

// TODO: move to the interfaces
interface IUserBudgetCalculator {
    function calculateBudget(uint256 currentUserRewards, uint256 userMaturedDeposit, uint256 totalMaturedDeposit) external view returns (uint256 userBudget);
}

contract UserBudgetV2Calculator is IUserBudgetCalculator {
    function calculateBudget(uint256 currentUserRewards, uint256 userMaturedDeposit, uint256 totalMaturedDeposit) public view returns (uint256 userBudget) {
        return 0; // TODO: implement logic as on the server
    }
}

struct UserAction {
    uint256 timestamp;
    uint256 balanceSnapshot;
    uint256 userMaturedDeposit; // not needed?
    uint256 totalMaturedDeposit; // not needed?
}

//conform to interfaces IERC4626 & IERC7535

// User Vault is a vault for individual rewards
// ETH is deposited from the Octant MSIG or Octant Router
// Depending on the amount of ETH, the balance of the share is attributed to the users
// But it's minted and redeemed according to certain rules and connected to the AccountingTokenVault
contract UserVault is ERC20, UserBudgetV2Calculator {

    // TODO: override transfer functions
    
    error UserVault__AssetsCantBeZero();
    error UserVault__SharesCantBeZero();
    error UserVault__ReceiverIsZero();
    error UserVault__SharesAmountMustMatchDeposit();
    error UserVault__CantMintMoreThanUserBudget();
    error UserVault__CantRedeemMoreThanUserBudget();

    address private constant ETH_ASSET_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 totalBalanceOvertime;
    string public sharesTokenName;
    string public sharesTokenSymbol;

    TokenAccountingVault tokenAccountingVault;
    mapping(address user => uint256 withdrawn) public userWithdrawals;
    mapping(address user => UserAction userAction) public lastActions;

    event Deposited(address sender, address owner, uint256 assets, uint256 shares);
    event Withdrawn(address sender, address receiver, address owner, uint256 assets, uint256 shares);

    constructor(address accountingVault, string memory tokenName, string memory symbolName) {
        tokenAccountingVault = TokenAccountingVault(accountingVault);
        sharesTokenName = tokenName;
        sharesTokenSymbol = symbolName;
    }

    /**
     * @notice  Returns the current accrued rewards for the user in the vault without minting them
     * @dev     Maybe tokenAccountingVault can be just ERC20 in this contract
     * @param   owner  .
     * @return  result  .
     */
    function balanceOf(address owner) public view override returns (uint256 result) {
        uint256 virtualShares = _virtualBalance(owner);
        uint256 actualShares = super.balanceOf(owner);
        result = actualShares + virtualShares;
    }

    function name() public view override returns (string memory) {
        return sharesTokenName;
    }

    function symbol() public view override returns (string memory) {
        return sharesTokenSymbol;
    }

    function asset() external returns (address) {
        return address(ETH_ASSET_ADDRESS);
    }

    function totalAssets() external view returns (uint256) {
        return address(this).balance; // @audit create a special var for this
    }

    // function convertToShares(uint256 assets) public view returns (uint256 shares) {
    //     // should not depend on the specific user
    // }
    
    // function convertToAssets(uint256 shares) public view returns (uint256 assets) {
    //     // should not depend on the specific user
    // }

    function deposit() external payable {
        deposit(msg.value, ETH_ASSET_ADDRESS);
    }

    function deposit(uint256 assets, address to) public virtual payable returns (uint256) {
        assets; // Ignore assets input variable
        to;     // Ignore to variable
        if (msg.value == 0) revert UserVault__AssetsCantBeZero();

        totalBalanceOvertime += msg.value;
        // Mint the amount of shares to this address equal to the amount of ETH deposited
        // mint(address(this), msg.value);

        emit Deposited(msg.sender, ETH_ASSET_ADDRESS, msg.value, msg.value);
        return msg.value;
    }

    function mint(uint256 shares, address to) public virtual payable returns (uint256) {
        deposit(shares, to);
    }

    function redeem(uint256 shares, address to, address owner) external returns (uint256 assets) {
        if (shares == 0) revert UserVault__SharesCantBeZero();
        if (to == address(0)) revert UserVault__ReceiverIsZero();
        if (owner == address(0)) {
            owner = msg.sender;
        }

        _reconcileShares(shares, to, owner);
        assets = shares; // @audit optimize
        _withdraw(assets, shares, to, owner);

        emit Withdrawn(msg.sender, to, owner, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address to, address owner) external returns (uint256 shares) {
        if (assets == 0) revert UserVault__AssetsCantBeZero();
        if (to == address(0)) revert UserVault__ReceiverIsZero();
        if (owner == address(0)) {
            owner = msg.sender;
        }

        _reconcileShares(shares, to, owner);
        shares = assets; // @audit optimize
        _withdraw(assets, shares, to, owner);

    emit Withdrawn(msg.sender, to, owner, assets, assets);
        return assets;
    }

    function _reconcileShares(uint256 shares, address to, address owner) internal {
        uint256 virtualUserShares = _virtualBalance(owner); // 50
        uint256 actualUserShares = _actualBalance(owner); // 50
        uint256 totalUserBudget = virtualUserShares + actualUserShares; // 100
        if (shares > totalUserBudget) revert UserVault__CantRedeemMoreThanUserBudget();
        if (shares > actualUserShares) {
            uint256 toBurn = totalUserBudget - shares; // ex: shares = 70
            _burn(owner, toBurn);
        }
        if (shares < virtualUserShares) { // @audit else if ?
            uint256 toMint = virtualUserShares - shares; // ex: shares = 30
            _mint(to, toMint);
        }
    }

    function _withdraw(uint256 assets, uint256 shares, address to, address owner) internal {
        userWithdrawals[to] += shares;
        lastActions[owner] = UserAction({
            timestamp: block.timestamp,
            balanceSnapshot: address(this).balance,
            userMaturedDeposit: 0,
            totalMaturedDeposit: 0
            }); // @audit fix it later
        to.call{value: assets};
    }

    function _actualBalance(address owner) internal view returns (uint256) {
        return super.balanceOf(owner);
    }

    function _virtualBalance(address owner) internal view returns (uint256) {
        UserAction memory lastUserAction = lastActions[owner];
        uint256 userAvailableBalance = 0;
        if (lastUserAction.timestamp != 0) {
            userAvailableBalance = totalBalanceOvertime - lastUserAction.balanceSnapshot;
        } else {
            userAvailableBalance = totalBalanceOvertime;
        }
        uint256 userMaturedDeposit = tokenAccountingVault.balanceOf(owner);
        uint256 totalMaturedDeposit = tokenAccountingVault.totalSupply();
        return calculateBudget(userAvailableBalance, userMaturedDeposit, totalMaturedDeposit);
    }
}