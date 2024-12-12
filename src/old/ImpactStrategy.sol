// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
// import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { IProjectRegistry } from "../interfaces/IProjectRegistry.sol";
// /**
//  * @title ImpactStrategy
//  * @author octant, yearn.finance
//  * @notice
//  *  This ImpactStrategy can be used by anyone wishing to easily build
//  *  and deploy their own custom voting strategy.
//  *
//  *  The ImpactStrategy contract is meant to be used as the proxy
//  *  implementation contract that will handle all logic, storage and
//  *  management for a custom strategy that inherits the `BaseImpactStrategy`.
//  *  Any function calls to the strategy that are not defined within that
//  *  strategy will be forwarded through a delegateCall to this contract.
//  *
//  *  This contract implements a 4626-style vault that transforms traditional matching pool
//  *  distribution into a voting system:
//  *  1. Users deposit assets -> receive veTokens (conversion set by strategist)
//  *  2. Users vote with veTokens for projects (vote weight set by strategist)
//  *  3. Projects redeem vault shares for assets based on vote tallies (share calculation set by strategist)
//  *  4. The vault's total assets are distributed to projects proportionally to their shares.
//  *
//  *  A strategist only needs to override a few simple functions that are
//  *  focused entirely on the strategy specific needs to easily and cheaply
//  *  deploy their own permissionless voting strategy.
//  *
//  * This deviates from the standard 4626 vault in that users cannot withdraw the asset once they have deposited.
//  * Instead, users can only use their veToken to decide how the vault's shares are distributed.
//  */
// contract ImpactStrategy {
//     using Math for uint256;
//     using SafeERC20 for ERC20;

//     /*//////////////////////////////////////////////////////////////
//                                  EVENTS
//     //////////////////////////////////////////////////////////////*/
//     /**
//      * @notice Emitted when a strategy is shutdown.
//      */
//     event StrategyShutdown();

//     /**
//      * @notice Emitted on the initialization of any new `strategy` that uses `asset`
//      * with this specific `apiVersion`.
//      */
//     event NewTokenizedStrategy(address indexed strategy, address indexed asset, string apiVersion);

//     /**
//      * @notice Emitted when the strategy reports `profit` or `loss` and
//      * `performanceFees` and `protocolFees` are paid out.
//      */
//     event Reported(uint256 profit, uint256 loss, uint256 protocolFees, uint256 performanceFees);

//     /**
//      * @notice Emitted when the 'keeper' address is updated to 'newKeeper'.
//      */
//     event UpdateKeeper(address indexed newKeeper);

//     /**
//      * @notice Emitted when the 'management' address is updated to 'newManagement'.
//      */
//     event UpdateManagement(address indexed newManagement);

//     /**
//      * @notice Emitted when the 'emergencyAdmin' address is updated to 'newEmergencyAdmin'.
//      */
//     event UpdateEmergencyAdmin(address indexed newEmergencyAdmin);

//     /**
//      * @notice Emitted when the 'pendingManagement' address is updated to 'newPendingManagement'.
//      */
//     event UpdatePendingManagement(address indexed newPendingManagement);

//     /**
//      * @notice Emitted when the allowance of a `spender` for an `owner` is set by
//      * a call to {approve}. `value` is the new allowance.
//      */
//     event Approval(address indexed owner, address indexed spender, uint256 value);

//     /**
//      * @notice Emitted when `value` tokens are moved from one account (`from`) to
//      * another (`to`).
//      *
//      * Note that `value` may be zero.
//      */
//     event Transfer(address indexed from, address indexed to, uint256 value);

//     /**
//      * @notice Emitted when the `caller` has exchanged `assets` for `shares`,
//      * and transferred those `shares` to `owner`.
//      */
//     event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

//     /**
//      * @notice Emitted when the `caller` has exchanged `owner`s `shares` for `assets`,
//      * and transferred those `assets` to `receiver`.
//      */
//     event Withdraw(
//         address indexed caller,
//         address indexed receiver,
//         address indexed owner,
//         uint256 assets,
//         uint256 shares
//     );

//     /*//////////////////////////////////////////////////////////////
//                                CONSTANTS
//     //////////////////////////////////////////////////////////////*/

//     /// @notice API version this TokenizedStrategy implements.
//     string internal constant API_VERSION = "1.0.0";

//     /// @notice Value to set the `entered` flag to during a call.
//     uint8 internal constant ENTERED = 2;
//     /// @notice Value to set the `entered` flag to at the end of the call.
//     uint8 internal constant NOT_ENTERED = 1;

//     /// @notice Used for fee calculations.
//     uint256 internal constant MAX_BPS = 10_000;
//     /// @notice Used for profit unlocking rate calculations.
//     uint256 internal constant MAX_BPS_EXTENDED = 1_000_000_000_000;

//     /// @notice Seconds per year for max profit unlocking time.
//     uint256 internal constant SECONDS_PER_YEAR = 31_556_952; // 365.2425 days


//     /*//////////////////////////////////////////////////////////////
//                         STORAGE STRUCT
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @dev The struct that will hold all the storage data for each strategy
//      * that uses this implementation.
//      *
//      * This replaces all state variables for a traditional contract. This
//      * full struct will be initialized on the creation of the strategy
//      * and continually updated and read from for the life of the contract.
//      *
//      * We combine all the variables into one struct to limit the amount of
//      * times the custom storage slots need to be loaded during complex functions.
//      *
//      * Loading the corresponding storage slot for the struct does not
//      * load any of the contents of the struct into memory. So the size
//      * will not increase memory related gas usage.
//      */
//     // prettier-ignore
//     struct StrategyData {
//         // The ERC20 compliant underlying asset that will be
//         // used by the Strategy
//         ERC20  asset;
//         ERC20Burnable  veToken;
//         address projectRegistry;
//         // These are the corresponding ERC20 variables needed for the
//         // strategies token that is issued and burned on each deposit or withdraw.
//         uint8 decimals; // The amount of decimals that `asset` and strategy use.
//         string name; // The name of the token for the strategy.
//         uint256 totalSupply; // The total amount of shares currently issued.
//         mapping(address => uint256) nonces; // Mapping of nonces used for permit functions.
//         mapping(address => uint256) balances; // Mapping to track current balances for each account that holds shares.
//         mapping(address => mapping(address => uint256)) allowances; // Mapping to track the allowances for the strategies shares.


//         // We manually track `totalAssets` to prevent PPS manipulation through airdrops.
//         uint256 totalAssets;

//         uint96 fullProfitUnlockDate; // The timestamp at which all locked shares will unlock.
//         address keeper; // Address given permission to call {report} and {tend}.
//         uint32 profitMaxUnlockTime; // The amount of seconds that the reported profit unlocks over.
//         // uint16 performanceFee; // The percent in basis points of profit that is charged as a fee.
//         // address performanceFeeRecipient; // The address to pay the `performanceFee` to.
//         // uint96 lastReport; // The last time a {report} was called.


