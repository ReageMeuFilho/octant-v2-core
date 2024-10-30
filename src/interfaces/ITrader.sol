// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface ITrader {
    function setSpendADay(uint256 _low, uint256 _high, uint256 _budget, uint256 _deadline) external;
    function convert(uint256 _height) external;
    function setSwapper(address _swapper) external;

    function token() public view returns (address);
    function swapper() public view returns (address);

    function budget() public view returns (uint256);
    function deadline() public view returns (uint256);
    function spent() public view returns (uint256);

    function saleValueLow() public view returns (uint256);
    function saleValueHigh() public view returns (uint256);
}
