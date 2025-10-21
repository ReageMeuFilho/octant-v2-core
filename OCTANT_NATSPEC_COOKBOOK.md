# OCTANT NATSPEC COOKBOOK
**Proven Recipes for Excellent Smart Contract Documentation**

Version: 2.0 | Last Updated: 2025-10-15 | Security: security@golem.foundation

---

## Core Principles

```
✓ Self-documenting code FIRST (clear names, simple logic)
✓ Document the WHY, not the WHAT (code shows what)
✓ Less is more: brief, accurate, no redundancy
✓ Units specified for ALL numeric values
✓ NatSpec for ALL public/external functions
✓ Security implications documented
✓ Zero TODO/FIXME in production
✓ No unnecessary blank lines in NatSpec blocks
```

**Communication Rule**: Attention is scarce. Every word must earn its place.

---

## Brevity & Clarity

**AVOID over-documentation:**

❌ **DON'T document the obvious:**
```solidity
/// @param deployer The address of the deployer  // Parameter name says this!
/// @notice Sets msg.sender as factory owner      // Constructor code shows this!
```

✅ **DO document the non-obvious:**
```solidity
/// @param alpha Weighting factor (dimensionless ratio, 0 to denominator)
/// @notice Finalizes state; callable once per epoch
```

**Single-line format for simple cases:**
```solidity
// Good (enums, simple events):
/// @notice Can add strategies via addStrategy()
ADD_STRATEGY_MANAGER,

/// @notice Emitted when blockset is updated
event BlocksetAssigned(IAddressSet indexed blockset);
```

**Multi-line ONLY when complexity demands it:**
```solidity
/**
 * @notice Deploys mechanism with quadratic funding
 * @dev Uses CREATE2 for deterministic addresses
 *      Reverts if mechanism with same params exists
 * @param config Mechanism parameters (see AllocationConfig)
 * @param alphaNumerator QF weighting (dimensionless, 0 to denominator)
 * @return mechanism Address of deployed contract
 * @custom:security Caller becomes owner with admin privileges
 */
```

**No blank lines between tags:**
```solidity
// BAD (wastes space):
/**
 * @notice Does something
 * @dev Technical details
 *
 * @param input Description     // ← Unnecessary blank line
 * @return output Description
 */

// GOOD (compact):
/**
 * @notice Does something
 * @dev Technical details
 * @param input Description
 * @return output Description
 */
```

---

## Quick Reference

| Tag | Use | Required | Example |
|-----|-----|----------|---------|
| `@title` | Contract name | YES | `@title YourContract` |
| `@author` | Attribution | YES | `@author [Golem Foundation](https://golem.foundation)` |
| `@custom:security-contact` | Security email | YES | `@custom:security-contact security@golem.foundation` |
| `@notice` | User-facing description | YES | `@notice Deposits assets and mints shares` |
| `@dev` | Technical details | Recommended | `@dev Uses ERC4626 standard with...` |
| `@param` | Parameter (with units!) | YES | `@param amount Amount in asset base units (e.g., 1e18 for 1.0 token)` |
| `@return` | Return value (named + units) | YES if returns | `@return shares Minted shares in 18 decimals` |
| `@inheritdoc` | Inherit docs | Use for overrides | `@inheritdoc IYourInterface` |
| `@custom:security` | Security note | For privileged/risky | `@custom:security Only callable by management` |

---

## THE PERFECTION CHECKLIST

**Use this checklist to achieve 100% source-to-doc match with zero empty cells.**

This recipe comes from perfecting `LinearAllowanceSingleton` through iterative `forge doc` review.

### Rule 1: Document EVERY Parameter (No Exceptions)

❌ **NEVER** skip @param even if it seems obvious  
✅ **ALWAYS** provide minimal but complete descriptions

**Why**: `forge doc` generates parameter tables. Empty cells look broken and unprofessional.

```solidity
// ❌ BAD - Creates empty cells
/// @notice Emitted when allowance is set
/// @param dripRatePerDay Drip rate per day
event AllowanceSet(address indexed source, address indexed delegate, address indexed token, uint192 dripRatePerDay);

// ✅ GOOD - Complete table
/// @notice Emitted when allowance is set
/// @param source Safe that owns the allowance
/// @param delegate Authorized spender
/// @param token Token being allowed  
/// @param dripRatePerDay Drip rate in token base units per day
event AllowanceSet(address indexed source, address indexed delegate, address indexed token, uint192 dripRatePerDay);
```