//         // Access management variables.
//         address management; // Main address that can set all configurable variables.
//         address pendingManagement; // Address that is pending to take over `management`.
//         address emergencyAdmin; // Address to act in emergencies as well as `management`.

//         // Strategy Status
//         uint8 entered; // To prevent reentrancy. Use uint8 for gas savings.
//         bool shutdown; // Bool that can be used to stop deposits into the strategy.

//         // Vote tracking
//         mapping(address => uint256) projectVotes;      // Total votes per project
//         mapping(address => mapping(address => uint256)) userVotes;  // Votes per user per project
//         uint256 totalVotesCast;                        // Total votes across all projects
//     }

//     /*//////////////////////////////////////////////////////////////
//                             MODIFIERS
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @dev Require that the call is coming from the strategies management.
//      */
//     modifier onlyManagement() {
//         requireManagement(msg.sender);
//         _;
//     }

//     /**
//      * @dev Require that the call is coming from either the strategies
//      * management or the keeper.
//      */
//     modifier onlyKeepers() {
//         requireKeeperOrManagement(msg.sender);
//         _;
//     }

//     /**
//      * @dev Prevents a contract from calling itself, directly or indirectly.
//      * Placed over all state changing functions for increased safety.
//      */
//     modifier nonReentrant() {
//         StrategyData storage S = _strategyStorage();
//         // On the first call to nonReentrant, `entered` will be false (2)
//         require(S.entered != ENTERED, "ReentrancyGuard: reentrant call");

//         // Any calls to nonReentrant after this point will fail
//         S.entered = ENTERED;

//         _;

//         // Reset to false (1) once call has finished.
//         S.entered = NOT_ENTERED;
//     }

//     /**
//      * @notice Require a caller is `management`.
//      * @dev Is left public so that it can be used by the Strategy.
//      *
//      * When the Strategy calls this the msg.sender would be the
//      * address of the strategy so we need to specify the sender.
//      *
//      * @param _sender The original msg.sender.
//      */
//     function requireManagement(address _sender) public view {
//         require(_sender == _strategyStorage().management, "!management");
//     }

//     /**
//      * @notice Require a caller is the `keeper` or `management`.
//      * @dev Is left public so that it can be used by the Strategy.
//      *
//      * When the Strategy calls this the msg.sender would be the
//      * address of the strategy so we need to specify the sender.
//      *
//      * @param _sender The original msg.sender.
//      */
//     function requireKeeperOrManagement(address _sender) public view {
//         StrategyData storage S = _strategyStorage();
//         require(_sender == S.keeper || _sender == S.management, "!keeper");
//     }

//     /*//////////////////////////////////////////////////////////////
//                                CONSTANTS
//     //////////////////////////////////////////////////////////////*/

//     /// @notice API version this TokenizedStrategy implements.
//     string internal constant API_VERSION = "0.0.1";

//     /// @notice Value to set the `entered` flag to during a call.
//     uint8 internal constant ENTERED = 2;
//     /// @notice Value to set the `entered` flag to at the end of the call.
//     uint8 internal constant NOT_ENTERED = 1;

//     /// @notice Events
//     event Deposit(address indexed user, uint256 assets, uint256 veTokens);
//     event VoteCast(address indexed user, address indexed project, uint256 weight);
//     event SharesAllocated(address indexed project, uint256 shares);
//     event Redeem(address indexed project, uint256 shares, uint256 assets);

//     /**
//      * @dev Custom storage slot that will be used to store the
//      * `StrategyData` struct that holds each strategies
//      * specific storage variables.
//      *
//      * Any storage updates done by the TokenizedStrategy actually update
//      * the storage of the calling contract. This variable points
//      * to the specific location that will be used to store the
//      * struct that holds all that data.
//      *
//      * We use a custom string in order to get a random
//      * storage slot that will allow for strategists to use any
//      * amount of storage in their strategy without worrying
//      * about collisions.
//      */
//     bytes32 internal constant BASE_IMPACT_STRATEGY_STORAGE =
//         bytes32(uint256(keccak256("octant.base.impact.strategy.storage")) - 1);

//     /*//////////////////////////////////////////////////////////////
//                             STORAGE GETTER
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @dev will return the actual storage slot where the strategy
//      * specific `StrategyData` struct is stored for both read
//      * and write operations.
//      *
//      * This loads just the slot location, not the full struct
//      * so it can be used in a gas efficient manner.
//      */
//     function _strategyStorage() internal pure returns (StrategyData storage S) {
//         // Since STORAGE_SLOT is a constant, we have to put a variable
//         // on the stack to access it from an inline assembly block.
//         bytes32 slot = BASE_IMPACT_STRATEGY_STORAGE;
//         assembly {
//             S.slot := slot
//         }
//     }

//     /*//////////////////////////////////////////////////////////////
//                           INITIALIZATION
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Used to initialize storage for a newly deployed strategy.
//      * @dev This should be called atomically whenever a new strategy is
//      * deployed and can only be called once for each strategy.
//      *
//      * This will set all the default storage that must be set for a
//      * strategy to function. Any changes can be made post deployment
//      * through external calls from `management`.
//      *
//      * The function will also emit an event that off chain indexers can
//      * look for to track any new deployments using this TokenizedStrategy.
//      *
//      * @param _asset Address of the underlying asset.
//      * @param _name Name the strategy will use.
//      * @param _management Address to set as the strategies `management`.
//      * @param _performanceFeeRecipient Address to receive performance fees.
//      * @param _keeper Address to set as strategies `keeper`.
//      */
//     function initialize(
//         address _asset,
//         string memory _name,
//         address _management,
//         address _projectRegistry,
//         address _keeper
//     ) external {
//         // Cache storage pointer.
//         StrategyData storage S = _strategyStorage();

//         // Make sure we aren't initialized.
//         require(address(S.asset) == address(0), "initialized");

//         // Set the strategy's underlying asset.
//         S.asset = ERC20(_asset);
//         // Set the Strategy Tokens name.
//         S.name = _name;
//         // Set decimals based off the `asset`.
//         S.decimals = ERC20(_asset).decimals();

//         // Default to a 10 day profit unlock period.
//         S.profitMaxUnlockTime = 10 days;

//         // Set the default management address. Can't be 0.
//         require(_management != address(0), "ZERO ADDRESS");
//         S.management = _management;
//         // Set the keeper address
//         S.keeper = _keeper;
//         // Set the project registry address
//         S.projectRegistry = _projectRegistry;

//         // Emit event to signal a new strategy has been initialized.
//         emit NewTokenizedStrategy(address(this), _asset, API_VERSION);
//     }

//     /**
//      * @notice Core deposit logic that mints veTokens to receiver
//      * @dev Handles asset transfer and veToken minting
//      * @param S Storage pointer to strategy data
//      * @param receiver Address to receive the veTokens
//      * @param assets Amount of assets to deposit
//      * @return veTokenAmount Amount of veTokens received
//      */
//     function _deposit(
//         StrategyData storage S,
//         address receiver,
//         uint256 assets
//     ) internal returns (uint256 veTokenAmount) {
//         // Check sybil resistance
//         // (bool passedCheck, ) = checkSybilResistance(receiver);
//         // require(passedCheck, "!sybil");

