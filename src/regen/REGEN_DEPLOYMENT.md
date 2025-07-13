# RegenStaker Deployment Guide

## Prerequisites

- `RegenEarningPowerCalculator` deployed
- `Whitelist` contracts deployed (or use `address(0)`)
- Allocation mechanisms deployed and audited

## Parameters

```solidity
struct CreateStakerParams {
    IERC20 rewardsToken;
    IERC20 stakeToken;             // Must be IERC20Staking for WITH_DELEGATION variant
    address admin;                 // Use multisig
    IWhitelist stakerWhitelist;    // address(0) = no restrictions
    IWhitelist contributionWhitelist; // address(0) = no restrictions
    IWhitelist allocationMechanismWhitelist; // Required, only audited mechanisms
    IEarningPowerCalculator earningPowerCalculator;
    uint256 maxBumpTip;           // In reward token's smallest unit
    uint256 maxClaimFee;          // In reward token's smallest unit
    uint256 minimumStakeAmount;   // In stake token's smallest unit
    uint256 rewardDuration;       // 7-3000 days (≥30 days recommended)
}
```

## Deployment

```solidity
// Deploy factory with canonical bytecodes
RegenStakerFactory factory = new RegenStakerFactory(regenStakerBytecode, noDelegationBytecode);

// For delegation variant (IERC20Staking tokens)
address staker = factory.createStakerWithDelegation(params, salt, regenStakerBytecode);

// For non-delegation variant (standard ERC20 tokens)
address staker = factory.createStakerWithoutDelegation(params, salt, noDelegationBytecode);
```

## Post-Deployment

```solidity
stakerWhitelist.add(initialStakers);
allocationMechanismWhitelist.add(auditedMechanisms);
staker.setClaimFeeParameters(ClaimFeeParameters(feeAmount, feeCollector));
```

## Emergency

```solidity
staker.pause();    // Pause operations
staker.unpause();  // Resume after resolution
```

**Important:** The pause functionality **does not** affect rewards calculation. Rewards continue to accumulate based on `block.timestamp` even while the contract is paused. The pause only prevents user interactions (stake, withdraw, claim, contribute, compound) but the reward distribution timeline remains unchanged.

## Common Issues

- **Precision Loss**: <30 day durations may have ~1% calculation error
- **Surrogate Delegation**: Verify IERC20Staking support
- **Whitelist Lockout**: Changes affect access immediately