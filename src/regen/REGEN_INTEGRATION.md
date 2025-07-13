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

## Common Pitfalls

- **Surrogate Confusion**: RegenStaker moves tokens to surrogates, check `totalStaked()` not contract balance
- **Precision Loss**: <30 day reward durations may have ~1% error
- **Signature Replay**: Use nonces and deadlines in EIP-712 signatures
- **Whitelist Changes**: Monitor whitelist updates
- **Allocation Mechanism Trust**: Malicious mechanisms can misappropriate public good contributions