//         // Transfer assets to vault
//         S.asset.safeTransferFrom(msg.sender, address(this), assets);
//         S.totalAssets += assets;

//         // Mint veTokens (lockTime = 0 for now, can be updated later)
//         // veTokenAmount = _calculateVeTokens(assets, receiver, block.timestamp);
//         // S.veToken.mint(receiver, veTokenAmount);

//         emit Deposit(receiver, assets, veTokenAmount);
//         return veTokenAmount;
//     }

//     /*//////////////////////////////////////////////////////////////
//                             DEPLOYMENT
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @dev On contract creation we set `asset` for this contract to address(1).
//      * This prevents it from ever being initialized in the future.
//      */
//     constructor() {
//         _strategyStorage().asset = ERC20(address(1));
//     }

//     /**
//      * @notice Gets the total votes for a project
//      * @dev Includes vote decay logic if implemented by strategy
//      * @param _project Address of the project to get votes for
//      * @return totalVotes Current valid vote count for the project
//      */
//     function _getVoteTally(address _project) internal view returns (uint256 totalVotes) {
//         StrategyData storage S = _strategyStorage();

//         // Get raw vote count
//         totalVotes = S.projectVotes[_project];

//         return totalVotes;
//     }

//     /**
//      * @notice Adjusts vote tally based on strategy rules
//      * @dev Virtual function that can be overridden to implement vote decay or other adjustments
//      * Default implementation returns unmodified tally
//      * @param _project Project address to adjust votes for
//      * @param _rawTally The raw vote count before adjustments
//      * @return The adjusted vote tally
//      */
//     function adjustVoteTally(address _project, uint256 _rawTally) public view virtual returns (uint256) {
//         return _rawTally;
//     }

//     /**
//      * @notice Gets user's votes for a specific project
//      * @param _user Address of the voter
//      * @param _project Address of the project
//      * @return votes Number of votes from user to project
//      */
//     function getUserVotes(address _user, address _project) external view returns (uint256) {
//         return _strategyStorage().userVotes[_user][_project];
//     }

//     /**
//      * @notice Gets total votes for a project
//      * @param _project Address of the project
//      * @return votes Total number of votes for project
//      */
//     function getProjectVotes(address _project) external view returns (uint256) {
//         return _getVoteTally(_project);
//     }

//     /**
//      * @notice Gets total votes cast in the strategy
//      * @return votes Total number of votes cast
//      */
//     function getTotalVotes() external view returns (uint256) {
//         return _strategyStorage().totalVotesCast;
//     }

//     /**
//      * @notice Calculates shares to be allocated to a project based on their vote tally
//      * @dev Converts vote weight into proportional share allocation
//      * Default implementation uses linear proportion of total votes
//      * Strategists can override for custom allocation formulas (e.g. quadratic)
//      *
//      * @param _project Address of the project
//      * @param _owner Project registry ID
//      * @return shares Amount of shares to be allocated
//      */
//     function _calculateShares(address _project, address _owner) internal view returns (uint256 shares) {
//         StrategyData storage S = _strategyStorage();

//         // Get adjusted vote tally for this project
//         uint256 projectVotes = _getVoteTally(_project);

//         // No shares if no votes
//         if (projectVotes == 0 || S.totalVotesCast == 0) {
//             return 0;
//         }

//         // Calculate shares based on proportion of total votes
//         shares = (S.veToken.totalSupply() * projectVotes) / S.totalVotesCast;

//         return shares;
//     }

//     /**
//      * @notice Allows strategies to implement custom share allocation formulas
//      * @dev Virtual function that can be overridden to implement custom allocation logic
//      * Default implementation returns proportional allocation
//      * @param _project Project address
//      * @param _baseShares Linearly calculated share amount
//      * @param _projectVotes Project's vote tally
//      * @param _totalVotes Total votes cast
//      * @return The adjusted share allocation
//      */
//     function adjustShareAllocation(
//         address _project,
//         uint256 _baseShares,
//         uint256 _projectVotes,
//         uint256 _totalVotes
//     ) public view virtual onlyManagement returns (uint256) {
//         return _baseShares;
//     }

//     /*//////////////////////////////////////////////////////////////
//                       ERC4626 WRITE METHODS
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Deposits assets and mints veTokens to receiver
//      * @param assets Amount of underlying to deposit
//      * @param receiver Address to receive the veTokens
//      * @return veTokenAmount Amount of veTokens minted
//      */
//     function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 veTokenAmount) {
//         StrategyData storage S = _strategyStorage();
//         require(!S.shutdown, "shutdown");

//         // Handle max uint deposit
//         if (assets == type(uint256).max) {
//             assets = S.asset.balanceOf(msg.sender);
//         }

//         require(assets > 0, "zero assets");

//         return _deposit(S, receiver, assets);
//     }

//     /*//////////////////////////////////////////////////////////////
//                             VOTING LOGIC
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Cast votes for a project by burning veTokens
//      * @dev veTokens are burned permanently on voting
//      * Votes cannot be changed or withdrawn once cast
//      * @param _project Address of project to vote for
//      * @param _amount Amount of veTokens to vote with
//      */
//     function vote(address _project, uint256 _amount) external nonReentrant {
//         StrategyData storage S = _strategyStorage();
//         require(!S.shutdown, "shutdown");
//         require(_project != address(0), "invalid project");
//         require(IProjectRegistry(S.projectRegistry).isRegistered(_project), "!registered");

//         // Check veToken balance
//         uint256 veTokenBalance = S.veToken.balanceOf(msg.sender);
//         require(_amount <= veTokenBalance, "insufficient veTokens");
//         require(_amount > 0, "zero vote");

//         // Burn veTokens
//         _burnVeTokens(S, msg.sender, _amount);

//         // Record vote
//         _recordVote(S, msg.sender, _project, _amount);

//         emit VoteCast(msg.sender, _project, _amount);
//     }

//     /**
//      * @notice Burns veTokens from voter
//      * @param S Storage pointer
//      * @param _voter Address of voter
//      * @param _amount Amount of veTokens to burn
//      */
//     function _burnVeTokens(StrategyData storage S, address _voter, uint256 _amount) internal {
//         S.veToken.burnFrom(_voter, _amount);
//     }

//     /**
//      * @notice Records a vote in storage
//      * @param S Storage pointer
//      * @param _voter Address of voter
//      * @param _project Address of project
//      * @param _amount Amount of veTokens voted
//      */
//     function _recordVote(StrategyData storage S, address _voter, address _project, uint256 _amount) internal {
//         // Record the permanent vote
//         S.userVotes[_voter][_project] += _amount;
//         S.projectVotes[_project] += _amount;
//         S.totalVotesCast += _amount;
//     }

