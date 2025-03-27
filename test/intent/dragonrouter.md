# Dragon Router Schema

## Overview

The Dragon Router is a contract that manages the distribution of yield-bearing strategy shares among recipients, with the ability to convert the underlying assets to desired tokens through an intent-based protocol. It supports operator-based withdrawals for smart contract recipients (like ESF) through ERC-1271 signature validation.

## Core Components

### Recipients

- Each recipient has:
  - `bps`: Allocation percentage in basis points (e.g., 5000 = 50%)
  - `desiredToken`: The token they want to receive (e.g., GLM)
  - `shares`: Total shares allocated to them
  - `redeemedShares`: Number of shares already redeemed

### Share Distribution Flow

1. Strategy generates yield (mints new shares)
2. Dragon Router tracks total shares and recipient allocations
3. When an operator withdraws on behalf of a recipient:
   - Verifies operator signature if recipient is a smart contract
   - Calculates new shares (total shares - sum of all recipient shares)
   - Allocates recipient's portion based on their bps
   - Unwraps shares to underlying asset
   - Creates intent for token conversion
   - Intent protocol handles the actual swap

### Key Features

- Prevents double-claiming of shares
- Automatic distribution of new shares to all recipients
- Intent-based token conversion
- Share tracking per recipient
- Operator authorization for smart contract recipients

## Example Flow

1. Strategy mints 100 new shares
2. Operator withdraws on behalf of ESF (50% bps):
   - Operator signs withdrawal parameters
   - ESF validates operator signature
   - Gets 50 shares
   - Shares unwrapped to ETH
   - ETH converted to GLM via intent
3. Operator cannot withdraw same shares again
4. New yield generates new shares
5. Operator can withdraw ESF's portion of new shares

```mermaid
sequenceDiagram
    participant Test
    participant DR as DragonRouter
    participant STR as MockStrategy
    participant IP as MockIntentProtocol
    participant ESF as MockESF
    participant OP as Operator
    participant ETH as MockETH
    participant GLM as MockGLM

    Note over Test: Initial Setup
    Note over DR: DR has 100 shares<br/>ESF: 50% bps

    rect rgb(210, 250, 240)
        Note over Test,DR: Step 1: First Withdrawal
        Test->>DR: report()
        DR->>STR: report()
        STR-->>DR: mints 100 shares

        OP->>DR: withdrawAndConvert(ESF, deadline, minOut, signature)
        Note over DR: Verify operator signature<br/>Calculate new shares:<br/>100 - 0 = 100 new<br/>ESF gets 50 shares
        DR->>STR: unwrap(50 shares)
        STR-->>DR: returns 50 ETH
        DR->>IP: createIntent(ETH→GLM)
        IP-->>DR: returns intentId
        Test->>IP: executeIntent()
        IP->>ETH: transferFrom(DR, 50 ETH)
        IP->>GLM: transfer(50 GLM to ESF)
    end

    rect rgb(230, 240, 200)
        Note over Test,DR: Step 2: Attempt Second Withdrawal
        OP->>DR: withdrawAndConvert(ESF, deadline, minOut, signature)
        Note over DR: Calculate new shares:<br/>50 - 100 = 0 new<br/>Reverts: "No new shares"
    end

    rect rgb(250, 230, 230)
        Note over Test,DR: Step 3: Generate New Yield
        Test->>DR: report()
        DR->>STR: report()
        STR-->>DR: mints 100 shares

        OP->>DR: withdrawAndConvert(ESF, deadline, minOut, signature)
        Note over DR: Verify operator signature<br/>Calculate new shares:<br/>150 - 100 = 50 new<br/>ESF gets 25 shares
        DR->>STR: unwrap(25 shares)
        STR-->>DR: returns 25 ETH
        DR->>IP: createIntent(ETH→GLM)
        IP-->>DR: returns intentId2
        Test->>IP: executeIntent()
        IP->>ETH: transferFrom(DR, 25 ETH)
        IP->>GLM: transfer(25 GLM to ESF)
    end
```

The key changes in this update are:

1. Added operator authorization flow details
2. Updated the sequence diagram to show operator interactions
3. Clarified the signature verification process
4. Added details about share tracking and redemption
5. Updated the example flow to reflect operator-based withdrawals
