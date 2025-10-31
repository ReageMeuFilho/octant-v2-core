// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IVault {
    function asset() external view returns (address);
    function deposit(uint256 assets, address receiver) external;
    function withdraw(uint256 assets, address receiver, address owner) external;
    function withdraw(uint256 assets, address receiver, address owner, uint256 maxLoss) external;
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxRedeem(address) external view returns (uint256);
    function maxWithdraw(address) external view returns (uint256);
    function previewWithdraw(uint256) external view returns (uint256);
}
