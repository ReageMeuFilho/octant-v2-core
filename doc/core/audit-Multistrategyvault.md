# Audit Notice: MultistrategyVault Contract

## Contract Overview

The `MultistrategyVault.sol` contract is a **direct transposition** from Vyper to Solidity based on the Yearn V3 vault implementation. This contract maintains the same core functionality, logic, and architecture as the original Yearn V3 vault while being adapted for Solidity syntax and conventions.

## Source Repository

The original implementation can be found at:
**https://github.com/yearn/yearn-vaults-v3**

## Audit Scope Exclusions

### Known Issues Disclaimer

**Any bugs, vulnerabilities, or issues that are:**

1. **Publicly known** in the Yearn V3 vault implementation
2. **Previously reported** to the Yearn V3 repository or on platforms like Immunify
3. **Documented** as existing issues in Yearn V3

**Will be considered OUT OF SCOPE and will NOT be accepted as valid findings** in this audit.

### Rationale

Since this contract is a faithful transposition of the Yearn V3 vault:
- The core logic and mathematical operations remain identical
- Business logic decisions inherit from Yearn's design choices
- Known limitations and trade-offs are intentionally preserved

## Important Audit Focus: Design Deviations

### Design Parity Requirement

**Auditors should report any impactful design changes between the Vyper and Solidity implementations.**

The goal of this transposition is to maintain **maximum parity** with the original Vyper implementation. Any deviations that could affect:

1. **Core vault mechanics** (deposits, withdrawals, accounting)
2. **Share price calculations** or mathematical operations
3. **Access control patterns** beyond necessary adaptations
4. **State machine behavior** or transaction ordering
5. **Fee structures** or reward distributions
6. **Strategy interaction patterns**
7. **Emergency functions** or safety mechanisms

Should be flagged as these represent unintended divergences from the battle-tested Yearn V3 design.

