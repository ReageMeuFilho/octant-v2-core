# ETH2 Staking Vault Technical Specification

## Overview

The ETH2 Staking Vault enables trustless validator creation through an ERC7540-compliant asynchronous vault. The vault manages the complete lifecycle of ETH2 validators, from initial deposit through exit, while maintaining strict asset accounting and security controls.

Each controller address can operate exactly one validator, requiring a 32 ETH deposit. The vault issues shares on a 1:1 basis with deposited ETH once validators become active. This share token represents the holder's claim on the underlying staked ETH.

## Key Design Principles

The vault implements several core principles that guide its operation:

The vault enforces a strict one-to-one relationship between controllers, validators, and deposits. This simplifies state management and reduces complexity in validator operations.

Asset accounting is explicit and conservative. The vault tracks all ETH under management directly rather than inferring balances, preventing potential inflation attacks.

State transitions are unidirectional and explicit. Each validator progresses through clear states from deposit request through exit, with no ability to skip states or shortcut processes.

The implementation separates validator credentials. Users provide withdrawal credentials during deposit requests, while operator-supplied signing credentials complete validator activation.

### State Management
The vault maintains three primary state structures:

### ValidatorInfo:

Tracks validator credentials and lifecycle
Stores withdrawal and signing public keys
Manages validator status (active/exited)


### RequestInfo:

Handles deposit and redemption requests
Tracks request ownership and status
Manages cancellation states


### Asset Tracking:

Explicit totalAssets counter
Pending deposits/withdrawals per controller
Share token minting/burning aligned with validator lifecycle

## User Stories

As a staker, I want to:
- Deposit exactly 32 ETH to create a validator
- Provide my withdrawal credentials securely
- Receive shares representing my staked ETH
- Request validator exit when desired
- Withdraw my ETH after validator exit
- Cancel my deposit if needed before activation

As an operator, I want to:
- Process deposit requests with validator keys
- Manage validator activation securely
- Track validator status and exits
- Handle withdrawal processing

As an integrator, I want to:
- Interact with a standard ERC7540 interface
- Track validator and request state
- Monitor asset movements
- Integrate with existing systems

## Technical Implementation

The vault utilizes three primary data structures:

ValidatorInfo tracks the complete validator state including credentials, activation status, and exit data.

RequestInfo manages deposit and redemption requests, tracking amounts, ownership, and processing state.

The vault maintains explicit accounting through:
- totalAssets for total ETH under management
- pendingDeposits for ETH awaiting validator activation
- pendingWithdrawals for ETH pending withdrawal post-exit

Key flows include:

Deposit Flow:
1. User requests deposit with 32 ETH and withdrawal credentials
2. Operator processes with validator signing credentials
3. Validator activates and shares mint to user

Redemption Flow:
1. User requests redemption of shares
2. Validator exits on consensus layer
3. Exit is processed and ETH becomes withdrawable
4. User claims withdrawn ETH
