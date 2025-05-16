# TokenizedImpactStrategy.sol

# High-Level Overview

YearnTokenizedImpactStrategy is a specialized implementation of Yearn's TokenizedStrategy that enables different types of funding for impact projects. It combines ERC4626-compliant tokenized vault functionality with voting mechanics to allow depositors to allocate their voting power to different impact projects.

The contract's architecture separates three key concerns:
1. Asset management (inherited from TokenizedStrategy)
2. Voting power allocation (unique to an implementation)
3. Share distribution (immutable once finalized)

# Functionality Breakdown

The contract implements a two-phase system: deposit/voting phase and redemption phase.

1. **Deposit and Voting System**:
   - Users deposit assets and receive voting power proportional to their deposit
   - Voting power can be used to support projects through the implemented voting strategy
   - Votes are processed and tracked until tally finalization
   - Security measures prevent double voting and ensure proper vote weight calculation
 vfr4
2. **Share Distribution System**:
   - After voting period ends, management finalizes the tally
   - Project shares are calculated based on the voting tally and implemented strategy
   - Projects can redeem their share only after tally finalization
   - Prevents early withdrawals and gaming of the system

3. **Asset Management System**:
   - Tracks total assets and voting power separately
   - Prevents transfers of shares (_transfer is disabled)
   - Maintains balance accounting through deposits and withdrawals
   - Integrates with Yearn's strategy system

## Contract Summary

The contract provides the following main functions:

- `initialize(address,string,address,address,address)`: Sets up the strategy with initial parameters
- `deposit(uint256,address)`: Deposits assets and grants voting power
- `vote(uint256,uint256,uint256)`: Processes votes for projects
- `redeem(uint256,address,address)`: Allows withdrawal after tally finalization
- `finalizeTally(uint256)`: Finalizes voting and enables redemptions
- `projectTally(uint256)`: Returns current funding metrics for a project
- `projectRegistry()`: Returns current project registry address
- `setProjectRegistry(address)`: Updates project registry address
- `balanceOf(address)`: Returns combined balance including project shares

## Inherited Contracts

- **[TokenizedStrategy](./TokenizedStrategy.sol)**: Base implementation of Yearn's tokenized vault strategy
   - Provides pseudo-ERC4626 compliant vault functionality
   - Handles asset custody and accounting
   - Implements access control and emergency procedures
   - Core functions are overridden to add voting mechanics

## Security Analysis

### Storage Layout

The contract inherits storage layout from TokenizedStrategy and adds:
```solidity
struct StrategyData {
        ERC20 asset;
        mapping(address => uint256) votingPower; // Mapping of voting power for each account
        uint256 totalVotingPower; // Total voting power for the strategy
        uint256 finalizedTotalShares; // Total shares after the tally is finalized
        bool finalizedTally; // Flag to indicate if the tally is finalized
        mapping(address => bool) claimedShares; // Mapping of claims for each project

        uint8 decimals; // The amount of decimals that `asset` and strategy use.
        string name; // The name of the token for the strategy.
        uint256 totalSupply; // The total amount of shares currently issued.
        mapping(address => uint256) nonces; // Mapping of nonces used for permit functions.
        mapping(address => uint256) balances; // Mapping to track current balances for each account that holds shares.
        mapping(address => mapping(address => uint256)) allowances; // Mapping to track the allowances for the strategies shares.

        uint256 totalAssets;
        address projectRegistry;

        address keeper; // Address given custom permissions
        address management; // Main address that can set all configurable variables.
        address pendingManagement; // Address that is pending to take over `management`.
        address emergencyAdmin; // Address to act in emergencies as well as `management`.

        // Strategy Status
        uint8 entered; // To prevent reentrancy. Use uint8 for gas savings.
        bool shutdown; // Bool that can be used to stop deposits into the strategy.
    }
```

## Constants

- `MAX_BPS = 10_000`: Basis points constant for percentage calculations
- `ENTERED = 2`: Reentrancy guard entered state
- `NOT_ENTERED = 1`: Reentrancy guard not entered state

## Possible Attack Vectors

1. **Voting Manipulation**:
   - Front-running votes
   - Vote splitting across multiple addresses
   - Manipulation of vote weights
   - Flash loan attacks during voting
   - Project registry manipulation

2. **Withdrawal Gaming**:
   - Timing attacks around tally finalization (?)
   - Sandwich attacks on withdrawals
   - Price manipulation attempts

3. **Access Control Exploitation**:
   - Management role compromise
   - Keeper role abuse in vote processing
   - Project registry updates to malicious contract

## Potential Risks

1. Centralization Risks:
   - Management controls tally finalization
   - Project registry controls project validation
   - Keeper role for vote processing

2. Smart Contract Vulnerabilities:
   - Complex share calculation logic
   - Potential rounding errors in vote weight calculations (add decimal offset?)
   - State transition vulnerabilities between voting and redemption phases

3. Integration Risks:
   - Dependency on external project registry

## Security Analysis

