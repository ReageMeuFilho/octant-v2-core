# RegenStaker Deployment Guide

## Prerequisites

- `RegenEarningPowerCalculator` deployed
- `Whitelist` contracts deployed (or use `address(0)`)
- Allocation mechanisms deployed and audited

## Parameters

```solidity
struct DeploymentConfig {
    IERC20 rewardsToken;
    IERC20 stakeToken;             // Must be IERC20Staking for full variant
    address admin;                 // Use multisig
    uint256 maxBumpTip;           // In reward token's smallest unit
    uint256 maxClaimFee;          // In reward token's smallest unit
    uint256 minimumStakeAmount;   // In stake token's smallest unit
    uint256 rewardDuration;       // 7-3000 days (≥30 days recommended)
}
```

## Deployment

```solidity
RegenStakerFactory factory = new RegenStakerFactory(bytecode1, bytecode2);
address staker = factory.createStaker(variant, params, salt, bytecode);
```

## Security Checklist

- [ ] Admin is multisig
- [ ] Earning power calculator audited
- [ ] Allocation mechanisms audited for proper use of public good contributions
- [ ] Token contracts verified
- [ ] Understand precision implications for <30 day reward durations

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

## Common Issues

- **Precision Loss**: <30 day durations may have ~1% calculation error
- **Surrogate Delegation**: Verify IERC20Staking support
- **Whitelist Lockout**: Changes affect access immediately