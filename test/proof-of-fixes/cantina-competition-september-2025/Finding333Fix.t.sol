// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { MorphoCompounderStrategy } from "src/strategies/yieldDonating/MorphoCompounderStrategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract MockCompounderVault is ERC20, IERC4626 {
    using SafeERC20 for IERC20;

    error DepositLimitExceeded();

    IERC20 public immutable assetToken;

    uint256 public override totalAssets;
    uint256 public reportedLimit;
    uint256 public actualLimit;

    constructor(address asset_) ERC20("MockCompounderVault", "mCV") {
        assetToken = IERC20(asset_);
    }

    function asset() public view override returns (address) {
        return address(assetToken);
    }

    function setLimits(uint256 reported, uint256 actual) external {
        reportedLimit = reported;
        actualLimit = actual;
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        if (assets > actualLimit) revert DepositLimitExceeded();

        assetToken.safeTransferFrom(msg.sender, address(this), assets);

        shares = assets;
        _mint(receiver, shares);
        totalAssets += assets;
        actualLimit -= Math.min(assets, actualLimit);
    }

    function mint(uint256 shares, address receiver) external override returns (uint256 assets) {
        assets = shares;
        if (assets > actualLimit) revert DepositLimitExceeded();

        assetToken.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        totalAssets += assets;
        actualLimit -= Math.min(assets, actualLimit);
    }

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {
        shares = assets;
        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        totalAssets -= assets;
        assetToken.safeTransfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {
        assets = shares;
        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        totalAssets -= assets;
        assetToken.safeTransfer(receiver, assets);
    }

    function convertToShares(uint256 assets) public pure override returns (uint256) {
        return assets;
    }

    function convertToAssets(uint256 shares) public pure override returns (uint256) {
        return shares;
    }

    function previewDeposit(uint256 assets) external pure override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) external pure override returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) external pure override returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) external pure override returns (uint256) {
        return convertToAssets(shares);
    }

    function maxDeposit(address) external view override returns (uint256) {
        return reportedLimit;
    }

    function maxMint(address) external view override returns (uint256) {
        return reportedLimit;
    }

    function maxWithdraw(address owner) external view override returns (uint256) {
        return balanceOf(owner);
    }

    function maxRedeem(address owner) external view override returns (uint256) {
        return balanceOf(owner);
    }
}

contract MorphoCompounderStrategyHarness is MorphoCompounderStrategy {
    constructor(
        address _compounderVault,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        MorphoCompounderStrategy(
            _compounderVault,
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {}

    function deployTest(uint256 amount) external {
        _deployFunds(amount);
    }

    function depositLimitBuffer() external view returns (uint256) {
        return maxDepositBuffer;
    }
}

contract Finding333Fix is Test {
    using SafeERC20 for IERC20;

    MockERC20 internal assetToken;
    MockCompounderVault internal compounder;
    YieldDonatingTokenizedStrategy internal implementation;
    MorphoCompounderStrategyHarness internal strategy;

    address internal management = address(1);
    address internal keeper = address(2);
    address internal emergencyAdmin = address(3);
    address internal donation = address(4);

    function setUp() public {
        assetToken = new MockERC20(6);
        compounder = new MockCompounderVault(address(assetToken));
        implementation = new YieldDonatingTokenizedStrategy();

        strategy = new MorphoCompounderStrategyHarness(
            address(compounder),
            address(assetToken),
            "Morpho Compounder Test",
            management,
            keeper,
            emergencyAdmin,
            donation,
            false,
            address(implementation)
        );
    }

    function testDeployFundsRespectsActualLimit() public {
        compounder.setLimits(100e6, 40e6);
        assetToken.mint(address(strategy), 60e6);

        strategy.deployTest(60e6);

        assertEq(compounder.totalAssets(), 40e6, "only actual limit should be deployed");
        assertEq(assetToken.balanceOf(address(strategy)), 20e6, "excess stays idle");
        assertEq(strategy.depositLimitBuffer(), 100e6, "buffer tracks failed capacity");
        assertEq(strategy.availableDepositLimit(address(0)), 0, "reported limit reduced to zero");
    }

    function testDeployFundsAfterLimitUpdateClearsBuffer() public {
        compounder.setLimits(100e6, 40e6);
        assetToken.mint(address(strategy), 60e6);
        strategy.deployTest(60e6);

        compounder.setLimits(200e6, 200e6);

        uint256 idleBefore = assetToken.balanceOf(address(strategy));
        strategy.deployTest(idleBefore);

        assertEq(assetToken.balanceOf(address(strategy)), 0, "idle funds should be deployed");
        assertEq(compounder.totalAssets(), 60e6, "all assets deposited once capacity returns");
        assertEq(strategy.depositLimitBuffer(), 0, "buffer reset after successful deposit");
        assertEq(strategy.availableDepositLimit(address(0)), 200e6, "limit reflects new reported capacity");
    }
}