### Rule 2: Parameter Names Must Match Between Interface and Implementation

❌ **BAD** - Inconsistent naming:
```solidity
// Interface
function execute(address source, address token) external;

// Implementation  
function execute(address safe, address token) external {
    // Now needs extra @param to explain renaming - adds confusion
}
```

✅ **GOOD** - Consistent naming:
```solidity
// Interface
function execute(address source, address token) external;

// Implementation
function execute(address source, address token) external {
    // Can use @inheritdoc cleanly
}
```

### Rule 3: Returns Without Named Variables

When function signature doesn't name the return variable, **DO NOT** include variable name in @return.

❌ **BAD**:
```solidity
/// @return amount Amount transferred in token base units
function transfer() external returns (uint256);
```
**Generates**: `|<none>|uint256|amount Amount transferred in token base units|` ← Awkward!

✅ **GOOD**:
```solidity
/// @return Amount transferred in token base units
function transfer() external returns (uint256);
```
**Generates**: `|<none>|uint256|Amount transferred in token base units|` ← Clean!

### Rule 4: Units MUST Be Specified

For ALL numeric parameters and returns, specify units:

```solidity
/// @param amount Transfer amount in token base units
/// @param duration Lock duration in seconds
/// @param bps Fee in basis points (1 bps = 0.01%)
/// @param ratio Dimensionless ratio (0 to denominator)
/// @return shares Shares minted in 18 decimals
```

### Rule 5: Special Values MUST Be Documented

```solidity
/// @param token Use NATIVE_TOKEN for ETH, otherwise ERC20 address
/// @param amount Use type(uint256).max for full balance
/// @param recipient Use address(0) to burn
```

### Rule 6: @inheritdoc Usage

✅ **DO** use @inheritdoc for functions that fully inherit documentation:
```solidity
/// @inheritdoc IMyInterface
function myFunction(uint256 param) external override {
    // No need to repeat @param, @return, etc.
}
```

❌ **DON'T** add conflicting @param when using @inheritdoc:
```solidity
/// @inheritdoc IMyInterface
/// @param param The parameter  ← Redundant! Already in interface
function myFunction(uint256 param) external override {
}
```

### Rule 7: Event Parameters Need Full Documentation Too

Events are **NOT** exempt from the "document everything" rule.

❌ **BAD**:
```solidity
/// @notice User deposited tokens
event Deposited(address indexed user, uint256 amount);
```
**Generates empty cells for `user`!**

✅ **GOOD**:
```solidity
/// @notice User deposited tokens  
/// @param user Account that deposited
/// @param amount Deposit amount in token base units
event Deposited(address indexed user, uint256 amount);
```

### Rule 8: Batch Function Consistency

Document batch/array functions the same as single-item functions:

```solidity
/// @notice Execute multiple transfers in a single transaction
/// @param recipients Recipient addresses
/// @param amounts Transfer amounts in token base units
/// @param tokens Token addresses (use NATIVE_TOKEN for ETH)
/// @return results Transfer results for each operation
function batchTransfer(
    address[] calldata recipients,
    uint256[] calldata amounts,
    address[] calldata tokens
) external returns (bool[] memory results);
```

### Rule 9: Verify With `forge doc`

After documenting, **ALWAYS**:

1. Run `forge doc` to generate markdown
2. Check for empty table cells: `grep "||$" docs/src/**/*.md`
3. Review generated docs match source intent
4. Fix issues and regenerate

### Rule 10: No Inline Comments on Declarations

❌ **BAD** - Pollutes generated code blocks:
```solidity
mapping(address => uint256) public balances; // user -> balance
```

✅ **GOOD** - Use @dev:
```solidity
/// @notice Mapping of user balances
/// @dev Structure: user address → balance amount
mapping(address => uint256) public balances;
```

## Licensing

**Octant Licensing Policy:**

✓ **MIT License** - Default for all original Octant code  
✓ **Inherit License** - When extending/forking existing licensed code, use original license

**Examples:**

