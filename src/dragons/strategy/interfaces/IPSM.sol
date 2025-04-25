// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IPSM {
    function sellGem(address usr, uint256 gemAmt) external;
    function buyGem(address usr, uint256 gemAmt) external;
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
}

interface IExchange {
    function daiToUsds(address usr, uint256 wad) external;
    function usdsToDai(address usr, uint256 wad) external;
}
