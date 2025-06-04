# Product Requirements Document: BaseAllocationMechanism

## Product Vision & Motivation

**Vision:** Create a modular, secure, and transparent allocation mechanism that enables communities to democratically distribute resources through customizable voting strategies while maintaining strong governance safeguards.

**Core Motivation:**
- **Democratic Resource Allocation**: Enable communities to fairly distribute funds/resources through transparent voting processes
- **Modular Architecture**: Provide a flexible framework that supports multiple voting strategies through a hook-based system
- **Security & Governance**: Implement timelock mechanisms and validation hooks to prevent attacks and ensure proper governance
- **User Experience**: Simplify the complex process of on-chain voting while maintaining transparency and auditability

## Technical Architecture Overview

BaseAllocationMechanism implements an abstract base contract that provides the governance framework for ERC4626 vault-based allocation systems. The contract uses a hook-based architecture that allows implementers to customize voting behaviors while maintaining core security and flow invariants.

### Hook-Based Modular Approach

The contract defines 9 strategic hooks that implementers must override to create specific voting mechanisms:

#### Core Validation Hooks
- **`_beforeSignupHook(address user)`** - Controls user registration eligibility
- **`_beforeProposeHook(address proposer)`** - Validates proposal creation rights
- **`_validateProposalHook(uint256 pid)`** - Ensures proposal ID validity
- **`_beforeFinalizeVoteTallyHook()`** - Guards vote tally finalization

#### Voting Power & Processing Hooks
- **`_getVotingPowerHook(address user, uint256 deposit)`** - Calculates initial voting power
- **`_processVoteHook(pid, voter, choice, weight, oldPower)`** - Processes vote and updates tallies
- **`_hasQuorumHook(uint256 pid)`** - Determines if proposal meets quorum requirements

#### Distribution Hooks
- **`_convertVotesToShares(uint256 pid)`** - Converts vote tallies to vault shares
- **`_getRecipientAddressHook(uint256 pid)`** - Retrieves proposal recipient
- **`_requestDistributionHook(address recipient, uint256 shares)`** - Handles share distribution

## Functional Requirements

#### FR-1: User Registration & Voting Power
- **Requirement:** Users must be able to register with optional asset deposits to gain voting power
- **Implementation:** `signup(uint256 deposit)` function with `_beforeSignupHook()` and `_getVotingPowerHook()`
- **Acceptance Criteria:**
  - Users can only register once during voting period
  - Registration requires hook validation to pass
  - Voting power is calculated through customizable hook
  - Asset deposits are transferred securely using ERC20 transferFrom

#### FR-2: Proposal Creation & Management
- **Requirement:** Authorized users must be able to create proposals targeting specific recipients
- **Implementation:** `propose(address recipient)` function with `_beforeProposeHook()`
- **Acceptance Criteria:**
  - Each recipient address can only be used once across all proposals
  - Proposal creation requires hook-based authorization
  - Proposals receive unique incremental IDs
  - Recipients cannot be zero address

#### FR-3: Democratic Voting Process
- **Requirement:** Registered users must be able to cast weighted votes (For/Against/Abstain) on proposals
- **Implementation:** `castVote(uint256 pid, VoteType choice, uint256 weight)` with `_processVoteHook()`
- **Acceptance Criteria:**
  - Users can only vote once per proposal
  - Vote weight cannot exceed user's current voting power
  - Votes can only be cast during active voting period
  - Vote processing reduces user's available voting power

#### FR-4: Vote Tally Finalization
- **Requirement:** System must provide mechanism to finalize vote tallies after voting period ends
- **Implementation:** `finalizeVoteTally()` function with `_beforeFinalizeVoteTallyHook()`
- **Acceptance Criteria:**
  - Can only be called after voting period ends
  - Can only be called once per voting round
  - Requires hook validation before proceeding
  - Sets tallyFinalized flag to true

#### FR-5: Proposal Queuing & Share Allocation
- **Requirement:** Successful proposals must be queued and vault shares minted to recipients
- **Implementation:** `queueProposal(uint256 pid)` with multiple hooks
- **Acceptance Criteria:**
  - Can only queue proposals after tally finalization
  - Proposals must meet quorum requirements
  - Share amount determined by `_convertVotesToShares()` hook
  - Timelock delay applied before redemption eligibility

#### FR-6: Proposal State Management
- **Requirement:** System must track and expose proposal states throughout lifecycle
- **Implementation:** `state(uint256 pid)` and `_state()` functions
- **Acceptance Criteria:**
  - States: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
  - State transitions follow predefined rules based on timing and votes
  - Canceled proposals remain permanently canceled
  - Grace period handling for expired proposals

#### FR-7: Proposal Cancellation
- **Requirement:** Proposals must be cancellable before queuing
- **Implementation:** `cancelProposal(uint256 pid)` function
- **Acceptance Criteria:**
  - Can only cancel valid, non-canceled proposals
  - Cannot cancel already queued proposals
  - Cancellation is permanent and irreversible
  - No authorization checks (any user can cancel)

## System Invariants & Constraints