//     /**
//      * @notice Redeems exactly `shares` from `owner` and
//      * sends `assets` of underlying tokens to `receiver`.
//      * @dev This will default to allowing any loss passed to be realized.
//      * @param shares The amount of shares burnt.
//      * @param receiver The address to receive `assets`.
//      * @param owner The address whose shares are burnt.
//      * @return assets The actual amount of underlying withdrawn.
//      */
//     function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
//         // We default to not limiting a potential loss.
//         return redeem(shares, receiver, owner, MAX_BPS);
//     }

//     /**
//      * @notice Redeems shares for a project based on their vote tally and sends underlying assets to receiver
//      * @dev Only registered projects can redeem shares. Share amount is calculated from vote tally.
//      * @param shares The amount of shares to redeem
//      * @param receiver The address to receive the underlying assets
//      * @param owner The project address redeeming shares
//      * @param maxLoss The maximum acceptable loss in basis points
//      * @return The actual amount of underlying assets withdrawn
//      */
//     function redeem(
//         uint256 shares,
//         address receiver,
//         address owner, // project address
//         uint256 maxLoss
//     ) public nonReentrant returns (uint256) {
//         // Get the storage slot
//         StrategyData storage S = _strategyStorage();

//         // Verify owner is a registered project
//         require(IProjectRegistry(S.projectRegistry).isRegistered(owner), "Not a registered project");

//         // Calculate shares based on vote tally
//         uint256 voteTally = _getVoteTally(owner);
//         uint256 availableShares = _calculateShares( owner, owner);

//         require(shares <= availableShares, "Exceeds available shares");
//         require(shares <= _maxRedeem(S, owner), "Exceeds max redeem");

//         uint256 assets;
//         require((assets = _convertToAssets(S, shares, Math.Rounding.Floor)) != 0, "ZERO_ASSETS");

//         return _withdraw(S, receiver, owner, assets, shares, maxLoss);
//     }
//     /*//////////////////////////////////////////////////////////////
//                     INTERNAL 4626 WRITE METHODS
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @dev Function to be called during {deposit} and {mint}.
//      *
//      * This function handles all logic including transfers,
//      * minting and accounting.
//      *
//      * We do all external calls before updating any internal
//      * values to prevent view reentrancy issues from the token
//      * transfers or the _deployFunds() calls.
//      */
//     function _deposit(StrategyData storage S, address receiver, uint256 assets, uint256 shares) internal {
//         // Cache storage variables used more than once.
//         ERC20 _asset = S.asset;

//         // take the funds
//         _asset.safeTransferFrom(msg.sender, address(this), assets);

//         // Adjust total Assets.
//         S.totalAssets += assets;

//         // mint shares
//         _mint(S, receiver, shares);

//         emit Deposit(msg.sender, receiver, assets, shares);
//     }

//     /**
//      * @dev To be called during {redeem} and {withdraw}.
//      *
//      * This will handle all logic, transfers and accounting
//      * in order to service the withdraw request.
//      *
//      * If we are not able to withdraw the full amount needed, it will
//      * be counted as a loss and passed on to the user.
//      */
//     function _withdraw(
//         StrategyData storage S,
//         address receiver,
//         address owner,
//         uint256 assets,
//         uint256 shares,
//         uint256 maxLoss
//     ) internal virtual returns (uint256) {
//         require(receiver != address(0), "ZERO ADDRESS");
        
//         // Spend allowance if applicable.
//         if (msg.sender != owner) {
//             _spendAllowance(S, owner, msg.sender, shares);
//         }

//         // Cache `asset` since it is used multiple times..
//         ERC20 _asset = S.asset;

//         // Update assets based on how much we took.
//         S.totalAssets -= (assets);

//         _burn(S, owner, shares);

       
//         _asset.safeTransfer(receiver, assets);
   

//         emit Withdraw(msg.sender, receiver, owner, assets, shares);

//         // Return the actual amount of assets withdrawn.
//         return assets;
//     }

//     /*//////////////////////////////////////////////////////////////
//                     EXTERNAL 4626 VIEW METHODS
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Get the total amount of assets this strategy holds
//      * as of the last report.
//      *
//      * We manually track `totalAssets` to avoid any PPS manipulation.
//      *
//      * @return . Total assets the strategy holds.
//      */
//     function totalAssets() external view returns (uint256) {
//         return _totalAssets(_strategyStorage());
//     }

//     /**
//      * @notice Get the current supply of the strategies shares.
//      *
//      * Locked shares issued to the strategy from profits are not
//      * counted towards the full supply until they are unlocked.
//      *
//      * As more shares slowly unlock the totalSupply will decrease
//      * causing the PPS of the strategy to increase.
//      *
//      * @return . Total amount of shares outstanding.
//      */
//     function totalSupply() external view returns (uint256) {
//         return _totalSupply(_strategyStorage());
//     }

//     /*//////////////////////////////////////////////////////////////
//                     INTERNAL 4626 VIEW METHODS
//     //////////////////////////////////////////////////////////////*/

//     /// @dev Internal implementation of {totalAssets}.
//     function _totalAssets(StrategyData storage S) internal view returns (uint256) {
//         return S.totalAssets;
//     }

//     /// @dev Internal implementation of {totalSupply}.
//     function _totalSupply(StrategyData storage S) internal view returns (uint256) {
//         return S.totalSupply;
//     }

//     /// @dev Internal implementation of {maxDeposit}.
//     function _maxDeposit(StrategyData storage S, address receiver) internal view returns (uint256) {
//         // Cannot deposit when shutdown or to the strategy.
//         if (S.shutdown || receiver == address(this)) return 0;

//         //return IBaseStrategy(address(this)).availableDepositLimit(receiver);
//         return type(uint256).max;
//     }

//     /// @dev Internal implementation of {maxMint}.
//     function _maxMint(StrategyData storage S, address receiver) internal view returns (uint256 maxMint_) {
//         // Cannot mint when shutdown or to the strategy.
//         if (S.shutdown || receiver == address(this)) return 0;

//         //maxMint_ = IBaseStrategy(address(this)).availableDepositLimit(receiver);
//         if (maxMint_ != type(uint256).max) {
//             maxMint_ = _convertToShares(S, maxMint_, Math.Rounding.Down);
//         }
//     }

//     /// @dev Internal implementation of {maxRedeem}.
//     function _maxRedeem(StrategyData storage S, address owner) internal view returns (uint256 maxRedeem_) {
//         // Get the max the owner could withdraw currently.
//         // maxRedeem_ = IBaseStrategy(address(this)).availableWithdrawLimit(owner);

//         // Conversion would overflow and saves a min check if there is no withdrawal limit.
//         if (maxRedeem_ == type(uint256).max) {
//             maxRedeem_ = _balanceOf(S, owner);
//         } else {
//             maxRedeem_ = Math.min(
//                 // Can't redeem more than the balance.
//                 _convertToShares(S, maxRedeem_, Math.Rounding.Down),
//                 _balanceOf(S, owner)
//             );
//         }
//     }

//     /*//////////////////////////////////////////////////////////////
//                     EXTERNAL 4626 VIEW METHODS
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Get the total amount of assets this strategy holds
//      * as of the last report.
//      *
//      * We manually track `totalAssets` to avoid any PPS manipulation.
//      *
//      * @return . Total assets the strategy holds.
//      */
//     function totalAssets() external view returns (uint256) {
//         return _totalAssets(_strategyStorage());
//     }

