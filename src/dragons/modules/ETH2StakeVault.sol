// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

contract ETH2StakeVault is ERC4626, IERC7540Vault, ReentrancyGuard {
    using SafeTransferLib for IERC20;

    uint256 private constant VALIDATOR_DEPOSIT = 32 ether;
    
    enum RequestState { None, Pending, Processing, Claimable, Cancelled, Claimed }
    
    struct ValidatorInfo {
        bytes withdrawalCreds;     
        bytes pubkey;              
        bytes signature;           
        bytes32 depositDataRoot;   
        bool isActive;            
        uint256 slashedAmount;    
        bool isExited;            
        uint256 exitEpoch;
        uint256 requestId;        // Request that created this validator
    }

    struct Request {
        uint256 amount;          
        address owner;           // Original ETH/share provider
        address controller;      // Request controller
        RequestState state;      // Current state
        RequestType requestType; // Deposit or Redeem
        uint256 validatorIndex;  // Index if validator created
    }

    enum RequestType { Deposit, Redeem }

    // Core contract
    IDepositContract public immutable DEPOSIT_CONTRACT;

    // Request management
    uint256 public nextRequestId;
    mapping(uint256 => Request) public requests;
    mapping(uint256 => ValidatorInfo) public validators;
    
    // Amount tracking
    uint256 public override totalAssets;
    mapping(uint256 => uint256) public pendingDeposits;    // requestId -> amount
    mapping(uint256 => uint256) public pendingWithdrawals;  // requestId -> amount
    
    // Request lookup
    mapping(address => uint256[]) public controllerRequests;  // controller -> requestIds
    mapping(address => mapping(address => bool)) public isOperator;

    event RequestCreated(
        uint256 indexed requestId,
        address indexed controller,
        address owner,
        RequestType requestType,
        uint256 amount
    );

    event RequestStateUpdated(
        uint256 indexed requestId,
        RequestState state
    );

    event ValidatorCreated(
        uint256 indexed requestId,
        address indexed controller,
        bytes pubkey,
        uint256 validatorIndex
    );

    constructor(
        address _depositContract,
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(IERC20(_asset)) ERC20(_name, _symbol) {
        require(_depositContract != address(0), "Invalid deposit contract");
        DEPOSIT_CONTRACT = IDepositContract(_depositContract);
    }

    function requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        bytes calldata withdrawalCreds
    ) public payable nonReentrant returns (uint256 requestId) {
        require(owner == msg.sender || isOperator[owner][msg.sender], "Not authorized");
        require(assets == VALIDATOR_DEPOSIT && msg.value == VALIDATOR_DEPOSIT, "Must be 32 ETH");
        require(withdrawalCreds.length == 32, "Invalid withdrawal credentials");
        
        // Create new request
        requestId = nextRequestId++;
        
        Request storage request = requests[requestId];
        request.amount = assets;
        request.owner = owner;
        request.controller = controller;
        request.state = RequestState.Pending;
        request.requestType = RequestType.Deposit;
        
        // Track pending deposit
        pendingDeposits[requestId] = assets;
        
        // Store validator withdrawal credentials
        validators[requestId].withdrawalCreds = withdrawalCreds;
        validators[requestId].requestId = requestId;
        
        // Track controller request
        controllerRequests[controller].push(requestId);
        
        emit RequestCreated(requestId, controller, owner, RequestType.Deposit, assets);
        emit DepositRequest(controller, owner, requestId, msg.sender, assets);
        
        return requestId;
    }

    function processValidatorDeposit(
        uint256 requestId,
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot,
        uint256 validatorIndex
    ) external nonReentrant {
        Request storage request = requests[requestId];
        ValidatorInfo storage validator = validators[requestId];
        
        require(request.state == RequestState.Pending, "Invalid request state");
        require(request.requestType == RequestType.Deposit, "Not a deposit request");
        require(!validator.isActive, "Validator already exists");
        require(pubkey.length == 48 && signature.length == 96, "Invalid key lengths");

        request.state = RequestState.Processing;
        request.validatorIndex = validatorIndex;

        DEPOSIT_CONTRACT.deposit{value: VALIDATOR_DEPOSIT}(
            pubkey,
            validator.withdrawalCreds,
            signature,
            depositDataRoot
        );

        // Update validator info
        validator.pubkey = pubkey;
        validator.signature = signature;
        validator.depositDataRoot = depositDataRoot;
        validator.isActive = true;

        // Update state
        totalAssets += VALIDATOR_DEPOSIT;
        pendingDeposits[requestId] = 0;
        request.state = RequestState.Claimable;

        emit ValidatorCreated(requestId, request.controller, pubkey, validatorIndex);
        emit RequestStateUpdated(requestId, RequestState.Claimable);
    }

    function claimDeposit(uint256 requestId) external nonReentrant {
        Request storage request = requests[requestId];
        require(request.state == RequestState.Claimable, "Not claimable");
        require(request.controller == msg.sender || isOperator[request.controller][msg.sender], "Not authorized");

        request.state = RequestState.Claimed;
        _mint(request.owner, VALIDATOR_DEPOSIT);

        emit Deposit(request.owner, request.controller, VALIDATOR_DEPOSIT, VALIDATOR_DEPOSIT);
    }

    function requestRedeem(
       uint256 shares,
       address controller,
       address owner
   ) public nonReentrant returns (uint256 requestId) {
       require(balanceOf(owner) >= shares, "Insufficient shares");
       
       // Create new request
       requestId = nextRequestId++;
       
       Request storage request = requests[requestId];
       request.amount = shares;
       request.owner = owner;
       request.controller = controller;
       request.state = RequestState.Pending;
       request.requestType = RequestType.Redeem;

       // Handle operator transfers
       address sender = isOperator[owner][msg.sender] ? owner : msg.sender;
       if (sender != owner) {
           uint256 allowed = allowance(owner, sender);
           if (allowed != type(uint256).max) {
               _approve(owner, sender, allowed - shares);
           }
       }

       // Track pending redemption
       pendingWithdrawals[requestId] = shares;
       
       // Track controller request
       controllerRequests[controller].push(requestId);

       // Transfer shares to vault
       _transfer(owner, address(this), shares);

       emit RequestCreated(requestId, controller, owner, RequestType.Redeem, shares);
       emit RedeemRequest(controller, owner, requestId, msg.sender, shares);
       
       return requestId;
   }

   function processRedeem(
       uint256 requestId,
       uint256 exitEpoch
   ) external nonReentrant {
       Request storage request = requests[requestId];
       ValidatorInfo storage validator = validators[request.validatorIndex];
       
       require(request.state == RequestState.Pending, "Invalid request state");
       require(request.requestType == RequestType.Redeem, "Not a redeem request");
       require(validator.isActive, "No active validator");
       require(!validator.isExited, "Already exited");

       uint256 amount = request.amount;

       // Update validator state
       validator.isExited = true;
       validator.exitEpoch = exitEpoch;

       // Update request state
       request.state = RequestState.Claimable;
       totalAssets -= amount;
       pendingWithdrawals[requestId] = amount;

       // Burn shares
       _burn(address(this), amount);

       emit RequestStateUpdated(requestId, RequestState.Claimable);
       emit ValidatorExited(request.validatorIndex, exitEpoch);
   }

   function claimRedeem(uint256 requestId) external nonReentrant {
       Request storage request = requests[requestId];
       
       require(request.state == RequestState.Claimable, "Not claimable");
       require(request.controller == msg.sender || isOperator[request.controller][msg.sender], "Not authorized");
       
       uint256 withdrawAmount = pendingWithdrawals[requestId];
       require(withdrawAmount > 0, "Nothing to claim");

       // Update state
       request.state = RequestState.Claimed;
       pendingWithdrawals[requestId] = 0;

       // Transfer ETH to owner
       (bool success, ) = request.owner.call{value: withdrawAmount}("");
       require(success, "ETH transfer failed");

       emit Withdraw(msg.sender, request.owner, request.controller, withdrawAmount, withdrawAmount);
   }

   function getRequestIds(
       address controller
   ) external view returns (uint256[] memory) {
       return controllerRequests[controller];
   }

   function getRequestState(
       uint256 requestId
   ) external view returns (
       RequestState state,
       RequestType requestType,
       uint256 amount,
       address owner,
       address controller
   ) {
       Request storage request = requests[requestId];
       return (
           request.state,
           request.requestType,
           request.amount,
           request.owner,
           request.controller
       );
   }

   function cancelDepositRequest(
       uint256 requestId,
       address controller
   ) external nonReentrant {
       Request storage request = requests[requestId];
       
       require(request.controller == controller, "Invalid controller");
       require(controller == msg.sender || isOperator[controller][msg.sender], "Not authorized");
       require(request.state == RequestState.Pending, "Not pending");
       require(request.requestType == RequestType.Deposit, "Not a deposit request");

       uint256 refundAmount = pendingDeposits[requestId];
       address refundAddress = request.owner;

       // Update state
       request.state = RequestState.Cancelled;
       pendingDeposits[requestId] = 0;

       // Return ETH to owner
       (bool success, ) = refundAddress.call{value: refundAmount}("");
       require(success, "ETH transfer failed");

       emit RequestStateUpdated(requestId, RequestState.Cancelled);
       emit CancelDepositRequest(controller, requestId, msg.sender);
   }

   function cancelRedeemRequest(
       uint256 requestId,
       address controller
   ) external nonReentrant {
       Request storage request = requests[requestId];
       
       require(request.controller == controller, "Invalid controller");
       require(controller == msg.sender || isOperator[controller][msg.sender], "Not authorized");
       require(request.state == RequestState.Pending, "Not pending");
       require(request.requestType == RequestType.Redeem, "Not a redeem request");

       uint256 shareAmount = request.amount;
       address shareOwner = request.owner;

       // Update state
       request.state = RequestState.Cancelled;
       pendingWithdrawals[requestId] = 0;

       // Return shares to owner
       _transfer(address(this), shareOwner, shareAmount);

       emit RequestStateUpdated(requestId, RequestState.Cancelled);
       emit CancelRedeemRequest(controller, requestId, msg.sender);
   }

   /**
    * @notice Check if request can be cancelled
    * @param requestId Request identifier
    * @return canCancel Whether request is in cancellable state
    */
   function canCancelRequest(
       uint256 requestId
   ) external view returns (bool canCancel) {
       Request storage request = requests[requestId];
       return request.state == RequestState.Pending;
   }

   /**
    * @notice Get cancellable amount for request
    * @param requestId Request identifier
    * @return amount Amount that would be returned on cancel
    */
   function getCancellableAmount(
       uint256 requestId
   ) external view returns (uint256 amount) {
       Request storage request = requests[requestId];
       if (request.state != RequestState.Pending) {
           return 0;
       }
       
       if (request.requestType == RequestType.Deposit) {
           return pendingDeposits[requestId];
       } else {
           return pendingWithdrawals[requestId];
       }
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
    function convertToShares(uint256 assets) public pure override returns (uint256) {
        return assets;
    }

    /**
     * @notice Convert shares to assets (1:1 for ETH staking)
     * @param shares Amount of shares
     * @return assets Equal amount of ETH
     */
    function convertToAssets(uint256 shares) public pure override returns (uint256) {
        return shares;
    }

    /**
     * @notice Maximum deposit allowed (32 ETH if no active validator)
     * @param controller Address to check
     * @return Maximum deposit amount
     */
    function maxDeposit(address controller) public view override returns (uint256) {
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
    function maxMint(address controller) public view override returns (uint256) {
        return maxDeposit(controller);
    }

    /**
     * @notice Maximum withdrawal allowed (full balance if validator exited)
     * @param owner Address to check
     * @return Maximum withdrawal amount
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        ValidatorInfo storage validator = validators[owner];
        return validator.isExited ? balanceOf(owner) : 0;
    }

    /**
     * @notice Maximum redemption allowed (full balance if validator exited)
     * @param owner Address to check
     * @return Maximum redemption amount
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        return maxWithdraw(owner);
    }

    /**
     * @notice Disabled - use requestDeposit for async deposits
     */
    function deposit(uint256, address) public pure override returns (uint256) {
        revert("Use requestDeposit");
    }

    /**
     * @notice Disabled - use requestDeposit for async deposits
     */
    function mint(uint256, address) public pure override returns (uint256) {
        revert("Use requestDeposit");
    }

    /**
     * @notice Disabled - use requestRedeem for async withdrawals
     */
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert("Use requestRedeem");
    }

    /**
     * @notice Disabled - use requestRedeem for async withdrawals
     */
    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert("Use requestRedeem");
    }

    /**
     * @notice Disabled for async vault
     */
    function previewDeposit(uint256) public pure override returns (uint256) {
        revert("Async deposits only");
    }

    /**
     * @notice Disabled for async vault
     */
    function previewMint(uint256) public pure override returns (uint256) {
        revert("Async deposits only");
    }

    /**
     * @notice Disabled for async vault
     */
    function previewWithdraw(uint256) public pure override returns (uint256) {
        revert("Async withdrawals only");
    }

    /**
     * @notice Disabled for async vault
     */
    function previewRedeem(uint256) public pure override returns (uint256) {
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
