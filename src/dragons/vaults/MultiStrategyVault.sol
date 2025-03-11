// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import { TokenizedStrategy } from "./TokenizedStrategy.sol";
import { IBaseStrategy } from "src/interfaces/IBaseStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC4626Payable } from "src/interfaces/IERC4626Payable.sol";

/**
 * @title MultiStrategyVault
 * @notice A single asset vault that allocates deposits across multiple underlying strategies
 * @dev This vault accepts a single asset type and distributes it among different strategies
 *      according to allocation percentages. All strategies must support the same underlying asset.
 */
contract MultiStrategyVault is TokenizedStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Strategy information
    struct StrategyInfo {
        address strategyAddress;
        uint256 allocation; // Basis points (10000 = 100%)
        uint256 lastReport;
        uint256 totalDeployed;
        bool active;
    }

    // Maximum number of strategies allowed to prevent out of gas errors during loops
    uint256 public constant MAX_STRATEGIES = 8;

    // Array of strategy addresses for iteration
    address[] public strategies;

    // This contract is lookup-heavy, therefore it makes sense to invest in a mapping to avoid O(MAX_STRATEGIES) complexity
    mapping(address => StrategyInfo) public strategyInfo;

    // Total allocation - should always sum to MAX_BPS
    uint256 public totalAllocBps;

    // Withdrawal queue ordering
    address[] public withdrawalQueue;

    // Events - room for improvement
    event StrategyAdded(address indexed strategy, uint256 allocation);
    event StrategyRemoved(address indexed strategy);
    event AllocationUpdated(address indexed strategy, uint256 oldAllocation, uint256 newAllocation);
    event WithdrawalQueueUpdated(address[] queue);
    event StrategyReported(address indexed strategy, uint256 profit, uint256 loss);

    // Errors - room for improvement
    error InvalidAllocation();
    error TooManyStrategies();
    error StrategyNotFound();
    error StrategyAlreadyAdded();
    error IncompleteAllocation();
    error WithdrawalFailed();
    error InvalidStrategy();
    error Unauthorized();
    error AssetMismatch(address expected, address actual);

    /**
     * @dev Initialize the multi-strategy vault.
     */
    function initialize(
        address _asset,
        string memory _name,
        address _operator,
        address _management,
        address _keeper,
        address _dragonRouter,
        address _regenGovernance
    ) external override(TokenizedStrategy) {
        super.__TokenizedStrategy_init(_asset, _name, _operator, _management, _keeper, _dragonRouter, _regenGovernance);
    }

    /**
     * @notice Add a new strategy to the vault
     * @param _strategy Address of the strategy to add
     * @param _allocation Allocation in basis points (10000 = 100%)
     */
    function addStrategy(address _strategy, uint256 _allocation) external onlyManagement {
        if (strategies.length >= MAX_STRATEGIES) revert TooManyStrategies();

        if (strategyInfo[_strategy].strategyAddress != address(0)) revert StrategyAlreadyAdded();

        if (_allocation == 0 || _allocation + totalAllocBps > MAX_BPS) revert InvalidAllocation();

        // Verify strategy accepts our asset
        address stratAsset = IERC4626Payable(_strategy).asset();
        if (stratAsset != address(super._strategyStorage().asset))
            revert AssetMismatch(address(super._strategyStorage().asset), stratAsset);

        // Add strategy
        strategies.push(_strategy);
        strategyInfo[_strategy] = StrategyInfo({
            strategyAddress: _strategy,
            allocation: _allocation,
            lastReport: block.timestamp,
            totalDeployed: 0,
            active: true
        });

        // Update total allocation
        totalAllocBps += _allocation;

        // Update withdrawal queue (add to the end)
        withdrawalQueue.push(_strategy);

        emit StrategyAdded(_strategy, _allocation);
        emit WithdrawalQueueUpdated(withdrawalQueue);
    }

    /**
     * @notice Remove a strategy from the vault
     * @param _strategy Address of the strategy to remove
     */
    function removeStrategy(address _strategy) external onlyManagement {
        StrategyInfo storage strategy = strategyInfo[_strategy];

        if (strategy.strategyAddress == address(0)) revert StrategyNotFound();

        _withdrawFromStrategy(_strategy, strategy.totalDeployed);
        totalAllocBps -= strategy.allocation;

        // Remove from strategies array
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == _strategy) {
                strategies[i] = strategies[strategies.length - 1];
                strategies.pop();
                break;
            }
        }

        // Remove from withdrawal queue
        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            if (withdrawalQueue[i] == _strategy) {
                withdrawalQueue[i] = withdrawalQueue[withdrawalQueue.length - 1];
                withdrawalQueue.pop();
                break;
            }
        }

        delete strategyInfo[_strategy];

        emit StrategyRemoved(_strategy);
        emit WithdrawalQueueUpdated(withdrawalQueue);
    }

    /**
     * @notice Update allocation for a strategy
     * @param _strategy Address of the strategy
     * @param _allocation New allocation in basis points
     */
    function updateAllocation(address _strategy, uint256 _allocation) external onlyManagement {
        StrategyInfo storage strategy = strategyInfo[_strategy];

        if (strategy.strategyAddress == address(0)) revert StrategyNotFound();

        uint256 newTotalAlloc = totalAllocBps - strategy.allocation + _allocation;

        if (_allocation == 0 || newTotalAlloc > MAX_BPS) revert InvalidAllocation();

        uint256 oldAllocation = strategy.allocation;
        strategy.allocation = _allocation;
        totalAllocBps = newTotalAlloc;

        emit AllocationUpdated(_strategy, oldAllocation, _allocation);
    }

    /**
     * @notice Update the withdrawal queue ordering
     * @dev This function is used to change the order of strategies that are used for withdrawing funds.
     *      Initial queue is built when strategies are added, in FIFO order.
     *      Room for improvement.
     * @param _withdrawalQueue New withdrawal queue
     */
    function setWithdrawalQueue(address[] calldata _withdrawalQueue) external onlyManagement {
        // Verify all strategies in the queue exist
        for (uint256 i = 0; i < _withdrawalQueue.length; i++) {
            if (strategyInfo[_withdrawalQueue[i]].strategyAddress == address(0)) revert StrategyNotFound();
        }

        // Clear current queue
        delete withdrawalQueue;

        // Set new queue
        for (uint256 i = 0; i < _withdrawalQueue.length; i++) {
            withdrawalQueue.push(_withdrawalQueue[i]);
        }

        emit WithdrawalQueueUpdated(withdrawalQueue);
    }

    /**
     * @notice Deploy funds to strategies according to allocations
     * @dev Implements IBaseStrategy.deployFunds
     * @param amount Amount to deploy
     */
    function deployFunds(uint256 amount) external {
        // Only the vault itself can call this during deposit
        if (msg.sender != address(this)) revert Unauthorized();

        if (amount == 0) return;

        IERC20 asset = super._strategyStorage().asset;
        uint256 toAllocate = amount;

        // Deploy to each strategy according to allocation
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyInfo storage stratInfo = strategyInfo[strategy];

            if (!stratInfo.active) continue;

            // Calculate amount to deploy to this strategy
            uint256 stratAmount = (amount * stratInfo.allocation) / MAX_BPS;
            if (stratAmount == 0) continue;

            // Get current allowance
            uint256 currentAllowance = IERC20(address(asset)).allowance(address(this), strategy);
            // Decrease to 0 if needed
            if (currentAllowance > 0) {
                IERC20(address(asset)).safeDecreaseAllowance(strategy, currentAllowance);
            }
            // Increase to desired amount
            IERC20(address(asset)).safeIncreaseAllowance(strategy, stratAmount);

            // Deposit into strategy
            IERC4626Payable(strategy).deposit(stratAmount, address(this));

            // Update deployed amount
            stratInfo.totalDeployed += stratAmount;
            toAllocate -= stratAmount;
        }
    }

    /**
     * @notice Free funds from strategies for withdrawal
     * @dev Implements IBaseStrategy.freeFunds
     * @param amount Amount to free
     */
    function freeFunds(uint256 amount) external {
        // Only the vault itself can call this during withdrawal
        if (msg.sender != address(this)) revert Unauthorized();

        if (amount == 0) return;

        // Follow withdrawal queue order
        uint256 remaining = amount;

        for (uint256 i = 0; i < withdrawalQueue.length && remaining > 0; i++) {
            address strategy = withdrawalQueue[i];
            StrategyInfo storage stratInfo = strategyInfo[strategy];

            if (stratInfo.totalDeployed == 0) continue;

            // Calculate amount to withdraw from this strategy
            uint256 toWithdraw = Math.min(remaining, stratInfo.totalDeployed);

            // Withdraw from strategy
            remaining -= _withdrawFromStrategy(strategy, toWithdraw);

            if (remaining == 0) break;
        }

        // If we couldn't free enough, we'll have to take a loss
    }

    /**
     * @notice Helper to withdraw from a strategy
     * @param _strategy Strategy to withdraw from
     * @param _amount Amount to withdraw
     * @return amountReceived The amount actually received
     */
    function _withdrawFromStrategy(address _strategy, uint256 _amount) internal returns (uint256 amountReceived) {
        if (_amount == 0) return 0;

        StrategyInfo storage stratInfo = strategyInfo[_strategy];
        uint256 beforeBal = super._strategyStorage().asset.balanceOf(address(this));

        // Withdraw from strategy - allowing for some loss
        IERC4626Payable(_strategy).withdraw(_amount, address(this), address(this));

        uint256 afterBal = super._strategyStorage().asset.balanceOf(address(this));
        amountReceived = afterBal - beforeBal;

        // Update deployed amount
        if (amountReceived > stratInfo.totalDeployed) {
            stratInfo.totalDeployed = 0;
        } else {
            stratInfo.totalDeployed -= amountReceived;
        }

        return amountReceived;
    }

    /**
     * @notice Report profits and losses from all strategies
     * @dev Implements IBaseStrategy.harvestAndReport
     * @return totalAssets New total assets
     */
    function harvestAndReport() external onlyKeepers returns (uint256 totalAssets) {
        uint256 totalProfit = 0;
        uint256 totalLoss = 0;

        // Report all strategies
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyInfo storage stratInfo = strategyInfo[strategy];

            if (!stratInfo.active) continue;

            // Calculate expected value
            uint256 expectedValue = stratInfo.totalDeployed;

            // Get current value
            uint256 currentValue = IERC4626Payable(strategy).balanceOf(address(this));

            // Calculate profit/loss
            if (currentValue > expectedValue) {
                uint256 profit = currentValue - expectedValue;
                totalProfit += profit;

                // Harvest profit
                IERC4626Payable(strategy).withdraw(profit, address(this), address(this));

                emit StrategyReported(strategy, profit, 0);
            } else if (currentValue < expectedValue) {
                uint256 loss = expectedValue - currentValue;
                totalLoss += loss;

                // Update tracked value
                stratInfo.totalDeployed = currentValue;

                emit StrategyReported(strategy, 0, loss);
            }

            stratInfo.lastReport = block.timestamp;
        }

        // Calculate total assets including vault balance
        IERC20 asset = super._strategyStorage().asset;
        totalAssets = asset.balanceOf(address(this));

        // Add deployed assets
        for (uint256 i = 0; i < strategies.length; i++) {
            totalAssets += strategyInfo[strategies[i]].totalDeployed;
        }

        return totalAssets;
    }

    /**
     * @notice Tend strategies - optimize positions without deposit/withdrawal
     * @dev Implements IBaseStrategy.tendThis
     * @param balance Current idle balance to potentially deploy
     */
    function tendThis(uint256 balance) external onlyKeepers {
        _rebalance(balance);
    }

    /**
     * @notice Rebalance funds between strategies based on target allocations
     * @param additionalFunds Additional funds to deploy
     */
    function _rebalance(uint256 additionalFunds) internal {
        // Get total assets including new funds
        uint256 totalAssets = super._strategyStorage().totalAssets + additionalFunds;

        // Calculate target amounts for each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyInfo storage stratInfo = strategyInfo[strategy];

            if (!stratInfo.active) continue;

            // Calculate target amount
            uint256 targetAmount = (totalAssets * stratInfo.allocation) / MAX_BPS;

            // Compare with current deployed amount
            if (targetAmount > stratInfo.totalDeployed) {
                // Need to deposit more
                uint256 toDeposit = targetAmount - stratInfo.totalDeployed;

                // Ensure we have enough balance
                if (toDeposit <= additionalFunds) {
                    // Deposit to strategy
                    IERC20 token = IERC20(address(super._strategyStorage().asset));
                    // Get current allowance
                    uint256 currentAllowance = token.allowance(address(this), strategy);
                    // Decrease to 0 if needed
                    if (currentAllowance > 0) {
                        token.safeDecreaseAllowance(strategy, currentAllowance);
                    }
                    // Increase to desired amount
                    token.safeIncreaseAllowance(strategy, toDeposit);
                    IERC4626Payable(strategy).deposit(toDeposit, address(this));

                    // Update tracking
                    stratInfo.totalDeployed += toDeposit;
                    additionalFunds -= toDeposit;
                }
            } else if (targetAmount < stratInfo.totalDeployed) {
                // Need to withdraw
                uint256 toWithdraw = stratInfo.totalDeployed - targetAmount;

                // Withdraw from strategy
                uint256 received = _withdrawFromStrategy(strategy, toWithdraw);

                // Add to available funds
                additionalFunds += received;
            }
        }
    }

    /**
     * @notice Provides information about all strategies
     * @return _strategies Array of strategy addresses
     * @return _allocations Array of strategy allocations
     * @return _deployed Array of deployed amounts
     */
    function getStrategiesInfo()
        external
        view
        returns (address[] memory _strategies, uint256[] memory _allocations, uint256[] memory _deployed)
    {
        uint256 length = strategies.length;
        _strategies = new address[](length);
        _allocations = new uint256[](length);
        _deployed = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            address strategy = strategies[i];
            StrategyInfo storage stratInfo = strategyInfo[strategy];

            _strategies[i] = strategy;
            _allocations[i] = stratInfo.allocation;
            _deployed[i] = stratInfo.totalDeployed;
        }
    }

    /**
     * @notice Special case for shutdown
     * @dev Implements IBaseStrategy.shutdownWithdraw
     */
    function shutdownWithdraw(uint256) external onlyEmergencyAuthorized {
        // Withdraw from all strategies
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyInfo storage stratInfo = strategyInfo[strategy];

            if (stratInfo.totalDeployed > 0) {
                try IERC4626Payable(strategy).redeem(stratInfo.totalDeployed, address(this), address(this)) {
                    stratInfo.totalDeployed = 0;
                } catch {
                    // Continue to next strategy even if one fails
                }
            }
        }
    }
}
