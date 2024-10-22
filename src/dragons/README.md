# TokenizedStrategy.sol

## Executive Summary:
We are forking the Yearn Tokenized Strategy to support yield donations that are agnistic to the underlying protocols principal deployed. We will use this as the core to a dragon vault. This will allow for the creation of sustainable sources of funded by the underlying principal as well as borrowing from existing Yearn V3 strategies to generate yield. This requires us to fork some of the TokenizedStrategy.sol implementation to manage yield and principal separately and securely. Our goals are to have:

1) Separate yield from principal: Users deposit assets and receive 1:1 vault tokens and the asset-to-share ratio should remain constant (1:1).
2) Yield tracking: The strategy should earn yield as before but Yield must be tracked separately from the principal.
3) Yield withdrawal: Accumulated yield should not be withdrawable by the depositor. Instead, profits can be withdrawn by a special role (to be held by DragonVault).

### Gap Analysis:

Principal preservation:
- Current: TotalAssets fluctuates based on profits/losses.
- Needed: TotalAssets should always equal totalSupply of shares.

Yield separation:
- Current: Profits are locked and gradually released to all shareholders.
- Needed: Profits should be kept separate and not affect share value.

Yield withdrawal:
- Current: No specific function for yield-only withdrawal.
- Needed: New role and gated function to withdraw all accumulated yield.

Accounting:
- Current: Uses profit unlocking mechanism.
- Needed: Simpler accounting separating principal and yield.

Share price:
- Current: Share price can increase over time.
- Needed: Share price should remain constant (1:1 with asset), yield withdraws should NEVER affect share price, principal should always be safe.

#### TODO (I will remove this as I go and add audit documentation explaining implementation): 
Modify TokenizedStrategy.sol:
- Remove profit unlocking mechanism.
- Add a separate yield tracking variable.
- Modify deposit/mint functions to maintain 1:1 ratio.
- Modify withdraw/redeem functions to maintain 1:1 ratio.
- Add a new function for yield withdrawal by keeper.

Modify BaseStrategy.sol:
- Update _harvestAndReport spec to separate yield from principal.

Create new functions:
- addYield(): Internal function or similar to harvest and track yield.
- withdrawYield(): External function for keeper to withdraw yield.


Modify existing functions:
- totalAssets(): Should return only the principal amount.
- _deposit(): Ensure 1:1 minting of shares.
- _withdraw(): Ensure 1:1 burning of shares.


Update tests:
- Modify existing tests to reflect new behavior.
- Add new tests for yield separation and withdrawal.