```solidity
// Original Octant code:
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Extending AGPL-3.0 code:
// SPDX-License-Identifier: AGPL-3.0
// This contract extends [Original Contract] by [Original Author]
// Original code licensed under AGPL-3.0
pragma solidity ^0.8.25;
```

**When inheriting licenses, document the original:**
```solidity
// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from IAccessControlledEarningPowerCalculator by [Golem Foundation](https://golem.foundation)
// IAccessControlledEarningPowerCalculator is licensed under AGPL-3.0-only.
// Users of this contract should ensure compliance with the AGPL-3.0-only license terms.
```

---

## Contract Template

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ContractName
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Brief user-facing description (1-2 sentences)
 * @dev Technical details: architecture, formulas, security considerations
 *
 *      KEY CONCEPTS:
 *      - Concept 1: Explanation
 *      - Concept 2: Explanation
 *
 *      EXAMPLE:
 *      User deposits 100 tokens → receives 100 shares (1:1 ratio)
 *
 * @custom:security List critical security assumptions
 */
contract ContractName {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Description of what this stores
    /// @dev Units, precision, constraints (e.g., "in basis points, 10000 = 100%")
    uint256 public stateVariable;

    // ============================================
    // EVENTS
    // ============================================

    /// @notice Emitted when simple event occurs
    event SimpleEvent(address indexed user);

    /**
     * @notice Emitted when complex event with multiple params occurs
     * @param param1 Amount in base units
     * @param param2 Address receiving funds
     */
    event ComplexEvent(uint256 indexed param1, address param2);

    // ============================================
    // ERRORS
    // ============================================

    /// @notice Thrown when condition X fails
    error CustomError();

    // ============================================
    // FUNCTIONS
    // ============================================

    /**
     * @notice Brief description of what function does
     * @dev Technical implementation details
     *
     *      FORMULA: result = (a * b) / c
     *
     *      EXAMPLE:
     *      deposit(100) → 100 shares minted
     *
     * @param amount Amount in asset base units (e.g., 1e18 for 1.0 token)
     * @return shares Minted shares in 18 decimals
     *
     * @custom:security Only callable by authorized addresses
     */
    function functionName(uint256 amount) external returns (uint256 shares) {
        // Implementation
    }
}
```

---

## Units Reference (CRITICAL!)

**ALWAYS specify units for numeric parameters/returns:**

### Token Amounts
```solidity
/// @param amount Amount in asset base units (e.g., 1e18 for 1.0 token with 18 decimals)
/// @return balance Balance in token base units
```

### Shares
```solidity
/// @param shares Number of shares in 18 decimals
/// @return assets Assets redeemed in asset base units
```

### Percentages
```solidity
/// @param fee Fee in basis points (10000 = 100%, 100 = 1%)
/// @param ratio Ratio in BPS_EXTENDED (1000000 = 100%, 1000 = 0.1%)
```

### Time
```solidity
/// @param duration Duration in seconds
/// @param timestamp Unix timestamp in seconds since epoch
```

### Exchange Rates
```solidity
/// @param rate Exchange rate in RAY precision (1e27, where 1e27 = 1.0)
/// @param price Price in WAD precision (1e18, where 1e18 = 1.0)
```

### Special Values
```solidity
/// @param maxLoss Maximum acceptable loss in basis points (e.g., 100 = 1%)
/// @return 0 if operation failed, 1 if succeeded
/// @param deadline type(uint256).max for no deadline
```

---

## Section Organization

**Required order:**
1. ERRORS
2. EVENTS
3. IMMUTABLES
4. STATE VARIABLES
5. MODIFIERS
6. CONSTRUCTOR
7. EXTERNAL FUNCTIONS
8. PUBLIC FUNCTIONS
9. INTERNAL FUNCTIONS
10. PRIVATE FUNCTIONS
11. VIEW/PURE FUNCTIONS (grouped by visibility)

**Section divider:**
```solidity
// ============================================
// SECTION NAME
// ============================================
```

---

## Proven Patterns for Complex Functions

### Structured @dev Sections (HIGHLY EFFECTIVE)

Use labeled sections within @dev for complex functions. These render perfectly in generated documentation:

```solidity
/**
 * @notice Executes a complex operation with multiple steps
 * @dev Implements algorithm X with safeguards and optimizations
 *
 *      ALGORITHM:
 *      - Step 1: Validate inputs
 *      - Step 2: Calculate intermediate values
 *      - Step 3: Apply transformation
 *
 *      SPECIAL CASES:
 *      - input = 0: Returns default value
 *      - input = type(uint256).max: Uses maximum safe value
 *
 *      BEHAVIOR:
 *      - Updates state variable A
 *      - Emits Event X
 *      - Transfers tokens if needed
 *
 *      REQUIREMENTS:
 *      - Caller must have ROLE_X
 *      - Contract not paused
 *      - Input within valid range
 *
 * @param input Input value in base units
 * @param recipient Address to receive output
 * @return result Computed result in 18 decimals
 * @custom:security Reentrancy protected
 */