//     /**
//      * @notice Get the current supply of the strategies shares.
//      *
//      * Locked shares issued to the strategy from profits are not
//      * counted towards the full supply until they are unlocked.
//      *
//      * As more shares slowly unlock the totalSupply will decrease
//      * causing the PPS of the strategy to increase.
//      *
//      * @return . Total amount of shares outstanding.
//      */
//     function totalSupply() external view returns (uint256) {
//         return _totalSupply(_strategyStorage());
//     }

//     /**
//      * @notice The amount of shares that the strategy would
//      *  exchange for the amount of assets provided, in an
//      * ideal scenario where all the conditions are met.
//      *
//      * @param assets The amount of underlying.
//      * @return . Expected shares that `assets` represents.
//      */
//     function convertToShares(uint256 assets) external view returns (uint256) {
//         return _convertToShares(_strategyStorage(), assets, Math.Rounding.Floor);
//     }

//     /**
//      * @notice The amount of assets that the strategy would
//      * exchange for the amount of shares provided, in an
//      * ideal scenario where all the conditions are met.
//      *
//      * @param shares The amount of the strategies shares.
//      * @return . Expected amount of `asset` the shares represents.
//      */
//     function convertToAssets(uint256 shares) external view returns (uint256) {
//         return _convertToAssets(_strategyStorage(), shares, Math.Rounding.Floor);
//     }

//     /**
//      * @notice Allows an on-chain or off-chain user to simulate
//      * the effects of their deposit at the current block, given
//      * current on-chain conditions.
//      * @dev This will round down.
//      *
//      * @param assets The amount of `asset` to deposits.
//      * @return . Expected shares that would be issued.
//      */
//     function previewDeposit(uint256 assets) external view returns (uint256) {
//         return _convertToShares(_strategyStorage(), assets, Math.Rounding.Floor);
//     }

//     /**
//      * @notice Allows an on-chain or off-chain user to simulate
//      * the effects of their mint at the current block, given
//      * current on-chain conditions.
//      * @dev This is used instead of convertToAssets so that it can
//      * round up for safer mints.
//      *
//      * @param shares The amount of shares to mint.
//      * @return . The needed amount of `asset` for the mint.
//      */
//     function previewMint(uint256 shares) external view returns (uint256) {
//         return _convertToAssets(_strategyStorage(), shares, Math.Rounding.Ceil);
//     }

//     /**
//      * @notice Allows an on-chain or off-chain user to simulate
//      * the effects of their withdrawal at the current block,
//      * given current on-chain conditions.
//      * @dev This is used instead of convertToShares so that it can
//      * round up for safer withdraws.
//      *
//      * @param assets The amount of `asset` that would be withdrawn.
//      * @return . The amount of shares that would be burnt.
//      */
//     function previewWithdraw(uint256 assets) external view returns (uint256) {
//         return _convertToShares(_strategyStorage(), assets, Math.Rounding.Ceil);
//     }

//     /**
//      * @notice Allows an on-chain or off-chain user to simulate
//      * the effects of their redemption at the current block,
//      * given current on-chain conditions.
//      * @dev This will round down.
//      *
//      * @param shares The amount of shares that would be redeemed.
//      * @return . The amount of `asset` that would be returned.
//      */
//     function previewRedeem(uint256 shares) external view returns (uint256) {
//         return _convertToAssets(_strategyStorage(), shares, Math.Rounding.Floor);
//     }

//     /**
//      * @notice Total number of underlying assets that can
//      * be deposited into the strategy, where `receiver`
//      * corresponds to the receiver of the shares of a {deposit} call.
//      *
//      * @param receiver The address receiving the shares.
//      * @return . The max that `receiver` can deposit in `asset`.
//      */
//     function maxDeposit(address receiver) external view returns (uint256) {
//         return _maxDeposit(_strategyStorage(), receiver);
//     }

//     /**
//      * @notice Total number of shares that can be minted to `receiver`
//      * of a {mint} call.
//      *
//      * @param receiver The address receiving the shares.
//      * @return _maxMint The max that `receiver` can mint in shares.
//      */
//     function maxMint(address receiver) external view returns (uint256) {
//         return _maxMint(_strategyStorage(), receiver);
//     }

//     /**
//      * @notice Total number of underlying assets that can be
//      * withdrawn from the strategy by `owner`, where `owner`
//      * corresponds to the msg.sender of a {redeem} call.
//      *
//      * @param owner The owner of the shares.
//      * @return _maxWithdraw Max amount of `asset` that can be withdrawn.
//      */
//     function maxWithdraw(address owner) external view virtual returns (uint256) {
//         return _maxWithdraw(_strategyStorage(), owner);
//     }

//     /**
//      * @notice Variable `maxLoss` is ignored.
//      * @dev Accepts a `maxLoss` variable in order to match the multi
//      * strategy vaults ABI.
//      */
//     function maxWithdraw(address owner, uint256 /*maxLoss*/) external view virtual returns (uint256) {
//         return _maxWithdraw(_strategyStorage(), owner);
//     }

//     /**
//      * @notice Total number of strategy shares that can be
//      * redeemed from the strategy by `owner`, where `owner`
//      * corresponds to the msg.sender of a {redeem} call.
//      *
//      * @param owner The owner of the shares.
//      * @return _maxRedeem Max amount of shares that can be redeemed.
//      */
//     function maxRedeem(address owner) external view virtual returns (uint256) {
//         return _maxRedeem(_strategyStorage(), owner);
//     }

//     /**
//      * @notice Variable `maxLoss` is ignored.
//      * @dev Accepts a `maxLoss` variable in order to match the multi
//      * strategy vaults ABI.
//      */
//     function maxRedeem(address owner, uint256 /*maxLoss*/) external view virtual returns (uint256) {
//         return _maxRedeem(_strategyStorage(), owner);
//     }

//     /*//////////////////////////////////////////////////////////////
//                     INTERNAL 4626 VIEW METHODS
//     //////////////////////////////////////////////////////////////*/

//     /// @dev Internal implementation of {totalAssets}.
//     function _totalAssets(StrategyData storage S) internal view returns (uint256) {
//         return S.totalAssets;
//     }

//     /// @dev Internal implementation of {totalSupply}.
//     function _totalSupply(StrategyData storage S) internal view returns (uint256) {
//         return S.totalSupply;
//     }

//     /// @dev Internal implementation of {convertToShares}.
//     function _convertToShares(
//         StrategyData storage S,
//         uint256 assets,
//         Math.Rounding _rounding
//     ) internal view returns (uint256) {
//         // Saves an extra SLOAD if values are non-zero.
//         uint256 totalSupply_ = _totalSupply(S);
//         // If supply is 0, PPS = 1.
//         if (totalSupply_ == 0) return assets;

