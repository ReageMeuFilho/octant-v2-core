# Base Strategy

## High-Level Overview

DragonBaseStrategy is a foundational abstract contract for implementing yield-generating strategies in a tokenized format. It inherits from BaseStrategy and implements a proxy pattern using delegatecall to interact with a contract that implements the TokenizedStrategy interface. This architecture enables multiple strategies to share core logic while keeping strategy-specific implementations separate.

This contract should be inherited by a specific strategy. It implements all of the required functionality to seamlessly integrate with the `TokenizedStrategy` implementation contract allowing anyone to easily build a fully permissionless ERC-4626 compliant Vault by inheriting this contract and overriding four simple functions.

It utilizes an immutable proxy pattern that allows the BaseStrategy to remain simple and small. All standard logic is held within the
`TokenizedStrategy` and is reused over any n strategies all using the `fallback` function to delegatecall the implementation so that strategists can only be concerned with writing their strategy specific code.

This contract should be inherited and the four main abstract methods `_deployFunds`, `_freeFunds`, `_harvestAndReport` and `liquidatePosition` implemented to adapt the Strategy to the particular needs it has to generate yield. There are
other optional methods that can be implemented to further customize
the strategy if desired.

All default storage for the strategy is controlled and updated by the
`TokenizedStrategy`. The implementation holds a storage struct that
contains all needed global variables in a manual storage slot. This
means strategists can feel free to implement their own custom storage
variables as they need with no concern of collisions. All global variables
can be viewed within the Strategy by a simple call using the
`TokenizedStrategy` variable. IE: TokenizedStrategy.globalVariable();.

## Smart Contract Flow Diagram:

![Base Strategy Flow Diagram](../../../assets/base-strategy-flow.svg)

## Functionality Breakdown

### Proxy Implementation Architecture:

- Uses delegatecall pattern to forward calls to a shared TokenizedStrategy implementation
- Maintains separation between core logic and strategy-specific code
- Implements a fallback function to handle all standard operations
- Uses assembly for efficient delegatecall operations

### Strategy Management:

- Provides initialization framework for new strategies
- Implements access control through modifiers
- Handles ETH and token operations safely

## Inherited Contracts

BaseStrategy: Provides the core framework for tokenized strategy implementation
- Implements fundamental strategy functionality
- Defines access control modifiers
- Specifies required virtual functions for strategy implementation

## Security Analysis

### Storage Layout 

Key storage variables:
```solidity
address public tokenizedStrategyImplementation;
uint256 public maxReportDelay;
address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
```

The storage layout is carefully managed to avoid collisions with the TokenizedStrategy implementation through the use of delegatecall.

### Critical Function Analysis

### Method: __BaseStrategy_init

This function initializes the strategy configuration and sets up the proxy pattern for delegating calls to the TokenizedStrategy implementation.

```solidity
 1  function __BaseStrategy_init(
 2      address _tokenizedStrategyImplementation,
 3      address _asset,
 4      address _owner,
 5      address _management,
 6      address _keeper,
 7      address _dragonRouter,
 8      uint256 _maxReportDelay,
 9      string memory _name,
10      address _regenGovernance
11  ) internal {
12      tokenizedStrategyImplementation = _tokenizedStrategyImplementation;
13      asset = ERC20(_asset);
14      maxReportDelay = _maxReportDelay;
15  
16      TokenizedStrategy = ITokenizedStrategy(address(this));
17  
18      _delegateCall(
19          abi.encodeCall(ITokenizedStrategy.initialize, (_asset, _name, _owner, _management, _keeper, _dragonRouter, _regenGovernance))
20      );
21  
22      assembly ("memory-safe") {
23          sstore(
24              0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
25              _tokenizedStrategyImplementation
26          )
27      }
28  }
```

1-11. Function declaration with all necessary parameters for strategy initialization. The function is marked `internal` to ensure it can only be called during contract creation.

12-14. Sets the core immutable strategy parameters:
- Stores the implementation contract address
- Sets the asset token address
- Configures the maximum delay between reports

16. Creates an instance of ITokenizedStrategy pointing to this contract (used for delegatecall operations)

18-20. Performs a delegatecall to initialize the TokenizedStrategy implementation:
- Encodes the initialization call with all required parameters
- Executes the delegatecall via the _delegateCall helper function

22-27. Uses assembly to store the implementation address in a specific storage slot:
- Uses memory-safe assembly tag
- Storage slot is the standard EIP-1967 implementation slot (keccak256('eip1967.proxy.implementation') - 1)
- This storage is used by block explorers to identify the implementation contract

### Method: fallback

This function acts as a proxy to forward any unmatched function calls to the TokenizedStrategy implementation using delegatecall. It handles both the forwarding of calls and proper return of data.

