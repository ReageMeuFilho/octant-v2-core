# YieldSkimmingTokenizedStrategy Audit Report – Aug 26, 2025

Auditor: Ferit

### Summary
Transfer bypass is fixed. One accounting bug remains: withdrawing exactly half of the outstanding shares zeroes users’ recorded obligation, and the next report mints “profit” to the dragon from user value.

### Context and objective
Re-audit PR‑47 with focus on the prior “Dragon Transfer Bypass” and the new value‑debt design. Confirm the bypass is resolved and surface any remaining, exploitable accounting issues. Provide minimal, test‑backed remediation.

### Critical finding (exploit‑backed)
Bug: After burning shares in redeem/withdraw, the code compares withdrawn shares to the post‑burn total supply and clears all user debt when these are equal. This occurs when a user withdraws exactly half of the pre‑burn supply. With users’ debt set to zero while shares remain, the next report treats remaining vault value as profit and mints to the dragon.

PoC (short recap, reproducible in tests):
- Deposit 100 (rate 1.0) → userDebt=100, supply=100
- Profit: rate 1.5 → report mints 50 to dragon → supply=150, dragon=50
- Loss: rate 0.5 → report burns 50 → supply=100, dragon=0
- Redeem 50 (half supply) → userDebt incorrectly resets to 0
- Next report mints fabricated profit to dragon while economically insolvent

### Fix
Replace the post-burn equality check in both `redeem()` (lines 163-165) and `withdraw()` (lines 212-214):

**Current (buggy):**
```solidity
if (shares == _totalSupply(S)) {
    YS.totalUserDebtInAssetValue = 0;
}
```

**Fixed:**
```solidity
if (_totalSupply(S) == 0) {
    YS.totalUserDebtInAssetValue = 0;
    YS.dragonRouterDebtInAssetValue = 0;  // Also clear dragon debt for completeness
}
```

This ensures debts are only cleared when the vault is truly empty, not when someone withdraws exactly half the supply.

### Tests (single file)
- `test/yieldSkimming/YieldSkimmingInvariantsAndPoC.t.sol`
  - PoC: `test_Exploit_DebtReset_FabricatedProfit()`
  - Post‑fix: `test_Fix_DebtReset_NoFabricatedProfit()`
  - Forge StdInvariant suite (256 runs): conversion, dragon gating, mint/burn

### Current results
- PoC: PASS
- Post‑fix: FAIL (expected until remediation)
- Invariants: PASS

### Invariant model (what we assert continuously)
- Definitions: V = totalAssets × currentRate; S = totalShares; D = userDebt + dragonDebt (all in value units).
- Conversion: assetsOut(shares) = shares × min(totalAssets / S, 1 / currentRate) (pro‑rata when insolvent; live rate when solvent).
- Mint/burn and gating: no mint to dragon unless V > D; when V < D, dragon burns first up to balance; dragon operations revert when insolvent.

### Status
Do not merge until the fix is applied and this test file is green.
