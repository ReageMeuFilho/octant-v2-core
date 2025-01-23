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

   /**
    * @notice Contract constructor
    * @param _depositContract ETH2 deposit contract address
    * @param _asset Asset contract address (WETH)
    * @param _name Share token name
    * @param _symbol Share token symbol
    */
   constructor(
       address _depositContract,
       address _asset,
       string memory _name,
       string memory _symbol
   ) ERC4626(IERC20(_asset)) ERC20(_name, _symbol) {
       require(_depositContract != address(0), "Invalid deposit contract");
       DEPOSIT_CONTRACT = IDepositContract(_depositContract);
   }
/**
    * @notice Request deposit of ETH for validator creation
    * @param assets Amount of ETH to deposit (must be 32)
    * @param controller Address that controls the validator
    * @param owner Address providing the ETH
    * @param withdrawalCreds Withdrawal credentials for validator
    * @return requestId Always returns 0 per ERC7540 spec
    */
   function requestDeposit(
       uint256 assets,
       address controller,
       address owner,
       bytes calldata withdrawalCreds
   ) public payable nonReentrant returns (uint256) {
       // Input validation
       require(owner == msg.sender || isOperator[owner][msg.sender], "Not authorized");
       require(assets == VALIDATOR_DEPOSIT && msg.value == VALIDATOR_DEPOSIT, "Must be 32 ETH");
       require(withdrawalCreds.length == 32, "Invalid withdrawal credentials");
       require(!validators[controller].isActive, "Validator exists");
       require(depositRequests[controller].amount == 0, "Request exists");

       // Track pending deposit
       pendingDeposits[controller] = assets;
       
       // Store validator and request info
       validators[controller].withdrawalCreds = withdrawalCreds;
       depositRequests[controller] = RequestInfo({
           amount: assets,
           owner: owner,
           isCancelled: false,
           isProcessed: false
       });

       emit ValidatorRequested(controller, withdrawalCreds, block.timestamp);
       emit DepositRequest(controller, owner, 0, msg.sender, assets);
       return 0;
   }

   /**
    * @notice Process validator deposit with signing credentials
    * @param controller Controller address 
    * @param pubkey Validator public key
    * @param signature Proof of possession of signing key
    * @param depositDataRoot Merkle root of deposit data
    */
   function processValidatorDeposit(
       address controller,
       bytes calldata pubkey,
       bytes calldata signature,
       bytes32 depositDataRoot
   ) external nonReentrant {
       // Load state
       RequestInfo storage request = depositRequests[controller];
       ValidatorInfo storage validator = validators[controller];
       
       // Validate state
       require(pendingDeposits[controller] == VALIDATOR_DEPOSIT, "No pending deposit");
       require(!request.isProcessed && !request.isCancelled, "Invalid request state");
       require(!validator.isActive, "Validator already exists");
       require(pubkey.length == 48 && signature.length == 96, "Invalid key lengths");

       // Process deposit
       DEPOSIT_CONTRACT.deposit{value: VALIDATOR_DEPOSIT}(
           pubkey,
           validator.withdrawalCreds,
           signature,
           depositDataRoot
       );

       // Update state
       totalAssets += VALIDATOR_DEPOSIT;
       pendingDeposits[controller] = 0;

       validator.pubkey = pubkey;
       validator.signature = signature;
       validator.depositDataRoot = depositDataRoot;
       validator.isActive = true;

       _mint(request.owner, VALIDATOR_DEPOSIT);
       request.isProcessed = true;

       emit ValidatorActivated(controller, pubkey, block.timestamp);
   }

   /**
    * @notice Get pending deposit amount for controller
    * @param requestId Unused - returns 0 if no pending deposit
    * @param controller Controller address to check
    * @return Amount of ETH pending deposit
    */
   function pendingDepositRequest(
       uint256 requestId,
       address controller
   ) external view returns (uint256) {
       return pendingDeposits[controller];
   }

   /**
    * @notice Get claimable deposit amount for controller
    * @param requestId Unused - returns 0 if nothing claimable
    * @param controller Controller address to check
    * @return Amount of ETH ready to claim
    */
   function claimableDepositRequest(
       uint256 requestId,
       address controller
   ) external view returns (uint256) {
       RequestInfo storage request = depositRequests[controller];
       return (request.isProcessed && !request.isCancelled) ? request.amount : 0;
   }


   // --- ERC4626 Overrides ---

   /**
    * @notice Total ETH controlled by vault (explicitly tracked)
    * @return Total assets in vault
    */
   function totalAssets() public view override returns (uint256) {
       return totalAssets;
   }

   /**
    * @notice Convert assets to shares (1:1 for ETH staking)
    * @param assets Amount of ETH
    * @return shares Equal amount of shares
    */
   function convertToShares(
       uint256 assets
   ) public pure override returns (uint256) {
       return assets;
   }

   /**
    * @notice Convert shares to assets (1:1 for ETH staking)
    * @param shares Amount of shares
    * @return assets Equal amount of ETH
    */
   function convertToAssets(
       uint256 shares
   ) public pure override returns (uint256) {
       return shares;
   }

   /**
    * @notice Maximum deposit allowed (32 ETH if no active validator)
    * @param controller Address to check
    * @return Maximum deposit amount
    */
   function maxDeposit(
       address controller
   ) public view override returns (uint256) {
       if (validators[controller].isActive || pendingDeposits[controller] > 0) {
           return 0;
       }
       return VALIDATOR_DEPOSIT;
   }

   /**
    * @notice Maximum mint allowed (32 ETH if no active validator)
    * @param controller Address to check
    * @return Maximum mint amount
    */
   function maxMint(
       address controller
   ) public view override returns (uint256) {
       return maxDeposit(controller);
   }

   /**
    * @notice Maximum withdrawal allowed (full balance if validator exited)
    * @param owner Address to check
    * @return Maximum withdrawal amount
    */
   function maxWithdraw(
       address owner
   ) public view override returns (uint256) {
       ValidatorInfo storage validator = validators[owner];
       return validator.isExited ? balanceOf(owner) : 0;
   }

   /**
    * @notice Maximum redemption allowed (full balance if validator exited)
    * @param owner Address to check
    * @return Maximum redemption amount
    */
   function maxRedeem(
       address owner
   ) public view override returns (uint256) {
       return maxWithdraw(owner);
   }

   /**
    * @notice Disabled - use requestDeposit for async deposits
    */
   function deposit(
       uint256,
       address
   ) public pure override returns (uint256) {
       revert("Use requestDeposit");
   }

   /**
    * @notice Disabled - use requestDeposit for async deposits
    */
   function mint(
       uint256,
       address
   ) public pure override returns (uint256) {
       revert("Use requestDeposit");
   }

   /**
    * @notice Disabled - use requestRedeem for async withdrawals
    */
   function withdraw(
       uint256,
       address,
       address
   ) public pure override returns (uint256) {
       revert("Use requestRedeem");
   }

   /**
    * @notice Disabled - use requestRedeem for async withdrawals
    */
   function redeem(
       uint256,
       address,
       address
   ) public pure override returns (uint256) {
       revert("Use requestRedeem");
   }

   /**
    * @notice Disabled for async vault
    */
   function previewDeposit(
       uint256
   ) public pure override returns (uint256) {
       revert("Async deposits only");
   }

   /**
    * @notice Disabled for async vault
    */
   function previewMint(
       uint256
   ) public pure override returns (uint256) {
       revert("Async deposits only");
   }

   /**
    * @notice Disabled for async vault
    */
   function previewWithdraw(
       uint256
   ) public pure override returns (uint256) {
       revert("Async withdrawals only");
   }

   /**
    * @notice Disabled for async vault
    */
   function previewRedeem(
       uint256
   ) public pure override returns (uint256) {
       revert("Async withdrawals only");
   }

   /**
    * @notice Only accept ETH from deposit contract
    */
   receive() external payable {
       require(msg.sender == address(DEPOSIT_CONTRACT), "Direct deposits not allowed");
   }

   /**
    * @notice Prevent accidental ETH transfers
    */
   fallback() external payable {
       revert("Not supported");
   }

}