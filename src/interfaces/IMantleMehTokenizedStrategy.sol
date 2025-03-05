// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

import { IDragonTokenizedStrategy } from "src/interfaces/IDragonTokenizedStrategy.sol";

interface IMantleMehTokenizedStrategy {
    /* Error for invalid amount during deposit */
    error InvalidAmount();

    /* Error when user tries to claim a request that isn't theirs */
    error NotYourRequest();

    /* Error when trying to claim an already claimed request */
    error RequestAlreadyClaimed();

    /* Error when request is not ready for claiming */
    error RequestNotReady();

    /* Error when ETH transfer fails */
    error ETHTransferFailed();

    /* Mantle Staking Contract */
    function MANTLE_STAKING() external view returns (address);

    /* mETH token address */
    function METH_TOKEN() external view returns (address);

    /* Function to claim ETH from a specific unstake request
     * @param requestId The ID of the unstake request to claim
     */
    function claimUnstakeRequest(uint256 requestId, address receiver) external;

    /* Check all unstake requests for a user
     * @param user The address of the user to check
     * @return Array of request IDs, array of finalized status, array of filled amounts
     */
    function getUserUnstakeRequests(
        address user
    ) external view returns (uint256[] memory, bool[] memory, uint256[] memory);

    /* Helper function to convert assets (ETH) to mETH amount
     * @param ethAmount Amount of ETH to convert
     * @return Equivalent amount of mETH based on Mantle's exchange rate
     */
    function convertAssetsToMETH(uint256 ethAmount) external view returns (uint256);

    /* Helper function to convert mETH to assets (ETH)
     * @param methAmount Amount of mETH to convert
     * @return Equivalent amount of ETH based on Mantle's exchange rate
     */
    function convertMETHToAssets(uint256 methAmount) external view returns (uint256);

    /* Check if an unstake request has been claimed
     * @param requestId The ID of the request to check
     * @return True if the request has been claimed, false otherwise
     */
    function unstakeRequestClaimed(uint256 requestId) external view returns (bool);

    /* Get a specific user's unstake requests
     * @param user The address of the user
     * @param index The index in the user's requests array
     * @return The request ID at the given index
     */
    function userUnstakeRequests(address user, uint256 index) external view returns (uint256);
}
