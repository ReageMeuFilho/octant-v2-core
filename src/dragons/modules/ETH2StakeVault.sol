// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

/**
* @title ETH2StakeVault
* @notice ERC7540 compliant vault for ETH2 validator staking
* @dev Implements async deposits/withdrawals for ETH2 validators with 1:1 share ratio
*/
contract ETH2StakeVault is ERC4626, ReentrancyGuard {
   using SafeTransferLib for IERC20;

   /// @notice Required deposit amount for ETH2 validators
   uint256 private constant VALIDATOR_DEPOSIT = 32 ether;

   /// @notice Validator information tracking
   struct ValidatorInfo {
       bytes withdrawalCreds;     // BLS withdrawal credentials
       bytes pubkey;              // Validator public key
       bytes signature;           // BLS proof of possession
       bytes32 depositDataRoot;   // Merkle root of deposit data
       bool isActive;            // Whether validator is on beacon chain
       uint256 slashedAmount;    // Amount of ETH slashed if any
       bool isExited;            // Whether validator has exited
       uint256 exitEpoch;        // Epoch number when validator exited
   }

   /// @notice Request state tracking
   struct RequestInfo {
       uint256 amount;           // ETH/shares amount (always 32 ETH for deposits)
       address owner;            // Original ETH/shares owner
       bool isCancelled;         // If request was cancelled
       bool isProcessed;         // If request was processed
   }

   /// @notice Core contract references
   IDepositContract public immutable DEPOSIT_CONTRACT;

   /// @notice Total asset tracking
   uint256 public override totalAssets;  

   /// @notice Pending amounts tracking
   mapping(address => uint256) public pendingDeposits;
   mapping(address => uint256) public pendingWithdrawals;

   /// @notice State tracking
   mapping(address => ValidatorInfo) public validators;
   mapping(address => RequestInfo) public depositRequests;
   mapping(address => RequestInfo) public redeemRequests;
   mapping(address => mapping(address => bool)) public isOperator;

   // --- Events ---

   event ValidatorRequested(
       address indexed controller,
       bytes withdrawalCreds,
       uint256 timestamp
   );

   event ValidatorActivated(
       address indexed controller,
       bytes pubkey,
       uint256 timestamp
   );

   event ValidatorExited(
       address indexed controller,
       uint256 exitEpoch,
       uint256 timestamp
   );

   event ValidatorSlashed(
       address indexed controller,
       uint256 amount,
       uint256 timestamp
   );

   
}