// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IImpactStrategy Interface
 * @notice Interface for the ImpactStrategy implementation contract
 * @dev Defines core functionality for voting-based fund distribution
 */
interface IImpactStrategy {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed user, uint256 assets, uint256 veTokens);
    event VoteCast(address indexed user, address indexed project, uint256 weight);
    event SharesAllocated(address indexed project, uint256 shares);
    event Redeem(address indexed project, uint256 shares, uint256 assets);
    event UpdateManagement(address indexed management);
    event UpdateKeeper(address indexed keeper);
    event UpdateEmergencyAdmin(address indexed admin);
    event NewTokenizedStrategy(address indexed strategy, address indexed asset, string apiVersion);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address asset,
        string memory name,
        address management,
        address projectRegistry,
        address keeper
    ) external;

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit assets and receive veTokens
    function deposit(uint256 assets, address receiver) external returns (uint256 veTokens);

    /// @notice Cast votes for a project
    function vote(address project, uint256 weight) external;

    /// @notice Allocate shares based on vote tallies
    function allocateShares() external;

    /// @notice Redeem shares for assets
    function redeem(uint256 shares) external returns (uint256 assets);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get user's votes for a project
    function getUserVotes(address user, address project) external view returns (uint256);

    /// @notice Get total votes for a project
    function getProjectVotes(address project) external view returns (uint256);

    /// @notice Get total votes cast in strategy
    function getTotalVotes() external view returns (uint256);

    /// @notice Check if address passes sybil resistance
    function checkSybilResistance(address voter) external view returns (bool passed, uint256 score);

    /// @notice Get available deposit limit for voter
    function availableDepositLimit(address voter) external view returns (uint256);

    /// @notice Get available withdraw limit for project
    function availableWithdrawLimit(address project) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set new management address
    function setPendingManagement(address pendingManagement) external;

    /// @notice Accept management role
    function acceptManagement() external;

    /// @notice Set new keeper address
    function setKeeper(address keeper) external;

    /// @notice Set emergency admin address
    function setEmergencyAdmin(address emergencyAdmin) external;

    /// @notice Update strategy name
    function setName(string calldata name) external;

    /// @notice Validates if msg.sender is either keeper or management
    /// @dev Reverts if caller is neither keeper nor management
    /// @return true if msg.sender is either keeper or management
    function requireKeeperOrManagement(address _sender) external view returns (bool);

    /// @notice Validates if msg.sender is emergency admin
    /// @dev Reverts if caller is not emergency admin
    /// @return true if msg.sender is emergency admin
    function requireEmergencyAuthorized() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            ERC20 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get strategy token name
    function name() external view returns (string memory);

    /// @notice Get strategy token symbol
    function symbol() external view returns (string memory);

    /// @notice Get token decimals
    function decimals() external view returns (uint8);

    /// @notice Get account balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfer tokens
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Get allowance
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Approve spender
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Transfer tokens from sender
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get current nonce for owner
    function nonces(address owner) external view returns (uint256);

    /// @notice EIP-2612 permit
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Get domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
