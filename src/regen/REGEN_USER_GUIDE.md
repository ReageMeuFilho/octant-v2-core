# RegenStaker User Guide

## Contract Variants

- **RegenStaker** - IERC20Staking tokens with delegation
- **RegenStakerWithoutDelegateSurrogateVotes** - Standard ERC20 tokens

## Core Functions

```solidity
stake(amount, delegatee, claimer) → depositId
stakeMore(depositId, amount)
withdraw(depositId, amount)
claimReward(depositId) → amount
compoundRewards(depositId) → amount  // reward token = stake token only
contribute(depositId, mechanism, amount, deadline, v, r, s) → amount
```

## Key Parameters

- **Reward Duration**: 7-3000 days (≥30 days recommended for precision)
- **Minimum Stake**: Token's smallest unit (e.g., 1e18 for 18-decimal)
- **Earning Power**: Determines reward share

## Whitelists

- **Staker**: Controls staking access (`address(0)` = unrestricted)
- **Contribution**: Controls contribution access (`address(0)` = unrestricted)
- **Allocation Mechanism**: Controls available mechanisms (required)

## Security

- Admin controls all parameters
- Allocation mechanisms must be audited
- Malicious mechanisms can misappropriate public good contributions
- Contract pausable for emergencies

## Error Codes

- `MinimumStakeAmountNotMet`
- `NotWhitelisted`
- `CompoundingNotSupported`
- `InvalidRewardDuration`