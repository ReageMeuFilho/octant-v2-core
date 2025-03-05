// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

interface IMantleStaking {
    function stake() external payable;
    function unstake(uint256 mETHAmount) external;
    function ethToMETH(uint256 ethAmount) external view returns (uint256);
    function mETHToETH(uint256 mETHAmount) external view returns (uint256);
    function totalControlled() external view returns (uint256);
    function convertMETHToETH(uint256 mETHAmount) external view returns (uint256);
    function unstakeRequest(uint256 mETHAmount, uint256 ethAmount) external returns (uint256);
    function unstakeRequestInfo(uint256 unstakeRequestID) external view returns (bool, uint256);
    function claimUnstakeRequest(uint256 unstakeRequestID) external;
    function maximumDepositAmount() external view returns (uint256);
}
