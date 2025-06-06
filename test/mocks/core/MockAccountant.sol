// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IAccountant } from "src/interfaces/IAccountant.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";

// based off https://github.com/yearn/yearn-vaults-v3/blob/master/tests/unit/vault/test_strategy_accounting.py
contract MockAccountant is IAccountant {
    // Constants matching the original Vyper contract
    uint256 constant MAX_BPS = 10_000;
    uint256 constant MAX_SHARE = 7_500; // 75% max fee cap
    uint256 constant SECS_PER_YEAR = 365 days;

    // Storage variables
    address public feeManager;
    address public futureFeeManager;
    address public asset;

    // Events
    event CommitFeeManager(address indexed feeManager);
    event ApplyFeeManager(address indexed feeManager);
    event UpdatePerformanceFee(uint256 performanceFee);
    event UpdateManagementFee(uint256 managementFee);
    event UpdateRefundRatio(uint256 refundRatio);
    event DistributeRewards(uint256 rewards);

    // Fee configuration per strategy
    struct Fee {
        uint256 managementFee;
        uint256 performanceFee;
    }

    mapping(address => Fee) public fees;
    mapping(address => uint256) public refundRatios;

    constructor(address _asset) {
        asset = _asset;
        feeManager = msg.sender;
    }

    function report(
        address strategy,
        uint256 gain,
        uint256 loss
    ) external override returns (uint256 totalFees, uint256 totalRefunds) {
        // Get strategy params from the vault
        IMultistrategyVault.StrategyParams memory strategyParams = IMultistrategyVault(msg.sender).strategies(strategy);
        Fee memory fee = fees[strategy];
        uint256 duration = block.timestamp - strategyParams.lastReport;

        // Calculate management fee based on time elapsed - matches Vyper implementation
        totalFees = (strategyParams.currentDebt * duration * fee.managementFee) / MAX_BPS / SECS_PER_YEAR;

        if (gain > 0) {
            // Add performance fee if there's a gain
            totalFees += (gain * fee.performanceFee) / MAX_BPS;

            // Cap fees at 75% of gain
            uint256 maximumFee = (gain * MAX_SHARE) / MAX_BPS;
            if (totalFees > maximumFee) {
                return (maximumFee, 0);
            }
        } else {
            // Calculate refunds if there's a loss - ONLY FOR LOSSES, not gains
            uint256 refundRatio = refundRatios[strategy];
            totalRefunds = (loss * refundRatio) / MAX_BPS;

            if (totalRefunds > 0) {
                // Approve the vault to pull the refund
                IERC20(asset).approve(msg.sender, totalRefunds);
            }
        }

        return (totalFees, totalRefunds);
    }

    // Helper function to set fees for testing
    function setFees(address strategy, uint256 managementFee, uint256 performanceFee, uint256 refundRatio) external {
        fees[strategy] = Fee({ managementFee: managementFee, performanceFee: performanceFee });
        refundRatios[strategy] = refundRatio;
    }

    // Additional functions from the Vyper contract
    function distribute(IERC20 vault) external {
        require(msg.sender == feeManager, "not fee manager");
        uint256 rewards = vault.balanceOf(address(this));
        vault.transfer(msg.sender, rewards);
        emit DistributeRewards(rewards);
    }

    function setPerformanceFee(address strategy, uint256 performanceFee) external {
        require(msg.sender == feeManager, "not fee manager");
        require(performanceFee <= performanceFeeThreshold(), "exceeds performance fee threshold");
        fees[strategy].performanceFee = performanceFee;
        emit UpdatePerformanceFee(performanceFee);
    }

    function setManagementFee(address strategy, uint256 managementFee) external {
        require(msg.sender == feeManager, "not fee manager");
        require(managementFee <= managementFeeThreshold(), "exceeds management fee threshold");
        fees[strategy].managementFee = managementFee;
        emit UpdateManagementFee(managementFee);
    }

    function setRefundRatio(address strategy, uint256 refundRatio) external {
        require(msg.sender == feeManager, "not fee manager");
        refundRatios[strategy] = refundRatio;
        emit UpdateRefundRatio(refundRatio);
    }

    function commitFeeManager(address _futureFeeManager) external {
        require(msg.sender == feeManager, "not fee manager");
        futureFeeManager = _futureFeeManager;
        emit CommitFeeManager(_futureFeeManager);
    }

    function applyFeeManager() external {
        require(msg.sender == feeManager, "not fee manager");
        require(futureFeeManager != address(0), "future fee manager != zero address");
        feeManager = futureFeeManager;
        emit ApplyFeeManager(feeManager);
    }

    function performanceFeeThreshold() public pure returns (uint256) {
        return MAX_BPS / 2;
    }

    function managementFeeThreshold() public pure returns (uint256) {
        return MAX_BPS;
    }
}
