# TokenizedStrategy.sol

## Executive Summary:
We are forking the Yearn Tokenized Strategy to support yield donations that are agnostic to the underlying protocols principal deployed. We will use this as the core to a dragon vault. This will allow for the creation of sustainable sources of funded by the underlying principal as well as borrowing from existing Yearn V3 strategies to generate yield. This requires us to fork some of the TokenizedStrategy.sol implementation to manage yield and principal separately and securely. Our goals are to have:

1) Separate yield from principal: Users deposit assets and receive 1:1 vault tokens and the asset-to-share ratio should remain constant (1:1).
2) Yield tracking: The strategy should earn yield as before but Yield must be tracked separately from the principal.
3) Yield withdrawal: Accumulated yield should not be withdrawable by the depositor. Instead, profits can be withdrawn by a special role (to be held by DragonVault).

### Core Functionality:

1. Yield Donation Mechanism
The yield donation mechanism allows users to deposit assets while automatically donating any earned yield. Think of it like a savings account where you keep your principal but donate all the interest earned. Here's how it works:

- Simplified Accounting: Direct tracking of yield separate from principal without profit unlocking mechanism
- Principal Preservation: TotalAssets maintains a 1:1 ratio with totalSupply of shares, ensuring depositor's principal is always preserved, if a loss is registered burn shares from Dragon Router before realizing loss in principal.
- Yield Withdrawal: Special keeper role (DragonRouter) has exclusive access to withdraw accumulated yield

2. Voluntary Lockup Mechanism
The lockup mechanism is like putting your money in a time-locked safe. You choose to lock your funds for at least 90 days, showing your commitment to the protocol. This helps create stability for the protocol while giving users flexibility in how long they want to commit their assets.

- Users can lock their strategy shares for a minimum period of 90 days (MINIMUM_LOCKUP_DURATION)
- Lockups can be created during deposit/mint operations using depositWithLockup() or mintWithLockup()
- Locked shares cannot be withdrawn until the lockup period expires
- Users can extend existing lockups with additional duration
- Each user can have one active lockup tracked via the LockupInfo struct

3. Rage Quit Mechanism
The rage quit feature acts as a safety valve, allowing users to exit their position if they need to, even during a lockup period. Think of it as an emergency exit ramp that lets you gradually withdraw your funds over 3 months, rather than being completely locked in.
- Allows users with locked shares to initiate a gradual withdrawal over 3 months
- Once initiated via initiateRageQuit():
  - Sets a new 3-month lockup period
  - Enables proportional unlocking of shares over time
  - Cannot be reversed once started
  - Forbids deposits after the rage quit
- Unlocked shares calculation during rage quit:
  - Based on time elapsed since rage quit initiation
  - Linear unlocking over the 3 month period
  - Formula: unlockedPortion = (timeElapsed * lockedShares) / MINIMUM_LOCKUP_DURATION


### Changes from original yearn implementation
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

Additional Functions:

- `setupHatsProtocol(address _hats, uint256 _keeperHat, uint256 _managementHat, uint256 _emergencyAdminHat, uint256 _regenGovernanceHat)`
  - Initializes Hats Protocol integration
  - Can only be called once by management
  - Sets up hat IDs for each role

Storage Updates:

- Added to StrategyData:
  - `hatsInitialized`: Flag for Hats Protocol state
  - `HATS`: IHats interface reference
  - Role-specific hat IDs (KEEPER_HAT, MANAGEMENT_HAT, etc.)

Update tests:
- Modify existing tests to reflect new behavior.
- Add new tests for yield separation and withdrawal.