```

**Why this works:**
- ✅ Renders as clean markdown with sections preserved
- ✅ Easy to scan in both source and generated docs
- ✅ Bullet points maintained perfectly
- ✅ Blank lines between sections aid readability without bloat

**Common section labels:**
- `ALGORITHM:` - For calculation logic/formulas
- `BEHAVIOR:` - What the function does step-by-step
- `REQUIREMENTS:` - Preconditions that must be met
- `SPECIAL CASES:` - Edge cases and special inputs
- `FORMULA:` - Mathematical formulas
- `EXAMPLES:` - Concrete usage examples
- `STEPS:` - Ordered process flow
- `SECURITY:` - Security-critical considerations
- `EDGE CASES:` - Boundary conditions

### State Variable Documentation

**GOOD - Use NatSpec tags:**
```solidity
/// @notice Maximum number of items allowed in the queue
/// @dev Prevents excessive gas costs during iterations
uint256 public constant MAX_ITEMS = 10;
```

Renders cleanly as:
```markdown
### MAX_ITEMS
Maximum number of items allowed in the queue

*Prevents excessive gas costs during iterations*
```

**BAD - Inline comments pollute generated docs:**
```solidity
// ❌ DON'T DO THIS
mapping(address => mapping(address => uint256)) public balances; // user -> token -> amount
```

Renders awkwardly as:
```markdown
### balances

```solidity
mapping(address => mapping(address => uint256)) public balances; // user -> token -> amount
```
```

The inline comment `// user -> token -> amount` appears in the code block without context.

**FIX - Use @dev instead:**
```solidity
/// @notice Mapping of user balances per token
/// @dev Structure: user address → token address → balance amount
mapping(address => mapping(address => uint256)) public balances;
```

### Minimal But Complete Parameter Descriptions

**THE BALANCE**: Avoid verbosity BUT don't leave empty cells in generated docs.

**BAD** - Restates parameter name:
```solidity
/// @param delegate The delegate address
/// @param token The token address
```

**BAD** - Empty (creates empty table cells):
```solidity
/// @param delegate
/// @param token
```

**GOOD** - Minimal but adds value:
```solidity
/// @param delegate Authorized spender address
/// @param token Use NATIVE_TOKEN for ETH, otherwise ERC20 address
/// @param amount Transfer amount in token base units
```

**What makes a good minimal @param:**
- ✅ Role/purpose (e.g., "Authorized spender", "Recipient")
- ✅ Units (ALWAYS for numeric values)
- ✅ Special values (e.g., "Use NATIVE_TOKEN for ETH")
- ✅ Constraints (e.g., "Must be > 0", "Max 10 items")
- ❌ Restating the parameter name
- ❌ Obvious type information already in signature

### Forge Doc Tag Mapping (100% Accurate in Production)

| Source NatSpec | Generated Markdown | Notes |
|----------------|-------------------|-------|
| `@title` | `# Heading` | Top-level contract title |
| `@author` | `**Author:** line` | Rendered with bold |
| `@notice` | Plain text | Main description |
| `@dev` | `*Italic block*` | Technical details emphasized |
| `@param` | Parameter table | Name \| Type \| Description |
| `@return` | Returns table | Name \| Type \| Description |
| `@custom:xyz` | `**Note:** xyz` | Security/custom notes highlighted |

---

## Function Documentation Patterns

### Standard Function (Brief)
```solidity
/**
 * @notice Deposits assets and mints shares
 * @param amount Amount in asset base units
 * @return shares Minted shares in 18 decimals
 */
```

