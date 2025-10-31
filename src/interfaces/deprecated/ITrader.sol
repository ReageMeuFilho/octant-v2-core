// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface ITrader {
    function setSpending(uint256 _low, uint256 _high, uint256 _budget) external;
    function convert(uint256 _height) external;
    function setSwapper(address _swapper) external;

    function base() external view returns (address);
    function quote() external view returns (address);
    function swapper() external view returns (address);

    function budget() external view returns (uint256);
    function deadline() external view returns (uint256);
    function spent() external view returns (uint256);

    function saleValueLow() external view returns (uint256);
    function saleValueHigh() external view returns (uint256);
}