//         uint256 totalAssets_ = _totalAssets(S);
//         // If assets are 0 but supply is not PPS = 0.
//         if (totalAssets_ == 0) return 0;

//         return assets.mulDiv(totalSupply_, totalAssets_, _rounding);
//     }

//     /// @dev Internal implementation of {convertToAssets}.
//     function _convertToAssets(
//         StrategyData storage S,
//         uint256 shares,
//         Math.Rounding _rounding
//     ) internal view returns (uint256) {
//         // Saves an extra SLOAD if totalSupply() is non-zero.
//         uint256 supply = _totalSupply(S);

//         return supply == 0 ? shares : shares.mulDiv(_totalAssets(S), supply, _rounding);
//     }

//     /// @dev Internal implementation of {maxDeposit}.
//     /// @param S Storage pointer to the strategy's data
//     /// @param receiver The address that will receive the deposit
//     /// @return The maximum amount of assets that can be deposited
//     function _maxDeposit(StrategyData storage S, address receiver) internal view returns (uint256) {
//         // Cannot deposit when shutdown or to the strategy itself
//         if (S.shutdown || receiver == address(this)) return 0;

//         // Return max uint256 since base contract will handle actual deposit limits
//         return type(uint256).max;
//     }

//     /// @dev Internal implementation of {maxMint}.
//     function _maxMint(StrategyData storage S, address receiver) internal view virtual returns (uint256 maxMint_) {
//         // Cannot mint when shutdown or to the strategy.
//         if (S.shutdown || receiver == address(this)) return 0;

//         // maxMint_ = IBaseStrategy(address(this)).availableDepositLimit(receiver);
//         if (maxMint_ != type(uint256).max) {
//             maxMint_ = _convertToShares(S, maxMint_, Math.Rounding.Floor);
//         }
//     }

//     /// @dev Internal implementation of {maxWithdraw}.
//     function _maxWithdraw(StrategyData storage S, address owner) internal view virtual returns (uint256 maxWithdraw_) {
//         // Get the max the owner could withdraw currently.
//         // maxWithdraw_ = IBaseStrategy(address(this)).availableWithdrawLimit(owner);

//         // If there is no limit enforced.
//         if (maxWithdraw_ == type(uint256).max) {
//             // Saves a min check if there is no withdrawal limit.
//             maxWithdraw_ = _convertToAssets(S, _balanceOf(S, owner), Math.Rounding.Floor);
//         } else {
//             maxWithdraw_ = Math.min(_convertToAssets(S, _balanceOf(S, owner), Math.Rounding.Floor), maxWithdraw_);
//         }
//     }

//     /// @dev Internal implementation of {maxRedeem}.
//     function _maxRedeem(StrategyData storage S, address owner) internal view virtual returns (uint256 maxRedeem_) {
//         // Get the max the owner could withdraw currently.
//         //maxRedeem_ = IBaseStrategy(address(this)).availableWithdrawLimit(owner);

//         // Conversion would overflow and saves a min check if there is no withdrawal limit.
//         if (maxRedeem_ == type(uint256).max) {
//             maxRedeem_ = _balanceOf(S, owner);
//         } else {
//             maxRedeem_ = Math.min(
//                 // Can't redeem more than the balance.
//                 _convertToShares(S, maxRedeem_, Math.Rounding.Floor),
//                 _balanceOf(S, owner)
//             );
//         }
//     }
//     /*//////////////////////////////////////////////////////////////
//                         GETTER FUNCTIONS
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Get the underlying asset for the strategy.
//      * @return . The underlying asset.
//      */
//     function asset() external view returns (address) {
//         return address(_strategyStorage().asset);
//     }

//     /**
//      * @notice Get the API version for this TokenizedStrategy.
//      * @return . The API version for this TokenizedStrategy
//      */
//     function apiVersion() external pure returns (string memory) {
//         return API_VERSION;
//     }

//     /**
//      * @notice Get the current address that controls the strategy.
//      * @return . Address of management
//      */
//     function management() external view returns (address) {
//         return _strategyStorage().management;
//     }

//     /**
//      * @notice Get the current pending management address if any.
//      * @return . Address of pendingManagement
//      */
//     function pendingManagement() external view returns (address) {
//         return _strategyStorage().pendingManagement;
//     }

//     /**
//      * @notice Get the current address that can call tend and report.
//      * @return . Address of the keeper
//      */
//     function keeper() external view returns (address) {
//         return _strategyStorage().keeper;
//     }

//     /**
//      * @notice Get the current address that can shutdown and emergency withdraw.
//      * @return . Address of the emergencyAdmin
//      */
//     function emergencyAdmin() external view returns (address) {
//         return _strategyStorage().emergencyAdmin;
//     }

//     /**
//      * @notice Get the current performance fee charged on profits.
//      * denominated in Basis Points where 10_000 == 100%
//      * @return . Current performance fee.
//      */
//     function performanceFee() external view returns (uint16) {
//         return _strategyStorage().performanceFee;
//     }

//     /**
//      * @notice Get the current address that receives the performance fees.
//      * @return . Address of performanceFeeRecipient
//      */
//     function performanceFeeRecipient() external view returns (address) {
//         return _strategyStorage().performanceFeeRecipient;
//     }

//     /**
//      * @notice Gets the timestamp at which all profits will be unlocked.
//      * @return . The full profit unlocking timestamp
//      */
//     function fullProfitUnlockDate() external view returns (uint256) {
//         return uint256(_strategyStorage().fullProfitUnlockDate);
//     }

//     /**
//      * @notice The per second rate at which profits are unlocking.
//      * @dev This is denominated in EXTENDED_BPS decimals.
//      * @return . The current profit unlocking rate.
//      */
//     function profitUnlockingRate() external view returns (uint256) {
//         return _strategyStorage().profitUnlockingRate;
//     }

//     /**
//      * @notice Gets the current time profits are set to unlock over.
//      * @return . The current profit max unlock time.
//      */
//     function profitMaxUnlockTime() external view returns (uint256) {
//         return _strategyStorage().profitMaxUnlockTime;
//     }

//     /*//////////////////////////////////////////////////////////////
//                         SETTER FUNCTIONS
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Step one of two to set a new address to be in charge of the strategy.
//      * @dev Can only be called by the current `management`. The address is
//      * set to pending management and will then have to call {acceptManagement}
//      * in order for the 'management' to officially change.
//      *
//      * Cannot set `management` to address(0).
//      *
//      * @param _management New address to set `pendingManagement` to.
//      */
//     function setPendingManagement(address _management) external onlyManagement {
//         require(_management != address(0), "ZERO ADDRESS");
//         _strategyStorage().pendingManagement = _management;

//         emit UpdatePendingManagement(_management);
//     }

//     /**
//      * @notice Step two of two to set a new 'management' of the strategy.
//      * @dev Can only be called by the current `pendingManagement`.
//      */
//     function acceptManagement() external {
//         StrategyData storage S = _strategyStorage();
//         require(msg.sender == S.pendingManagement, "!pending");
//         S.management = msg.sender;
//         S.pendingManagement = address(0);