### Method: initialize
Initializes the strategy with core parameters and settings.
```solidity
1  function initialize(
2      address _asset,
3      string memory _name, 
4      address _management,
5      address _projectRegistry,
6      address _keeper
7  ) external {
8      StrategyData storage S = _strategyStorage();
9      require(address(S.asset) == address(0), "initialized");
10    
11    S.asset = ERC20(_asset);
12    S.name = _name;
13    S.decimals = ERC20(_asset).decimals();
14
15    require(_projectRegistry != address(0), "ZERO ADDRESS");
16    require(_projectRegistry != address(this), "self");
17    S.projectRegistry = _projectRegistry;
18
19    require(_management != address(0), "ZERO ADDRESS");
20    S.management = _management;
21    S.keeper = _keeper;
22
23    emit NewTokenizedStrategy(address(this), _asset, API_VERSION);
24 }
```
1-6. External function that can only be called once to initialize the strategy.
7-8. Ensures the strategy hasn't been initialized before.
9-11. Sets up basic token parameters (asset, name, decimals).
13-15. Validates and sets project registry with zero-address and self-reference checks.
17-19. Sets up management and keeper roles with zero-address validation.
21. Emits initialization event.

### Method: deposit
```solidity
1  function deposit(
2      uint256 assets,
3      address receiver
4  ) external nonReentrant returns (uint256 votes) {
5      StrategyData storage S = _strategyStorage();
6      
7      if (assets == type(uint256).max) {
8          assets = S.asset.balanceOf(msg.sender);
9      }
10     
11     require(assets <= _maxDeposit(S, receiver), "ERC4626: deposit more than max");
12     require((votes = IBaseImpactStrategy(address(this)).convertToVotes(assets)) != 0, "ZERO_SHARES");
13 
14     _deposit(S, receiver, assets, votes);
15 }
```
1-4. External nonReentrant function handling deposits and returning voting power.
7-9. Handles max uint deposit case by using entire balance.
11. Validates deposit amount against maximum allowed.
12. Converts assets to votes, ensuring non-zero result.
14. Processes deposit and assigns voting power.

### Method: vote
Processes votes for projects and deducts voting power.
```solidity
1  function vote(
2      uint256 projectId,
3      uint256 contribution,
4      uint256 voteWeight
5  ) external nonReentrant {
6      StrategyData storage S = _strategyStorage();
7      IBaseImpactStrategy(address(this)).processVote(
8          projectId,
9          contribution,
10         voteWeight
11     );
12     _removeVotingPower(S, msg.sender, contribution);
13 }
```
1-5. External nonreentrant function for processing votes with project ID, contribution amount, and vote weight.
6. Loads strategy storage.
7-11. Delegates vote processing to the base impact strategy implementation.
12. Deducts used voting power from the sender's balance.

### Method: redeem
Allows projects to redeem 
```solidity
1  function redeem(
2      uint256 shares,
3      address receiver,
4      address owner
5  ) external returns (uint256) {
6      StrategyData storage S = _strategyStorage();
7      require(shares <= _maxRedeem(S, owner), "ERC4626: redeem more than max");
8      
9      uint256 assets;
10     require((assets = _convertToAssets(S, shares, Math.Rounding.Floor)) != 0, "ZERO_ASSETS");
11 
12     return _withdraw(S, receiver, owner, assets, shares, MAX_BPS);
13 }
```
1-5. External function allowing share redemption for assets.
6. Loads strategy storage.
7. Validates redemption amount against maximum allowed for the owner.
9-10. Converts shares to assets using floor rounding, ensures non-zero assets.
12. Processes withdrawal and returns asset amount.

### Method: finalizeTally
```solidity
1  function finalizeTally(uint256 totalShares) external onlyManagement {
2      uint256 finalizedTotalShares = IBaseImpactStrategy(address(this)).finalize(totalShares);
3      _strategyStorage().finalizedTotalShares = totalShares;
4      _strategyStorage().finalizedTally = true;
5  }
```
1. External management-only function to finalize voting tally with total shares parameter.
2. Calls base strategy to finalize votes and calculate total shares.
3. Updates storage with finalized share total.
4. Sets finalization flag in storage.

### Method: projectTally
```solidity
1  function projectTally(uint256 projectId) external view returns (uint256 projectShares, uint256 totalShares) {
2      return IBaseImpactStrategy(address(this)).tally(projectId);
3  }
```
1. External view function to query project tally information.
2. Delegates to base strategy to retrieve project shares and total shares.

### Method: setProjectRegistry
```solidity
1  function setProjectRegistry(address _projectRegistry) external onlyManagement {
2      require(_projectRegistry != address(0), "ZERO ADDRESS");
3      require(_projectRegistry != address(this), "Cannot be self");
4      _strategyStorage().projectRegistry = _projectRegistry;
5      emit UpdateProjectRegistry(_projectRegistry);
6  }
```
1. External management-only function to update project registry.
2. Validates new registry address against zero address.
3. Validates registry address is not self-referential.
4. Updates storage with new registry address.
5. Emits event for registry update.