```solidity
 1  fallback() external payable {
 2      assembly ("memory-safe") {
 3          if and(iszero(calldatasize()), not(iszero(callvalue()))) {
 4              return(0, 0)
 5          }
 6      }
 7      address _tokenizedStrategyAddress = tokenizedStrategyImplementation;
 8      assembly ("memory-safe") {
 9          calldatacopy(0, 0, calldatasize())
10          let result := delegatecall(
11              gas(),
12              _tokenizedStrategyAddress,
13              0,
14              calldatasize(),
15              0,
16              0
17          )
18          returndatacopy(0, 0, returndatasize())
19          switch result
20          case 0 {
21              revert(0, returndatasize())
22          }
23          default {
24              return(0, returndatasize())
25          }
26      }
27  }
```

1. Fallback function declaration marked as `external payable` to handle all incoming calls and ETH transfers.

2-6. First assembly block handles direct ETH transfers:
- `iszero(calldatasize())` checks if there's no calldata
- `not(iszero(callvalue()))` checks if ETH was sent
- If it's a direct ETH transfer with no calldata, returns immediately
- This prevents ETH transfers from failing while still handling function calls

7. Loads the implementation address from storage outside of assembly for better readability and safety.

8-26. Main assembly block handles the delegatecall:
   - Line 9: Copies the incoming calldata to memory starting at position 0
   - Lines 10-17: Executes the delegatecall with the following parameters:
     * Forwards all available gas
     * Calls the implementation address
     * Uses memory position 0 for input
     * Forwards the entire calldata size
     * Initially allocates no memory for output (will be handled by returndatacopy)
   - Line 18: Copies the return data to memory
   - Lines 19-25: Handles the delegatecall result:
     * If result is 0 (failure), reverts with the error data
     * If successful, returns the output data

Security considerations:
- Uses "memory-safe" assembly tag to enforce memory safety
- Properly handles both successful and failed delegatecalls
- Correctly manages memory for both input and output data
- Handles direct ETH transfers
- No storage manipulation in assembly blocks

### Method: harvestTrigger

This external view function determines whether a harvest operation should be triggered based on time elapsed and idle funds available.

```solidity
 1  function harvestTrigger() external view virtual returns (bool) {
 2      // Should not trigger if strategy is not active (no assets) or harvest has been recently called.
 3      if (
 4          TokenizedStrategy.totalAssets() != 0 && 
 5          (block.timestamp - TokenizedStrategy.lastReport()) >= maxReportDelay
 6      ) return true;
 7  
 8      // Check for idle funds in the strategy and deposit in the farm.
 9      return (
10          address(asset) == ETH ? 
11          address(this).balance : 
12          asset.balanceOf(address(this))
13      ) > 0;
14  }
```

1. Function declaration:
   - Marked as `external view` as it doesn't modify state
   - `virtual` allows child contracts to override the harvest trigger logic

3-6. First trigger condition:
   - Line 4: Checks if the strategy has any assets under management
   - Line 5: Verifies if enough time has passed since the last report using `maxReportDelay`
   - Returns true if both conditions are met to trigger a harvest

9-13. Second trigger condition:
   - Checks for any idle funds in the strategy
   - Line 10-12: Handles both ETH and ERC20 tokens:
     * For ETH: checks contract's ETH balance
     * For ERC20: checks token balance using balanceOf
   - Returns true if any idle funds are available


# Possible Attack Vectors

## Proxy Pattern Vulnerabilities

1. **Implementation Contract Manipulation**
- Risk: If the implementation address verification is insufficient during initialization, an attacker could potentially set up a malicious implementation
- Impact: Complete control over strategy functionality and assets
- Mitigation: Implementation address is immutable after initialization and should be thoroughly verified

2. **Storage Collision Attacks**
- Risk: Malicious implementation could try to manipulate storage layout to overwrite critical variables
- Impact: Could overwrite important state variables
- Mitigation: Storage layout for added variables is carefully managed through delegatecall pattern and standard proxy slots

## Timing Attacks

2. **Front-running Opportunities**
- Risk: MEV bots could front-run harvest calls
- Impact: Extract value from rebalancing or harvesting operations
- Mitigation: Implement keeper networks or private mempool solutions

## Access Control Exploits

2. **Management Role Abuse**
- Risk: Compromised management account could manipulate strategy parameters
- Impact: Modify critical parameters or drain funds
- Mitigation: Use 5/9 multi-sig controls the role

## Technical Vulnerabilities

2. **Delegate Call Chains**
- Risk: Complex delegate call chains could lead to unexpected behavior
- Impact: State inconsistency or failed operations
- Mitigation: Careful testing of all delegate call paths


### Recommendations

1. High Priority:


2. Medium Priority:

3. Low Priority:
- Initialization parameter sanity checks: validate the address is a contract, etc.
- Hard coded implementation address: rather than passing in as a parameter, to avoid man-in-the-middle attacks