### Timing Invariants
1. **Voting Window**: `startBlock + votingDelay ≤ voting period ≤ startBlock + votingDelay + votingPeriod`
2. **Registration Cutoff**: Users can only register before `startBlock + votingDelay + votingPeriod`
3. **Tally Finalization**: Can only occur after `startBlock + votingDelay + votingPeriod`
4. **Timelock Enforcement**: Shares redeemable only after `block.timestamp ≥ eta`
5. **Grace Period**: Proposals expire after `eta + GRACE_PERIOD` if not executed

### Power Conservation Invariants
1. **Non-Increasing Power**: `_processVoteHook()` must return `newPower ≤ oldPower`
2. **Single Registration**: Each address can only call `signup()` once
3. **Vote Uniqueness**: Each user can vote at most once per proposal

### State Consistency Invariants
1. **Unique Recipients**: Each recipient address used in at most one proposal
2. **Tally Finality**: `tallyFinalized` can only transition from false to true
3. **Proposal ID Monotonicity**: Proposal IDs increment sequentially starting from 1
4. **Cancellation Finality**: Canceled proposals cannot be un-canceled

### Security Invariants
1. **Hook Validation**: All critical operations protected by appropriate hooks
2. **Asset Safety**: ERC20 transfers use standard transferFrom pattern
3. **Access Control**: Sensitive operations require proper validation
4. **Reentrancy Protection**: External calls handled safely (implementation dependent)

## User Lifecycle Documentation

#### Phase 1: Registration
**User Story:** "As a community member, I want to register for voting so that I can participate in resource allocation decisions"

**Flow:**
1. User calls `signup(deposit)` with optional asset deposit
2. System validates registration through `_beforeSignupHook()`
3. Assets transferred if deposit > 0
4. Voting power calculated via `_getVotingPowerHook()`
5. User registered with voting power assigned

**NOTE:**
- One-time registration prevents voting power adjustment
- No mechanism to withdraw deposited assets before redemption (no take backs)

#### Phase 2: Proposal Creation
**User Story:** "As a funding round operator I want to add recipients to the funding round so that worthy projects can receive resources"

**Flow:**
1. User calls `propose(recipient)` with target recipient address
2. System validates through `_beforeProposeHook()`
3. System checks recipient hasn't been used before
4. Proposal created with unique ID and stored
5. Recipient marked as used to prevent duplicates

**NOTE:**
- No mechanism to update recipient after proposal creation
- Can submit proposal descriptions or metadata

#### Phase 3: Voting
**User Story:** "As a registered voter, I want to cast weighted votes on proposals so that I can influence resource allocation"

**Flow:**
1. User calls `castVote(pid, choice, weight)` during voting period
2. System validates proposal exists and voting window is active
3. System checks user hasn't already voted on this proposal
4. Vote processed through `_processVoteHook()` which updates tallies
5. User's voting power reduced by vote weight

**NOTE:**
- Cannot change or withdraw votes once cast
- Must carefully manage voting power across multiple proposals

**TODO**
- Mechanism to see current vote tallies during voting

#### Phase 4: Finalization & Queuing
**User Story:** "As a funding round recipient, I want to be fairly evaluated and if successful queue up for distribution"

**Flow:**
1. Admin* calls `finalizeVoteTally()` after voting period ends
2. System validates timing and hook requirements
3. For successful proposals, anyone calls `queueProposal(pid)`
4. System checks quorum through `_hasQuorumHook()`
5. Shares calculated and timelock initiated for recipient

**NOTE:**
- Manual finalization and queuing process
- No automatic execution of successful proposals
- Recipients must wait for timelock period regardless of proposal success timing

## Hook Implementation Guidelines

### Security-Critical Hooks
- **`_beforeSignupHook()`**: MUST validate user eligibility to prevent unauthorized registration
- **`_beforeProposeHook()`**: MUST validate proposer authority to prevent spam/invalid proposals  
- **`_validateProposalHook()`**: MUST validate proposal ID integrity to prevent invalid state access

### Mathematical Hooks
- **`_getVotingPowerHook()`**: Should implement consistent power allocation based on deposits/eligibility
- **`_processVoteHook()`**: MUST maintain vote tally accuracy and ensure power conservation
- **`_convertVotesToShares()`**: Should implement fair conversion from votes to economic value
- **`_hasQuorumHook()`**: Must implement consistent quorum calculation

### Integration Hooks
- **`_getRecipientAddressHook()`**: Should return consistent recipient for share distribution
- **`_requestDistributionHook()`**: Should handle integration with external distribution systems
- **`_beforeFinalizeVoteTallyHook()`**: Can implement additional safety checks or state validation

## Technical Constraints

### Gas Optimization Considerations
- Hook functions should minimize gas usage as they're called in critical paths
- Vote processing must scale efficiently with number of voters
- State reads should be optimized for frequently accessed data

### Upgrade & Proxy Compatibility
- Immutable variables (timing parameters) cannot be changed post-deployment
- Hook implementations must maintain storage layout compatibility
- State variable ordering critical for proxy pattern usage

### Integration Requirements
- ERC20 asset must be specified at deployment time
- Vault share minting system must be implemented by inheriting contracts
- Event emission provides off-chain integration points for monitoring and indexing