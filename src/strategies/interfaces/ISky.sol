// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title IStaking
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Interface for Sky staking contract
 * @dev Supports stake, withdraw, and reward claiming operations
 */
interface IStaking {
    function stakingToken() external view returns (address);
    function rewardsToken() external view returns (address);
    function paused() external view returns (bool);
    function earned(address) external view returns (uint256);
    function stake(uint256 _amount, uint16 _referral) external;
    function withdraw(uint256 _amount) external;
    function getReward() external;
}

/**
 * @title IReferral
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Interface for referral tracking in Sky protocol
 */
interface IReferral {
    function deposit(uint256, address, uint16) external;
}

/**
 * @title ISkyCompounder
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Interface for Sky compounder strategy management functions
 * @dev Configuration interface for UniswapV2/V3 swap settings and MEV protection
 */
interface ISkyCompounder {
    /// @notice Emitted when claim rewards setting is updated
    /// @param claimRewards True if rewards should be claimed automatically
    event ClaimRewardsUpdated(bool claimRewards);
    
    /// @notice Emitted when Uniswap V3 swap settings are updated
    /// @param useUniV3 True if Uniswap V3 should be used
    /// @param rewardToBase Fee tier for reward to base token swap in basis points
    /// @param baseToAsset Fee tier for base to asset token swap in basis points
    event UniV3SettingsUpdated(bool useUniV3, uint24 rewardToBase, uint24 baseToAsset);
    
    /// @notice Emitted when minimum amount to sell is updated
    /// @param minAmountToSell Minimum token amount to trigger swap in token base units
    event MinAmountToSellUpdated(uint256 minAmountToSell);
    
    /// @notice Emitted when base token is updated
    /// @param base Address of new base token
    /// @param useUniV3 True if Uniswap V3 should be used
    /// @param rewardToBase Fee tier for reward to base token swap in basis points
    /// @param baseToAsset Fee tier for base to asset token swap in basis points
    event BaseTokenUpdated(address base, bool useUniV3, uint24 rewardToBase, uint24 baseToAsset);
    
    /// @notice Emitted when referral code is updated
    /// @param referral New referral code
    event ReferralUpdated(uint16 referral);
    
    /// @notice Emitted when minimum amount out is updated
    /// @param minAmountOut Minimum output amount for swaps in token base units
    event MinAmountOutUpdated(uint256 minAmountOut);

    // Management functions
    function setClaimRewards(bool _claimRewards) external;
    function setUseUniV3andFees(bool _useUniV3, uint24 _rewardToBase, uint24 _baseToAsset) external;
    function setMinAmountToSell(uint256 _minAmountToSell) external;
    function setBase(address _base, bool _useUniV3, uint24 _rewardToBase, uint24 _baseToAsset) external;
    function setReferral(uint16 _referral) external;
    function setMinAmountOut(uint256 _minAmountOut) external;
}
