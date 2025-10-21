# NatSpec Documentation Checklist

Use this checklist when reviewing pull requests with new/modified contracts.

## Contract-Level Documentation

- [ ] Has `@title` tag
- [ ] Has `@author` tag with format: `[Golem Foundation](https://golem.foundation)`
- [ ] Has `@custom:security-contact security@golem.foundation`
- [ ] Has `@notice` with user-facing description
- [ ] Has `@dev` with technical details (if needed)
- [ ] Has `@custom:security` tags for critical security considerations
- [ ] License is MIT (or AGPL if inherited from AGPL code)

## Function Documentation

- [ ] All public/external functions have `@notice`
- [ ] All parameters have `@param` with **units specified**
- [ ] All returns have `@return` with **units specified**
- [ ] Complex functions use structured sections (CONVERSION:, BEHAVIOR:, etc.)
- [ ] Privileged functions have `@custom:security` tags
- [ ] Rounding modes specified where applicable

## State Variables

- [ ] All public state variables have `/// @notice`
- [ ] All state variables have `/// @dev` explaining units/constraints
- [ ] Immutables are documented

## Events & Errors

- [ ] Simple events use single-line format: `/// @notice Description`
- [ ] Complex events have `@param` for non-obvious parameters
- [ ] All custom errors have `/// @notice` explaining when thrown

## Quality Checks

- [ ] No unnecessary blank lines between NatSpec tags
- [ ] No documentation that merely restates parameter names
- [ ] All numeric values specify units (e.g., "in basis points", "in 18 decimals")
- [ ] No TODO/FIXME comments in production code
- [ ] `forge doc` generates clean output without errors

## Testing

Run these commands to verify:

```bash
# Format and build
yarn format && yarn build

# Generate and review docs
forge doc
cat docs/src/src/YourContract.sol/contract.YourContract.md

# Verify no uncommitted doc changes
git diff docs/src/
```

## Example of Good NatSpec

```solidity
/**
 * @notice Deposits assets and mints shares to receiver
 * @dev Uses ERC4626 conversion formula with ROUND_DOWN
 *
 *      CONVERSION:
 *      - shares = (assets * totalSupply) / totalAssets
 *      - First deposit: 1:1 ratio
 *
 *      REQUIREMENTS:
 *      - Amount > 0
 *      - Amount <= maxDeposit(receiver)
 *
 * @param assets Amount in asset base units (or type(uint256).max for full balance)
 * @param receiver Address to receive minted shares
 * @return shares Amount of shares minted in 18 decimals
 * @custom:security Reentrancy protected
 */
function deposit(uint256 assets, address receiver) external returns (uint256 shares);
```

## Resources

- [OCTANT_NATSPEC_GUIDE.md](../OCTANT_NATSPEC_GUIDE.md) - Full documentation guide
- [NatSpec Format](https://docs.soliditylang.org/en/latest/natspec-format.html) - Solidity docs
- [YourContract.sol](../src/core/YourContract.sol) - Reference implementation
