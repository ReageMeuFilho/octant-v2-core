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

import {ITimeTracker} from "../interfaces/ITimeTracker.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";

struct UserDeposit {
    uint256 timestamp;
    uint256 amount;
}

struct UserEffectiveDeposit {
    uint256 timestamp;
    uint256 maturityRate;
}

// TokenAccountingVault accepts GLM and mints non-tranferrable shares in form of OGLM
// OGLM represents the amount of shares in the vault and calculated based on the IR,
// which is in turn is based on maturity of the deposits
contract TokenAccountingVault is ERC20 {

    error TokenAccountingVault__AssetsCantBeZero();
    error TokenAccountingVault__SharesCantBeZero();
    error TokenAccountingVault__ReceiverIsZero();

    ERC20 public immutable tokenAsset;
    mapping(address user => UserDeposit deposit) userDeposits; // assets
    mapping(address user => UserEffectiveDeposit effectiveDeposit) userEffectiveDeposits;

    ITimeTracker timeTracker;
    
    string public sharesTokenName;
    string public sharesTokenSymbol;

    event Deposited(address sender, address owner, uint256 assets, uint256 shares);
    event Withdrawn(address sender, address receiver, address owner, uint256 assets, uint256 shares);

    constructor(ERC20 asset_, string memory sharesTokenName_, string memory sharesTokenSymbol_, address timeTracker_) {
        tokenAsset = asset_;
        sharesTokenName = sharesTokenName_;
        sharesTokenSymbol = sharesTokenSymbol_;
        timeTracker = ITimeTracker(timeTracker_);
    }

    function name() public view override returns (string memory) {
        return sharesTokenName;
    }

    function symbol() public view override returns (string memory) {
        return sharesTokenSymbol;
    }

    function asset() external returns (address) {
        return address(tokenAsset);
    }

    function balanceOf(address owner) public view override returns (uint256 result) {
        uint256 virtualShares = _virtualBalance(owner);
        uint256 actualShares = super.balanceOf(owner);
        result = actualShares + virtualShares;
    }

    function totalAssets() external view returns (uint256) {
        return tokenAsset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256 shares) {

    }
    
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {

    }

    function _actualBalance(address owner) internal returns (uint256) {
        return super.balanceOf(owner);
    }

    function _virtualBalance(address owner) internal view returns (uint256) {
        UserEffectiveDeposit memory userEfDeposit = userEffectiveDeposits[owner];
        // todo: Calculate current effective deposit that has not been minted based
        // on the current maturity rate
    }

    function deposit(uint256 assets, address to) public virtual returns (uint256) {
        if (assets == 0) revert TokenAccountingVault__AssetsCantBeZero();
        if (to == address(0)) revert TokenAccountingVault__ReceiverIsZero();

        uint256 newEfDeposit = balanceOf(msg.sender);
        _deposit(assets, newEfDeposit, to);

        emit Deposited(msg.sender, to, assets, newEfDeposit);
        return newEfDeposit;
    }

    function mint(uint256 shares, address to) public virtual returns (uint256) {
        if (shares == 0) revert TokenAccountingVault__SharesCantBeZero();
        if (to == address(0)) revert TokenAccountingVault__ReceiverIsZero();

        // TODO: reconcile and withdraw
        uint256 assets = shares;
        emit Deposited(msg.sender, to, assets, shares);
        return assets;
    }

    function redeem(uint256 shares, address to, address owner) external returns (uint256 assets) {
        if (shares == 0) revert TokenAccountingVault__SharesCantBeZero();
        if (to == address(0)) revert TokenAccountingVault__ReceiverIsZero();
        if (owner == address(0)) {
            owner = msg.sender;
        }

        // TODO: reconcile and withdraw
        emit Withdrawn(msg.sender, to, owner, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address to, address owner) external returns (uint256 shares) {
        if (shares == 0) revert TokenAccountingVault__SharesCantBeZero();
        if (to == address(0)) revert TokenAccountingVault__ReceiverIsZero();
        if (owner == address(0)) {
            owner = msg.sender;
        }

        shares = assets;
        _withdraw(assets, shares, to, owner);
        emit Withdrawn(msg.sender, to, owner, assets, shares);
        return shares;
    }

    function _deposit(uint256 assets, uint256 newEfDeposit, address to) internal {
        UserDeposit storage currentDeposit = userDeposits[to];
        UserEffectiveDeposit storage currentEfDeposit = userEffectiveDeposits[to];

        currentDeposit.amount += assets;
        currentDeposit.timestamp = block.timestamp;

        uint256 unvestedAssets = currentDeposit.amount - newEfDeposit;
        (uint256 periodNumber, uint256 start, uint256 end) = timeTracker.getCurrentAccumulationPeriod();
        uint256 maturityPeriod = end - start;
        uint256 newMaturityRate = unvestedAssets / maturityPeriod;

        currentEfDeposit.maturityRate = newMaturityRate;
        currentEfDeposit.timestamp = block.timestamp;

        tokenAsset.transferFrom(msg.sender, address(this), assets);
        _mint(to, newEfDeposit);
    }

    function _withdraw(uint256 assets, uint256 shares, address to, address owner) internal {
        _burn(owner, shares);
        userDeposits[owner].amount -= assets;
        tokenAsset.transferFrom(address(this), to, assets);
    }
}