// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title IPSM
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Interface for MakerDAO Peg Stability Module (PSM)
 * @dev Used for stable swaps between DAI and other stablecoins
 */
interface IPSM {
    function sellGem(address usr, uint256 gemAmt) external;
    function buyGem(address usr, uint256 gemAmt) external;
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
}

/**
 * @title IExchange
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Interface for DAI/USDS exchange contract
 * @dev Bidirectional conversion between DAI and USDS
 */
interface IExchange {
    function daiToUsds(address usr, uint256 wad) external;
    function usdsToDai(address usr, uint256 wad) external;
}
