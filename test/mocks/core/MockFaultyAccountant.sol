// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IAccountant } from "src/interfaces/IAccountant.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";

// based off https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/test/mocks/periphery/FaultyAccountant.vy
contract MockFaultyAccountant is IAccountant {
    address public asset;
    address public feeManager;

    // Constants matching the original Vyper contract
    uint256 constant MAX_BPS = 10_000;
    uint256 constant SECS_PER_YEAR = 365 days;

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
        IMultistrategyVault.StrategyParams memory strategyParams = IMultistrategyVault(msg.sender).strategies(strategy);
        Fee memory fee = fees[strategy];
        uint256 refundRatio = refundRatios[strategy];
        uint256 duration = block.timestamp - strategyParams.lastReport;

        // Calculate management fee based on time elapsed
        totalFees = (strategyParams.currentDebt * duration * fee.managementFee) / MAX_BPS / SECS_PER_YEAR;

        // Get asset balance for potential refunds
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));

        if (gain > 0) {
            // Add performance fee if there's a gain
            totalFees += (gain * fee.performanceFee) / MAX_BPS;

            // Calculate refunds in gain scenario
            if (refundRatio > 0) {
                totalRefunds = (gain * refundRatio) / MAX_BPS;
                if (totalRefunds > assetBalance) {
                    totalRefunds = assetBalance;
                }
            }
        } else if (loss > 0) {
            // Calculate refunds in loss scenario
            if (refundRatio > 0) {
                totalRefunds = (loss * refundRatio) / MAX_BPS;
                if (totalRefunds > assetBalance) {
                    totalRefunds = assetBalance;
                }
            }
        }

        // This is the fault - no approval for the vault
        // Regular accountant would call IERC20(asset).approve(msg.sender, totalRefunds)

        asset = asset; // prevent state mutability compiler warning

        return (totalFees, totalRefunds);
    }

    function distribute(address vault) external {
        require(msg.sender == feeManager, "not fee manager");
        uint256 rewards = IERC20(vault).balanceOf(address(this));
        IERC20(vault).transfer(msg.sender, rewards);
    }
}