### Standard Function (With Technical Details)
```solidity
/**
 * @notice Deposits assets and mints shares
 * @dev Uses ERC4626 conversion formula with ROUND_DOWN
 * @param amount Amount in asset base units
 * @return shares Minted shares in 18 decimals
 */
```

### Privileged Function
```solidity
/**
 * @notice What this does
 * @dev Technical details
 * @param input Description with units
 * @custom:security Only callable by management/keeper/owner
 * @custom:security Reentrancy protected
 */
```

### Complex Function (Use blank lines ONLY for readability of long @dev)
```solidity
/**
 * @notice Converts assets to shares with profit locking
 * @dev FORMULA: shares = (assets * totalSupply) / (totalAssets - lockedProfit)
 *
 *      STEPS:
 *      1. Calculate unlocked profit
 *      2. Apply conversion rate
 *      3. Round down to favor existing holders
 * @param assets Amount in asset base units
 * @return shares Minted shares in 18 decimals
 */
```

### Override Function
```solidity
/**
 * @inheritdoc IBaseContract
 * @dev Additional implementation details specific to this override
 */
```

---

## Rounding Documentation

**ALWAYS specify rounding mode:**

```solidity
/// @dev Uses ROUND_DOWN (OpenZeppelin Math.Rounding.Floor) - favors protocol
/// @dev Uses ROUND_UP (OpenZeppelin Math.Rounding.Ceil) - favors user
/// @dev Uses ROUND_HALF_UP (banker's rounding)
```

**Example:**
```solidity
/**
 * @notice Converts assets to shares
 * @dev Uses ROUND_DOWN when minting shares (favors existing holders)
 *      Uses ROUND_UP when burning shares (favors exiting user)
 */
```

---

## Common Patterns

### Access Control
```solidity
/// @custom:security Only callable by management
/// @custom:security Only callable by keeper or management
/// @custom:security Permissionless but protected by X
```

### State Changes
```solidity
/// @dev Updates totalAssets and emits event
/// @dev Non-reentrant via nonReentrant modifier
/// @dev Follows CEI pattern (Checks-Effects-Interactions)
```

### Economic Formulas
```solidity
/// @dev Profit locking formula:
///      lockedProfit = profit * (unlockTime - currentTime) / unlockPeriod
///
///      Example: 100 ETH profit, 10 day unlock, after 5 days:
///      lockedProfit = 100 * (5 days) / (10 days) = 50 ETH
```

---

## State Variable Documentation

```solidity
/// @notice Brief description of what this stores
/// @dev Units, precision, constraints, update conditions
```

**Examples:**
```solidity
/// @notice Total assets managed by vault
/// @dev Updated on deposit, withdraw, and strategy reports (in asset base units)
uint256 private _totalAssets;

/// @notice Time until profits fully unlock
/// @dev Default 10 days (864000 seconds), changeable by governance
uint256 public profitMaxUnlockTime;

/// @notice Fee charged on profits
/// @dev In basis points (10000 = 100%, 500 = 5%)
uint16 public performanceFee;
```

---

## Checklist Before Commit

- [ ] All public/external functions have `@notice`, `@param`, `@return`
- [ ] All numeric params/returns specify units
- [ ] Contract has `@title`, `@author`, `@custom:security-contact`
- [ ] Privileged functions have `@custom:security` tags
- [ ] Complex logic has `@dev` with formulas/examples (brief!)
- [ ] Use structured sections (CONVERSION:, BEHAVIOR:, etc.) for complex functions
- [ ] Rounding modes specified where applicable
- [ ] No TODO/FIXME comments
- [ ] Section dividers used consistently
- [ ] No unnecessary blank lines in NatSpec blocks (except between @dev sections)
- [ ] No documentation that merely restates code/names
- [ ] Every comment justifies its existence
- [ ] Run `forge doc` to verify rendering quality

---

## Common Mistakes

❌ **NO**: `@param amount The amount` (restates parameter name)  
✅ **YES**: `@param amount Amount in asset base units`

❌ **NO**: `@return The shares` (no name, no units)  
✅ **YES**: `@return shares Minted shares in 18 decimals`

❌ **NO**: `/// @dev This function does X` (use @notice for "what")  
✅ **YES**: `/// @notice Does X`

❌ **NO**: `@param delegate The delegate address` (restates name)  
✅ **YES**: `@param delegate Authorized spender address`

