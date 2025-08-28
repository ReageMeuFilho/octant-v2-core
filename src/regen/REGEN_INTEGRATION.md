# RegenStaker Integration Guide

## Factory Usage

```solidity
RegenStakerFactory factory = RegenStakerFactory(FACTORY_ADDRESS);

// IERC20Staking tokens (with delegation support)
address staker = factory.createStakerWithDelegation(params, salt, bytecode);

// Standard ERC20 tokens (without delegation support)
address staker = factory.createStakerWithoutDelegation(params, salt, bytecode);
```

## Parameters

```solidity
struct CreateStakerParams {
    IERC20 rewardsToken;
    IERC20 stakeToken;                    // Must be IERC20Staking for WITH_DELEGATION variant
    address admin;
    IWhitelist stakerWhitelist;           // address(0) = no restrictions
    IWhitelist contributionWhitelist;     // address(0) = no restrictions  
    IWhitelist allocationMechanismWhitelist;  // Required, only audited mechanisms
    IEarningPowerCalculator earningPowerCalculator;
    uint256 maxBumpTip;                   // In reward token's smallest unit
    uint256 maxClaimFee;                  // In reward token's smallest unit  
    uint256 minimumStakeAmount;           // In stake token's smallest unit
    uint256 rewardDuration;               // 7-3000 days (≥30 days recommended)
}
```

## Key Events

```solidity
event StakeDeposited(address indexed depositor, bytes32 indexed depositId, uint256 amount, uint256 balance, uint256 earningPower);
event RewardClaimed(bytes32 indexed depositId, address indexed claimer, uint256 amount, uint256 newEarningPower);
event RewardContributed(bytes32 indexed depositId, address indexed contributor, address indexed fundingRound, uint256 amount);
```

## Claimer Permissions

When setting a claimer for a deposit, be aware of the intended permission model:

### What Claimers CAN Do
- **Claim Rewards**: Withdraw accrued rewards to their address
- **Compound Rewards**: Reinvest rewards to increase the deposit's stake (when REWARD_TOKEN == STAKE_TOKEN)
- **Contribute Rewards**: Contribute unclaimed rewards to whitelisted allocation mechanisms (subject to contribution whitelist)
  - **⚠️ IMPORTANT**: When a claimer contributes, the CLAIMER receives the voting power in the allocation mechanism, NOT the deposit owner
  - This means claimers can effectively convert owner's rewards into their own voting power

### What Claimers CANNOT Do
- Withdraw principal stake
- Call `stakeMore()` directly
- Alter deposit parameters (delegatee, claimer)
  
Note: Claimers act as the owner's agent for rewards. They can claim, compound, and contribute rewards (if the contribution whitelist allows them). Owners can revoke the claimer at any time.

### Security Considerations
- **Trust Model**: Setting a claimer grants them limited staking abilities through compounding AND voting power when contributing
- **Voting Power**: Claimers receive voting power in allocation mechanisms when they contribute owner's rewards
- **Revocable**: Owners can change/remove claimers at any time via `alterClaimer()`
- **Economic Impact**: Compounding increases stake position, affecting earning power and rewards

### Best Practices
1. Only designate trusted addresses as claimers
2. Monitor claimer activities, especially compounding and contribution operations
3. Consider the long-term implications of automated compounding
4. Be aware that claimers will receive voting power when contributing to allocation mechanisms
5. Revoke claimer access when no longer needed

## Common Pitfalls

- **Surrogate Confusion**: RegenStaker moves tokens to surrogates, check `totalStaked()` not contract balance
- **Precision Loss**: <30 day reward durations may have ~1% error
- **Signature Replay**: Use nonces and deadlines in EIP-712 signatures
- **Whitelist Changes**: Monitor whitelist updates
- **Allocation Mechanism Trust**: Malicious mechanisms can misappropriate public good contributions
- **Claimer Permissions**: Claimers can increase stakes via compounding and receive voting power when contributing - this is intended behavior
- **Token Requirements**: STAKE_TOKEN and REWARD_TOKEN must be standard ERC-20. Fee-on-transfer/deflationary or rebasing tokens are unsupported. Accounting assumes transferred amount equals requested amount; non-standard tokens may break staking, withdrawals, or rewards.
