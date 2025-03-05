// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IMantleStaking } from "src/interfaces/IMantleStaking.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Mock Mantle Staking Contract
/// @notice A mock implementation of the Mantle staking contract for testing
contract MockMantleStaking is IMantleStaking {
    IERC20 public mETHToken;
    uint256 public exchangeRate = 1e18; // 1:1 ETH:mETH ratio by default

    mapping(uint256 => UnstakeRequest) public unstakeRequests;
    uint256 public nextRequestId = 1;

    struct UnstakeRequest {
        address requester;
        uint256 mETHAmount;
        uint256 ethAmount;
        bool finalized;
        bool claimed;
        uint256 filledAmount;
    }

    /// @notice Constructor that sets the mETH token
    constructor(address _mETHToken) {
        mETHToken = IERC20(_mETHToken);
    }

    /// @notice Set a new exchange rate for testing
    function setExchangeRate(uint256 _exchangeRate) external {
        exchangeRate = _exchangeRate;
    }

    /// @notice Set the mETH token reference for testing
    function setMETHToken(address _mETHToken) external {
        mETHToken = IERC20(_mETHToken);
    }

    /// @notice Stake ETH to receive mETH
    function stake() external payable override {
        // Calculate mETH amount based on exchange rate
        uint256 mETHAmount = ethToMETH(msg.value);

        // Mint mETH token to sender
        // For testing, we simulate the minting by manually transferring tokens
        (bool success, ) = address(mETHToken).call(
            abi.encodeWithSignature("mint(address,uint256)", msg.sender, mETHAmount)
        );
        require(success, "Failed to mint mETH");
    }

    /// @notice Unstake mETH to receive ETH (deprecated)
    function unstake(uint256 mETHAmount) external override {
        revert("Direct unstake deprecated, use unstakeRequest");
    }

    /// @notice Convert ETH to mETH based on current exchange rate
    function ethToMETH(uint256 ethAmount) public view override returns (uint256) {
        return (ethAmount * 1e18) / exchangeRate;
    }

    /// @notice Convert mETH to ETH based on current exchange rate
    function mETHToETH(uint256 mETHAmount) public view override returns (uint256) {
        return (mETHAmount * exchangeRate) / 1e18;
    }

    /// @notice Alias for mETHToETH (for compatibility)
    function convertMETHToETH(uint256 mETHAmount) external view override returns (uint256) {
        return this.mETHToETH(mETHAmount);
    }

    /// @notice Get total ETH controlled by the system
    function totalControlled() external view override returns (uint256) {
        return address(this).balance;
    }

    /// @notice Create a new unstake request
    function unstakeRequest(uint256 mETHAmount, uint256 ethAmount) external override returns (uint256) {
        // Take the mETH tokens
        (bool success, ) = address(mETHToken).call(
            abi.encodeWithSignature("burn(address,uint256)", msg.sender, mETHAmount)
        );
        require(success, "Failed to burn mETH");

        // Record the unstake request
        uint256 requestId = nextRequestId++;
        unstakeRequests[requestId] = UnstakeRequest({
            requester: msg.sender,
            mETHAmount: mETHAmount,
            ethAmount: ethAmount,
            finalized: false,
            claimed: false,
            filledAmount: 0
        });

        return requestId;
    }

    /// @notice Get information about an unstake request
    function unstakeRequestInfo(uint256 unstakeRequestID) external view override returns (bool, uint256) {
        UnstakeRequest storage request = unstakeRequests[unstakeRequestID];
        return (request.finalized, request.ethAmount);
    }

    /// @notice Claim ETH from a finalized unstake request
    function claimUnstakeRequest(uint256 unstakeRequestID) external override {
        UnstakeRequest storage request = unstakeRequests[unstakeRequestID];
        require(request.finalized, "Request not finalized");
        require(!request.claimed, "Request already claimed");
        require(request.requester == msg.sender, "Not your request");

        request.claimed = true;

        // Transfer ETH to the requester
        (bool success, ) = request.requester.call{ value: request.ethAmount }("");
        require(success, "ETH transfer failed");
    }

    /// @notice For testing: finalize a specific unstake request
    function finalizeRequest(uint256 requestId) external {
        unstakeRequests[requestId].finalized = true;
    }

    function maximumDepositAmount() external view override returns (uint256) {
        return 32 ether;
    }

    /// @notice Allow the contract to receive ETH
    receive() external payable {}

    /// @notice For testing: set the ETH amount and filled amount for a specific unstake request
    function setRequestAmount(uint256 requestId, uint256 amount) external {
        // Set both ethAmount and filledAmount for the request
        unstakeRequests[requestId].ethAmount = amount;
        unstakeRequests[requestId].filledAmount = amount;
    }

    function unfinalizeRequest(uint256 requestId) external {
        // Set the request as not finalized
        unstakeRequests[requestId].finalized = false;
    }
}