//         emit UpdateManagement(msg.sender);
//     }

//     /**
//      * @notice Sets a new address to be in charge of tend and reports.
//      * @dev Can only be called by the current `management`.
//      *
//      * @param _keeper New address to set `keeper` to.
//      */
//     function setKeeper(address _keeper) external onlyManagement {
//         _strategyStorage().keeper = _keeper;

//         emit UpdateKeeper(_keeper);
//     }

//     /**
//      * @notice Sets a new address to be able to shutdown the strategy.
//      * @dev Can only be called by the current `management`.
//      *
//      * @param _emergencyAdmin New address to set `emergencyAdmin` to.
//      */
//     function setEmergencyAdmin(address _emergencyAdmin) external onlyManagement {
//         _strategyStorage().emergencyAdmin = _emergencyAdmin;

//         emit UpdateEmergencyAdmin(_emergencyAdmin);
//     }

//     /**
//      * @notice Updates the name for the strategy.
//      * @param _name The new name for the strategy.
//      */
//     function setName(string calldata _name) external onlyManagement {
//         _strategyStorage().name = _name;
//     }

//     /*//////////////////////////////////////////////////////////////
//                         ERC20 METHODS
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Returns the name of the token.
//      * @return . The name the strategy is using for its token.
//      */
//     function name() external view returns (string memory) {
//         return _strategyStorage().name;
//     }

//     /**
//      * @notice Returns the symbol of the strategies token.
//      * @dev Will be 'ys + asset symbol'.
//      * @return . The symbol the strategy is using for its tokens.
//      */
//     function symbol() external view returns (string memory) {
//         return string(abi.encodePacked("ys", _strategyStorage().asset.symbol()));
//     }

//     /**
//      * @notice Returns the number of decimals used to get its user representation.
//      * @return . The decimals used for the strategy and `asset`.
//      */
//     function decimals() external view returns (uint8) {
//         return _strategyStorage().decimals;
//     }

//     /**
//      * @notice Returns the current balance for a given '_account'.
//      * @dev If the '_account` is the strategy then this will subtract
//      * the amount of shares that have been unlocked since the last profit first.
//      * @param account the address to return the balance for.
//      * @return . The current balance in y shares of the '_account'.
//      */
//     function balanceOf(address account) external view returns (uint256) {
//         return _balanceOf(_strategyStorage(), account);
//     }

//     /// @dev Internal implementation of {balanceOf}.
//     function _balanceOf(StrategyData storage S, address account) internal view returns (uint256) {
//         if (account == address(this)) {
//             return S.balances[account];
//         }
//         return S.balances[account];
//     }

//     /**
//      * @notice Transfer '_amount` of shares from `msg.sender` to `to`.
//      * @dev
//      * Requirements:
//      *
//      * - `to` cannot be the zero address.
//      * - `to` cannot be the address of the strategy.
//      * - the caller must have a balance of at least `_amount`.
//      *
//      * @param to The address shares will be transferred to.
//      * @param amount The amount of shares to be transferred from sender.
//      * @return . a boolean value indicating whether the operation succeeded.
//      */
//     function transfer(address to, uint256 amount) external returns (bool) {
//         _transfer(_strategyStorage(), msg.sender, to, amount);
//         return true;
//     }

//     /**
//      * @notice Returns the remaining number of tokens that `spender` will be
//      * allowed to spend on behalf of `owner` through {transferFrom}. This is
//      * zero by default.
//      *
//      * This value changes when {approve} or {transferFrom} are called.
//      * @param owner The address who owns the shares.
//      * @param spender The address who would be moving the owners shares.
//      * @return . The remaining amount of shares of `owner` that could be moved by `spender`.
//      */
//     function allowance(address owner, address spender) external view returns (uint256) {
//         return _allowance(_strategyStorage(), owner, spender);
//     }

//     /// @dev Internal implementation of {allowance}.
//     function _allowance(StrategyData storage S, address owner, address spender) internal view returns (uint256) {
//         return S.allowances[owner][spender];
//     }

//     /**
//      * @notice Sets `amount` as the allowance of `spender` over the caller's tokens.
//      * @dev
//      *
//      * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
//      * `transferFrom`. This is semantically equivalent to an infinite approval.
//      *
//      * Requirements:
//      *
//      * - `spender` cannot be the zero address.
//      *
//      * IMPORTANT: Beware that changing an allowance with this method brings the risk
//      * that someone may use both the old and the new allowance by unfortunate
//      * transaction ordering. One possible solution to mitigate this race
//      * condition is to first reduce the spender's allowance to 0 and set the
//      * desired value afterwards:
//      * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
//      *
//      * Emits an {Approval} event.
//      *
//      * @param spender the address to allow the shares to be moved by.
//      * @param amount the amount of shares to allow `spender` to move.
//      * @return . a boolean value indicating whether the operation succeeded.
//      */
//     function approve(address spender, uint256 amount) external returns (bool) {
//         _approve(_strategyStorage(), msg.sender, spender, amount);
//         return true;
//     }

//     /**
//      * @notice `amount` tokens from `from` to `to` using the
//      * allowance mechanism. `amount` is then deducted from the caller's
//      * allowance.
//      *
//      * @dev
//      * Emits an {Approval} event indicating the updated allowance. This is not
//      * required by the EIP.
//      *
//      * NOTE: Does not update the allowance if the current allowance
//      * is the maximum `uint256`.
//      *
//      * Requirements:
//      *
//      * - `from` and `to` cannot be the zero address.
//      * - `to` cannot be the address of the strategy.
//      * - `from` must have a balance of at least `amount`.
//      * - the caller must have allowance for ``from``'s tokens of at least
//      * `amount`.
//      *
//      * Emits a {Transfer} event.
//      *
//      * @param from the address to be moving shares from.
//      * @param to the address to be moving shares to.
//      * @param amount the quantity of shares to move.
//      * @return . a boolean value indicating whether the operation succeeded.
//      */
//     function transferFrom(address from, address to, uint256 amount) external returns (bool) {
//         StrategyData storage S = _strategyStorage();
//         _spendAllowance(S, from, msg.sender, amount);
//         _transfer(S, from, to, amount);
//         return true;
//     }

//     /**
//      * @dev Moves `amount` of tokens from `from` to `to`.
//      *
//      * This internal function is equivalent to {transfer}, and can be used to
//      * e.g. implement automatic token fees, slashing mechanisms, etc.
//      *
//      * Emits a {Transfer} event.
//      *
//      * Requirements:
//      *
//      * - `from` cannot be the zero address.
//      * - `to` cannot be the zero address.
//      * - `to` cannot be the strategies address
//      * - `from` must have a balance of at least `amount`.
//      *
//      */
//     function _transfer(StrategyData storage S, address from, address to, uint256 amount) internal {
//         require(from != address(0), "ERC20: transfer from the zero address");
//         require(to != address(0), "ERC20: transfer to the zero address");
//         require(to != address(this), "ERC20 transfer to strategy");

//         S.balances[from] -= amount;
//         unchecked {
//             S.balances[to] += amount;
//         }

