// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IStaking {
    function stakingToken() external view returns (address);
    function rewardsToken() external view returns (address);
    function paused() external view returns (bool);
    function earned(address) external view returns (uint256);
    function stake(uint256 _amount, uint16 _referral) external;
    function withdraw(uint256 _amount) external;
    function getReward() external;
}

interface IReferral {
    function deposit(uint256, address, uint16) external;
}

interface ISkyCompounder {
    // Events for state changes
    event ClaimRewardsUpdated(bool claimRewards);
    event UniV3SettingsUpdated(bool useUniV3, uint24 rewardToBase, uint24 baseToAsset);
    event MinAmountToSellUpdated(uint256 minAmountToSell);
    event BaseTokenUpdated(address base, bool useUniV3, uint24 rewardToBase, uint24 baseToAsset);
    event ReferralUpdated(uint16 referral);
    event MinAmountOutUpdated(uint256 minAmountOut);

    // Management functions
    function setClaimRewards(bool _claimRewards) external;
    function setUseUniV3andFees(bool _useUniV3, uint24 _rewardToBase, uint24 _baseToAsset) external;
    function setMinAmountToSell(uint256 _minAmountToSell) external;
    function setBase(address _base, bool _useUniV3, uint24 _rewardToBase, uint24 _baseToAsset) external;
    function setReferral(uint16 _referral) external;
    function setMinAmountOut(uint256 _minAmountOut) external;
}
