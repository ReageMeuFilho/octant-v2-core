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