//         emit Transfer(from, to, amount);
//     }

//     /** @dev Creates `amount` tokens and assigns them to `account`, increasing
//      * the total supply.
//      *
//      * Emits a {Transfer} event with `from` set to the zero address.
//      *
//      * Requirements:
//      *
//      * - `account` cannot be the zero address.
//      *
//      */
//     function _mint(StrategyData storage S, address account, uint256 amount) internal {
//         require(account != address(0), "ERC20: mint to the zero address");

//         S.totalSupply += amount;
//         unchecked {
//             S.balances[account] += amount;
//         }
//         emit Transfer(address(0), account, amount);
//     }

//     /**
//      * @dev Destroys `amount` tokens from `account`, reducing the
//      * total supply.
//      *
//      * Emits a {Transfer} event with `to` set to the zero address.
//      *
//      * Requirements:
//      *
//      * - `account` cannot be the zero address.
//      * - `account` must have at least `amount` tokens.
//      */
//     function _burn(StrategyData storage S, address account, uint256 amount) internal {
//         require(account != address(0), "ERC20: burn from the zero address");

//         S.balances[account] -= amount;
//         unchecked {
//             S.totalSupply -= amount;
//         }
//         emit Transfer(account, address(0), amount);
//     }

//     /**
//      * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
//      *
//      * This internal function is equivalent to `approve`, and can be used to
//      * e.g. set automatic allowances for certain subsystems, etc.
//      *
//      * Emits an {Approval} event.
//      *
//      * Requirements:
//      *
//      * - `owner` cannot be the zero address.
//      * - `spender` cannot be the zero address.
//      */
//     function _approve(StrategyData storage S, address owner, address spender, uint256 amount) internal {
//         require(owner != address(0), "ERC20: approve from the zero address");
//         require(spender != address(0), "ERC20: approve to the zero address");

//         S.allowances[owner][spender] = amount;
//         emit Approval(owner, spender, amount);
//     }

//     /**
//      * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
//      *
//      * Does not update the allowance amount in case of infinite allowance.
//      * Revert if not enough allowance is available.
//      *
//      * Might emit an {Approval} event.
//      */
//     function _spendAllowance(StrategyData storage S, address owner, address spender, uint256 amount) internal {
//         uint256 currentAllowance = _allowance(S, owner, spender);
//         if (currentAllowance != type(uint256).max) {
//             require(currentAllowance >= amount, "ERC20: insufficient allowance");
//             unchecked {
//                 _approve(S, owner, spender, currentAllowance - amount);
//             }
//         }
//     }

//     /*//////////////////////////////////////////////////////////////
//                             EIP-2612 LOGIC
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Returns the current nonce for `owner`. This value must be
//      * included whenever a signature is generated for {permit}.
//      *
//      * @dev Every successful call to {permit} increases ``owner``'s nonce by one. This
//      * prevents a signature from being used multiple times.
//      *
//      * @param _owner the address of the account to return the nonce for.
//      * @return . the current nonce for the account.
//      */
//     function nonces(address _owner) external view returns (uint256) {
//         return _strategyStorage().nonces[_owner];
//     }

//     /**
//      * @notice Sets `value` as the allowance of `spender` over ``owner``'s tokens,
//      * given ``owner``'s signed approval.
//      *
//      * @dev IMPORTANT: The same issues {ERC20-approve} has related to transaction
//      * ordering also apply here.
//      *
//      * Emits an {Approval} event.
//      *
//      * Requirements:
//      *
//      * - `spender` cannot be the zero address.
//      * - `deadline` must be a timestamp in the future.
//      * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
//      * over the EIP712-formatted function arguments.
//      * - the signature must use ``owner``'s current nonce (see {nonces}).
//      *
//      * For more information on the signature format, see the
//      * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
//      * section].
//      */
//     function permit(
//         address owner,
//         address spender,
//         uint256 value,
//         uint256 deadline,
//         uint8 v,
//         bytes32 r,
//         bytes32 s
//     ) external {
//         require(deadline >= block.timestamp, "ERC20: PERMIT_DEADLINE_EXPIRED");

//         // Unchecked because the only math done is incrementing
//         // the owner's nonce which cannot realistically overflow.
//         unchecked {
//             address recoveredAddress = ecrecover(
//                 keccak256(
//                     abi.encodePacked(
//                         "\x19\x01",
//                         DOMAIN_SEPARATOR(),
//                         keccak256(
//                             abi.encode(
//                                 keccak256(
//                                     "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
//                                 ),
//                                 owner,
//                                 spender,
//                                 value,
//                                 _strategyStorage().nonces[owner]++,
//                                 deadline
//                             )
//                         )
//                     )
//                 ),
//                 v,
//                 r,
//                 s
//             );

//             require(recoveredAddress != address(0) && recoveredAddress == owner, "ERC20: INVALID_SIGNER");

//             _approve(_strategyStorage(), recoveredAddress, spender, value);
//         }
//     }

//     /**
//      * @notice Returns the domain separator used in the encoding of the signature
//      * for {permit}, as defined by {EIP712}.
//      *
//      * @return . The domain separator that will be used for any {permit} calls.
//      */
//     function DOMAIN_SEPARATOR() public view returns (bytes32) {
//         return
//             keccak256(
//                 abi.encode(
//                     keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
//                     keccak256("Impact Strategy"),
//                     keccak256(bytes(API_VERSION)),
//                     block.chainid,
//                     address(this)
//                 )
//             );
//     }

//     /*//////////////////////////////////////////////////////////////
//                             DEPLOYMENT
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @dev On contract creation we set `asset` for this contract to address(1).
//      * This prevents it from ever being initialized in the future.
//      */
//     constructor() {
//         _strategyStorage().asset = ERC20(address(1));
//     }

//     /**
//      * @notice Adjusts vote tally based on strategy rules
//      * @dev Virtual function that can be overridden to implement vote decay or other adjustments
//      * Default implementation returns unmodified tally
//      * @param _project Project address to adjust votes for
//      * @param _rawTally The raw vote count before adjustments
//      * @return The adjusted vote tally
//      */
//     function adjustVoteTally(address _project, uint256 _rawTally) public view virtual returns (uint256) {
//         return _rawTally;
//     }

//     /**
//      * @notice Gets user's votes for a specific project
//      * @param _user Address of the voter
//      * @param _project Address of the project
//      * @return votes Number of votes from user to project
//      */
//     function getUserVotes(address _user, address _project) external view returns (uint256) {
//         return _strategyStorage().userVotes[_user][_project];
//     }

//     /**
//      * @notice Gets total votes for a project
//      * @param _project Address of the project
//      * @return votes Total number of votes for project
//      */
//     function getProjectVotes(address _project) external view returns (uint256) {
//         return _getVoteTally(_project);
//     }

//     /**
//      * @notice Gets total votes cast in the strategy
//      * @return votes Total number of votes cast
//      */
//     function getTotalVotes() external view returns (uint256) {
//         return _strategyStorage().totalVotesCast;
//     }
// }
