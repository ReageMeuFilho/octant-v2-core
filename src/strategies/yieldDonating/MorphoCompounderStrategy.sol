// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseHealthCheck } from "src/strategies/periphery/BaseHealthCheck.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title MorphoCompounderStrategy
/// @author [Golem Foundation](https://golem.foundation)
/// @custom:security-contact security@golem.foundation
/// @notice Yearn v3 Strategy that donates rewards.
contract MorphoCompounderStrategy is BaseHealthCheck {
    using SafeERC20 for IERC20;

    /// @dev Thrown when the configured compounder vault asset differs from the strategy asset.
    error InvalidCompounderAsset(address expected, address actual);

    // morpho vault
    address public immutable compounderVault;
    /// @dev Tracks excess reported capacity that failed during deposit attempts.
    uint256 internal maxDepositBuffer;

    /**
     * @param _compounderVault Address of the Morpho vault this strategy compounds into
     * @param _asset Address of the underlying asset of the Morpho vault
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
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
        BaseHealthCheck(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        // make sure asset is Morpho's asset
        address expectedAsset = IERC4626(_compounderVault).asset();
        if (expectedAsset != _asset) {
            revert InvalidCompounderAsset(expectedAsset, _asset);
        }
        IERC20(_asset).forceApprove(_compounderVault, type(uint256).max);
        compounderVault = _compounderVault;
    }

    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        uint256 vaultLimit = IERC4626(compounderVault).maxDeposit(address(this));
        uint256 idleBalance = IERC20(asset).balanceOf(address(this));
        uint256 limit = vaultLimit > idleBalance ? vaultLimit - idleBalance : 0;
        uint256 buffer = maxDepositBuffer;
        return buffer >= limit ? 0 : limit - buffer;
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this)) + IERC4626(compounderVault).maxWithdraw(address(this));
    }

    function _deployFunds(uint256 _amount) internal override {
        if (_amount == 0) return;

        uint256 remaining = _amount;
        while (remaining > 0) {
            uint256 reportedLimit = IERC4626(compounderVault).maxDeposit(address(this));
            if (reportedLimit == 0 || reportedLimit <= maxDepositBuffer) {
                // Reported capacity is exhausted or previously proven inaccurate.
                break;
            }

            uint256 effectiveLimit = reportedLimit - maxDepositBuffer;
            uint256 toDeposit = remaining < effectiveLimit ? remaining : effectiveLimit;
            if (toDeposit == 0) break;

            uint256 attempt = toDeposit;
            bool deposited;
            while (attempt > 0) {
                try IERC4626(compounderVault).deposit(attempt, address(this)) returns (uint256) {
                    remaining -= attempt;
                    maxDepositBuffer = 0;
                    deposited = true;
                    break;
                } catch {
                    // Reduce the attempt by 10%. Ensure we always make progress by clamping the reduction.
                    uint256 reduction = attempt / 10;
                    if (reduction == 0) reduction = 1;
                    if (attempt <= reduction) {
                        attempt = 0;
                    } else {
                        attempt -= reduction;
                    }
                }
            }

            if (!deposited) {
                // Even the smallest practical attempt failed; block further deposits until the limit changes.
                maxDepositBuffer = reportedLimit;
                break;
            }

            if (remaining == 0) {
                break;
            }
        }
    }

    function _freeFunds(uint256 _amount) internal override {
        IERC4626(compounderVault).withdraw(_amount, address(this), address(this));
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }

    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // get strategy's balance in the vault
        uint256 shares = IERC4626(compounderVault).balanceOf(address(this));
        uint256 vaultAssets = IERC4626(compounderVault).convertToAssets(shares);

        // include idle funds as per BaseStrategy specification
        uint256 idleAssets = IERC20(asset).balanceOf(address(this));

        _totalAssets = vaultAssets + idleAssets;

        return _totalAssets;
    }
}
