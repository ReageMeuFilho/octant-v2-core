// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseHealthCheck } from "src/strategies/periphery/BaseHealthCheck.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

/// @title YearnV3Strategy
/// @author [Golem Foundation](https://golem.foundation)
/// @custom:security-contact security@golem.foundation
/// @notice Strategy that donates rewards from a Yearn v3 vault.
contract YearnV3Strategy is BaseHealthCheck {
    using SafeERC20 for IERC20;

    // Yearn v3 vault
    address public immutable yearnVault;

    /**
     * @param _yearnVault Address of the Yearn v3 vault this strategy compounds into
     * @param _asset Address of the underlying asset of the Yearn v3 vault
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _yearnVault,
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
        // make sure asset is Yearn vault's asset
        require(ITokenizedStrategy(_yearnVault).asset() == _asset, "Asset mismatch with compounder vault");
        IERC20(_asset).forceApprove(_yearnVault, type(uint256).max);
        yearnVault = _yearnVault;
    }

    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        // NOTE: If the yearnVault is a meta-vault that deposits into other vaults (e.g., Morpho Steakhouse),
        // the maxDeposit value may be inflated when the underlying chain reaches vaults with duplicate
        // markets in their supplyQueue (like SteakHouse USDC). This could cause temporary DoS for deposits
        uint256 vaultLimit = ITokenizedStrategy(yearnVault).maxDeposit(address(this));
        uint256 idleBalance = IERC20(asset).balanceOf(address(this));
        return vaultLimit > idleBalance ? vaultLimit - idleBalance : 0;
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this)) + ITokenizedStrategy(yearnVault).maxWithdraw(address(this));
    }

    function _deployFunds(uint256 _amount) internal override {
        ITokenizedStrategy(yearnVault).deposit(_amount, address(this));
    }

    function _freeFunds(uint256 _amount) internal override {
        // NOTE: maxLoss is set to 10_000 (100%) to ensure withdrawals don't revert when the Yearn vault
        // has unrealized losses. This is necessary because:
        // 1. When the TokenizedStrategy needs funds, it calls freeFunds() to withdraw from the underlying Yearn vault
        // 2. Without accepting losses here, any slippage/loss in Yearn would cause the withdrawal to fail
        // 3. The MultistrategyVault performs its own loss checks after withdrawal via updateDebt's maxLoss parameter
        // This allows the strategy to always provide liquidity while loss protection is enforced at the vault level.
        ITokenizedStrategy(yearnVault).withdraw(_amount, address(this), address(this), 10_000);
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }

    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // get strategy's balance in the vault
        uint256 shares = ITokenizedStrategy(yearnVault).balanceOf(address(this));
        uint256 vaultAssets = ITokenizedStrategy(yearnVault).convertToAssets(shares);

        uint256 idleAssets = IERC20(asset).balanceOf(address(this));

        _totalAssets = vaultAssets + idleAssets;

        return _totalAssets;
    }
}
