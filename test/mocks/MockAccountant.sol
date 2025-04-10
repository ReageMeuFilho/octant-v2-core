// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IAccountant } from "../../src/interfaces/IAccountant.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "../../src/interfaces/IVault.sol";

// based off https://github.com/yearn/yearn-vaults-v3/blob/master/tests/unit/vault/test_strategy_accounting.py
contract MockAccountant is IAccountant {
    address public asset;
    address public feeManager;

    // Constants matching the original Vyper contract
    uint256 constant MAX_BPS = 10_000;
    uint256 constant MAX_SHARE = 7_500; // 75% max fee cap
    uint256 constant SECS_PER_YEAR = 31_556_952;

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

    function setFees(address strategy, uint256 managementFee, uint256 performanceFee, uint256 refundRatio) external {
        fees[strategy] = Fee({ managementFee: managementFee, performanceFee: performanceFee });
        refundRatios[strategy] = refundRatio;
    }

    function report(
        address strategy,
        uint256 gain,
        uint256 loss
    ) external override returns (uint256 totalFees, uint256 totalRefunds) {
        // Get strategy params from the vault
        IVault.StrategyParams memory strategyParams = IVault(msg.sender).strategies(strategy);
        Fee memory fee = fees[strategy];
        uint256 duration = block.timestamp - strategyParams.lastReport;

        // Calculate management fee based on time elapsed
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
            // Calculate refunds if there's a loss
            uint256 refundRatio = refundRatios[strategy];
            totalRefunds = (loss * refundRatio) / MAX_BPS;

            if (totalRefunds > 0) {
                // Approve the vault to pull the refund
                IERC20(asset).approve(msg.sender, totalRefunds);
            }
        }

        return (totalFees, totalRefunds);
    }
}
