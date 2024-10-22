// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

/**
 * @dev     In charge of splitting yield profits from dragon strategy, in case of a loss strategy burns shares owned by the dragon module
 * @notice  Interface for the Dragon Router Contract
 */
interface IDragonRouter {
    /**
     * @dev Distributes new splits to all shareholders.
     * @param amount The amount of tokens to distribute.
     */
    function fundFromSource(uint256 amount) external;

    /**
     * @dev Mints new shares for a user.
     * @param to The address receiving the shares.
     * @param amount The number of shares to mint.
     */
    function mint(address to, uint256 amount) external;

    /**
     * @dev Burns shares from a user.
     * @param from The address to burn shares from.
     * @param amount The number of shares to burn.
     */
    function burn(address from, uint256 amount) external;

    /**
     * @dev Allows a user to claim their available split, optionally transforming it.
     */
    function claimSplit() external;
}