❌ **NO**: `@param amount` (empty - generates empty table cells!)  
✅ **YES**: `@param amount Transfer amount in token base units`

❌ **NO**: `@param token The token address` (restates name)  
✅ **YES**: `@param token Use NATIVE_TOKEN for ETH, otherwise ERC20 address`

❌ **NO**: Multi-line block for simple events  
✅ **YES**: `/// @notice Emitted when user deposits`

❌ **NO**: Blank lines between @param tags (bloats code)  
✅ **YES**: Consecutive lines, blank ONLY before long @dev sections

❌ **NO**: Inline comments on declarations (pollutes generated docs)  
✅ **YES**: Use @dev to document structure/mappings

❌ **NO**: `@param fee The fee percentage` (no units)  
✅ **YES**: `@param fee Fee in basis points (10000 = 100%)`

❌ **NO**: Missing security tags on privileged functions  
✅ **YES**: `@custom:security Only callable by management`

---

## Resources

- **NatSpec Format**: https://docs.soliditylang.org/en/latest/natspec-format.html
- **OpenZeppelin Style**: https://docs.openzeppelin.com/contracts/style-guide
- **Security Contact**: security@golem.foundation

---

## Developer Workflow (Reproducible Process)

**Follow this workflow for consistent, high-quality NatSpec across the team:**

### Step 1: Write Code with NatSpec
```solidity
/**
 * @notice Brief user-facing description
 * @dev Technical details
 *
 *      CONVERSION:
 *      - Formula explanation
 *      - Edge cases
 *
 * @param amount Amount in asset base units
 * @return shares Shares minted in 18 decimals
 * @custom:security Reentrancy protected
 */
function deposit(uint256 amount) external returns (uint256 shares) {
    // Implementation
}
```

**Key principles:**
- Document WHY, not WHAT
- Specify units for ALL numeric values
- Use structured sections for complex logic
- Keep it brief and accurate

### Step 2: Format Code
```bash
yarn format
```

**Checks:**
- Removes trailing whitespace
- Consistent indentation
- Proper line breaks

### Step 3: Build & Test
```bash
yarn build
```

**Verifies:**
- No compiler errors
- No NatSpec syntax errors
- All documentation compiles

### Step 4: Generate Documentation
```bash
forge doc
```

**Creates:**
- `docs/src/` - Markdown documentation
- `docs/book/` - Browsable HTML (via mdBook)

### Step 5: Review Generated Docs
```bash
# View specific contract
cat docs/src/src/YourContract.sol/contract.YourContract.md

# Or open in browser
open docs/book/index.html
```

**What to check:**
- ✅ Structured sections (CONVERSION:, BEHAVIOR:) render cleanly
- ✅ Parameter tables are complete and readable
- ✅ Units show up in descriptions
- ✅ Security notes appear as **Note:** blocks
- ✅ Code examples render with syntax highlighting
- ✅ No broken formatting or missing content

### Step 6: Iterate if Needed
If something doesn't render well:
1. Adjust source NatSpec
2. Re-run `forge doc`
3. Review again
4. Update this guide with lessons learned

### Step 7: Commit
```bash
git add src/YourContract.sol
git commit -m "feat: add YourContract with comprehensive NatSpec"
```

**Pre-commit checklist:**
- [ ] All functions documented
- [ ] All units specified
- [ ] `forge doc` generates clean output
- [ ] No TODO/FIXME in production code
- [ ] Follows this guide's patterns

---

## Testing Documentation Quality

**Quick verification command:**
```bash
# One-line check: format, build, generate docs
yarn format && yarn build && forge doc && echo "✅ Documentation ready"
```

**For CI/CD integration:**
```bash
# Ensure docs are up to date
forge doc
git diff --exit-code docs/src/

# Will fail if generated docs don't match committed docs
```

**Positive Feedback Loop:**
1. Write NatSpec following this guide
2. Run workflow (format → build → doc)
3. Review generated markdown
4. Adjust if needed and repeat
5. Share improvements in this guide

---

**Remember**: Documentation is for auditors, integrators, and future you. Make it count! 🎯

**Proven Effectiveness**: Production contracts show that well-structured NatSpec generates clean documentation with 100% fidelity. Your careful documentation work pays off!
