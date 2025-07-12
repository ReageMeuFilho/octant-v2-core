# Product Requirements Document: Allocation Mechanism System

This implementation serves as a comprehensive reference for applying the Yearn V3 tokenized strategy pattern to complex governance systems with real economic distribution.

## Product Vision & Motivation

**Vision:** Create a modular, secure, and transparent allocation mechanism that enables communities to democratically distribute resources through customizable voting strategies while maintaining strong governance safeguards using the Yearn V3 tokenized strategy pattern.

**Core Motivation:**
- **Democratic Resource Allocation**: Enable communities to fairly distribute funds/resources through transparent voting processes
- **Modular Architecture**: Provide a flexible framework that supports multiple voting strategies through a hook-based system implemented via Yearn V3 pattern
- **Code Reuse & Efficiency**: Leverage shared implementation contracts to reduce deployment costs and improve maintainability
- **Security & Governance**: Implement timelock mechanisms and validation hooks to prevent attacks and ensure proper governance
- **User Experience**: Simplify the complex process of on-chain voting while maintaining transparency and auditability

## Technical Architecture Overview

The allocation mechanism system follows the **Yearn V3 Tokenized Strategy Pattern** with two main components:

1. **TokenizedAllocationMechanism.sol** - Shared implementation containing all standard logic (voting, proposals, ERC4626 vault functionality, storage management)
2. **BaseAllocationMechanism.sol** - Lightweight proxy contract with fallback delegation and hook definitions

The system uses a hook-based architecture that allows implementers to customize voting behaviors while maintaining core security and flow invariants. This pattern provides significant gas savings and code reuse compared to traditional inheritance patterns.

### Yearn V3 Pattern Benefits
- **Gas Efficiency**: Deploy shared implementation once, reuse for all strategies
- **Reduced Audit Surface**: Core logic audited once, strategies only need hook review  
- **Code Reuse**: All standard functionality (signup, propose, castVote) shared across strategies
- **Storage Isolation**: Each strategy maintains independent storage despite shared implementation

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
- **Implementation:** `signup(uint256 deposit)` function in TokenizedAllocationMechanism with `_beforeSignupHook()` and `_getVotingPowerHook()` in strategy
- **Acceptance Criteria:**
  - Users can only register once during voting period
  - Registration requires hook validation to pass via `IBaseAllocationStrategy` interface
  - Voting power is calculated through customizable hook in strategy contract
  - Asset deposits are transferred securely using ERC20 transferFrom

#### FR-2: Proposal Creation & Management
- **Requirement:** Authorized users must be able to create proposals targeting specific recipients
- **Implementation:** `propose(address recipient, string description)` function in TokenizedAllocationMechanism with `_beforeProposeHook()` in strategy
- **Acceptance Criteria:**
  - Each recipient address can only be used once across all proposals
  - Proposal creation requires hook-based authorization via interface
  - Proposals receive unique incremental IDs
  - Recipients cannot be zero address

#### FR-3: Democratic Voting Process
- **Requirement:** Registered users must be able to cast weighted votes (For/Against/Abstain) on proposals
- **Implementation:** `castVote(uint256 pid, VoteType choice, uint256 weight)` in TokenizedAllocationMechanism with `_processVoteHook()` in strategy
- **Acceptance Criteria:**
  - Users can only vote once per proposal
  - Vote weight cannot exceed user's current voting power
  - Votes can only be cast during active voting period
  - Vote processing reduces user's available voting power

#### FR-4: Vote Tally Finalization
- **Requirement:** System must provide mechanism to finalize vote tallies after voting period ends
- **Implementation:** `finalizeVoteTally()` function with `_beforeFinalizeVoteTallyHook()` and owner-only access control
- **Acceptance Criteria:**
  - Can only be called after voting period ends
  - Can only be called once per voting round
  - Requires hook validation before proceeding
  - Sets tallyFinalized flag to true

#### FR-5: Proposal Queuing & Share Allocation
- **Requirement:** Successful proposals must be queued and vault shares minted to recipients
- **Implementation:** `queueProposal(uint256 pid)` with `_requestDistributionHook()` calling `mintShares()` via delegatecall
- **Acceptance Criteria:**
  - Can only queue proposals after tally finalization
  - Proposals must meet quorum requirements via `_hasQuorumHook()`
  - Share amount determined by `_convertVotesToShares()` hook
  - Shares actually minted to recipient via ERC4626 vault integration
  - Timelock delay applied before redemption eligibility

#### FR-6: Proposal State Management
- **Requirement:** System must track and expose proposal states throughout lifecycle
- **Implementation:** `state(uint256 pid)` and `_state()` functions with comprehensive state machine
- **Acceptance Criteria:**
  - States: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
  - State transitions follow predefined rules based on timing and votes
  - Canceled proposals remain permanently canceled
  - Grace period handling for expired proposals

#### FR-7: Proposal Cancellation
- **Requirement:** Proposals must be cancellable before queuing
- **Implementation:** `cancelProposal(uint256 pid)` function with proposer authorization
- **Acceptance Criteria:**
  - Can only cancel valid, non-canceled proposals
  - Cannot cancel already queued proposals
  - Cancellation is permanent and irreversible
  - Only proposer can cancel their proposals

#### FR-8: Share Redemption & Asset Distribution
- **Requirement:** Recipients must be able to redeem allocated shares for underlying assets after timelock
- **Implementation:** Standard ERC4626 `redeem(shares, receiver, owner)` function with timelock validation
- **Acceptance Criteria:**
  - Recipients can redeem shares only after timelock period expires
  - Shares are burned upon redemption, reducing total supply
  - Underlying assets transferred to recipient from mechanism vault
  - Redemption amount follows ERC4626 share-to-asset conversion
  - Recipients can redeem partial amounts or full allocation

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

## Complete User Journey Documentation

This section maps the full end-to-end experience for all three primary user types in the allocation mechanism system.

### 🗳️ VOTER JOURNEY

Voters are community members who deposit assets to gain voting power and participate in democratic resource allocation.

#### Phase 1: Registration & Deposit
**User Story:** "As a community member, I want to register and stake tokens so I can vote on funding allocations"

**Actions:**
1. **Approve Tokens**: `token.approve(mechanism, depositAmount)`
2. **Register**: `mechanism.signup(depositAmount)` 
3. **Receive Voting Power**: System calculates power via `_getVotingPowerHook()`

**System Response:**
- Assets transferred from voter to mechanism vault
- Voting power assigned (1:1 in SimpleVotingMechanism) 
- UserRegistered event emitted
- Voter can now participate in voting

**Key Constraints:**
- ✅ One-time registration only (cannot re-register)
- ✅ Must register before voting period ends
- ⚠️ **No asset recovery** - deposited tokens locked until mechanism concludes
- ✅ Voting power calculation customizable per mechanism

#### Phase 2: Proposal Discovery & Voting
**User Story:** "As a registered voter, I want to review proposals and cast weighted votes to influence fund distribution"

**Actions:**
1. **Review Proposals**: Check proposal details via `mechanism.proposals(pid)`
2. **Cast Votes**: `mechanism.castVote(pid, VoteType.For/Against/Abstain, voteWeight)`
3. **Monitor Progress**: Track remaining voting power via `mechanism.votingPower(address)`

**System Response:**
- Vote tallies updated through `_processVoteHook()`
- Voter's remaining power reduced by vote weight
- VotesCast event emitted
- Vote recorded (cannot be changed)

**Key Constraints:**
- ✅ Can only vote during active voting window
- ✅ One vote per proposal per voter (immutable)
- ✅ Vote weight cannot exceed remaining voting power
- ✅ Must manage power across multiple proposals strategically

#### Phase 3: Post-Voting Monitoring  
**User Story:** "As a voter, I want to see voting results and understand how my votes influenced the outcome"

**Actions:**
- **Monitor Results**: View vote tallies via `mechanism.getVoteTally(pid)`
- **Check Proposal States**: Track proposal outcomes via `mechanism.state(pid)`
- **Await Asset Recovery**: Wait for mechanism conclusion or asset recovery mechanism

**System Response:**
- Real-time vote tally visibility
- Proposal state transitions (Defeated/Succeeded/Queued)
- Final allocation determined by successful proposals

**Current Limitations:**
- ⚠️ **No asset recovery mechanism** for voters after voting concludes
- ⚠️ Deposited assets remain in vault even if all voting power is not consumed

---

### 👨‍💼 ADMIN JOURNEY

Admins are trusted operators who manage the voting lifecycle and ensure proper governance execution.

#### Phase 1: Mechanism Deployment & Setup
**User Story:** "As a funding round operator, I want to deploy and configure a voting mechanism for my community"

**Actions:**
1. **Deploy Mechanism**: Use `AllocationMechanismFactory.deploySimpleVotingMechanism(config)`
2. **Configure Parameters**: Set voting delays, periods, quorum requirements, timelock
3. **Announce Round**: Communicate mechanism address and voting schedule to community

**System Response:**
- Lightweight proxy deployed using shared TokenizedAllocationMechanism
- Admin becomes owner with privileged access
- AllocationMechanismInitialized event emitted
- Mechanism ready for user registration

**Key Responsibilities:**
- ✅ Choose appropriate voting parameters for community size
- ✅ Ensure sufficient timelock for security
- ✅ Communicate timing and rules clearly to participants

#### Phase 2: Round Monitoring & Validation
**User Story:** "As an admin, I want to monitor voting progress and ensure fair process execution"

**Actions:**
- **Monitor Registration**: Track user signups and voting power distribution
- **Validate Proposals**: Ensure proposal creation follows rules
- **Watch Voting**: Monitor vote casting and detect any irregularities
- **Prepare for Finalization**: Ensure readiness when voting period ends

**System Response:**
- Events provide real-time monitoring capabilities
- Vote tallies visible throughout voting period
- Proposal state tracking enables intervention if needed

**Key Responsibilities:**
- ✅ Ensure fair access to registration and voting
- ✅ Monitor for gaming or manipulation attempts
- ✅ Prepare community for finalization timeline

#### Phase 3: Finalization & Execution
**User Story:** "As an admin, I want to finalize voting results and execute successful proposals"

**Actions:**
1. **Finalize Voting**: `mechanism.finalizeVoteTally()` (after voting period ends)
2. **Queue Successful Proposals**: `mechanism.queueProposal(pid)` for each successful proposal
3. **Monitor Redemption**: Track recipient share redemption after timelock

**System Response:**
- Vote tallies permanently finalized (tallyFinalized = true)
- Successful proposals transition to Queued state
- Shares minted to recipients with timelock enforcement
- ProposalQueued events emitted with redemption timeline

**Key Responsibilities:**
- ✅ **Must finalize promptly** after voting period to enable queuing
- ✅ Queue all successful proposals that meet quorum
- ✅ Communicate redemption timeline to recipients
- ✅ Ensure proper execution of funding round outcomes

---

### 💰 RECIPIENT JOURNEY

Recipients are the beneficiaries of successful funding proposals who receive allocated vault shares.

#### Phase 1: Proposal Advocacy
**User Story:** "As a project seeking funding, I want to get my proposal created and advocate for community support"

**Actions:**
- **Find Proposer**: Work with registered voter who can create proposal
- **Proposal Creation**: Proposer calls `mechanism.propose(recipientAddress, description)`
- **Campaign**: Advocate to voters during voting period

**System Response:**
- Proposal created with unique ID
- Recipient address locked to this proposal (cannot be reused)
- ProposalCreated event emitted
- Proposal enters Active state when voting begins

**Key Constraints:**
- ✅ Each address can only be recipient of one proposal
- ✅ Cannot modify recipient address after proposal creation
- ⚠️ **Dependent on proposer** - recipients cannot self-propose

#### Phase 2: Voting Period & Outcome
**User Story:** "As a recipient, I want to track voting progress and understand if my proposal will succeed"

**Actions:**
- **Monitor Votes**: Track vote tallies via `mechanism.getVoteTally(proposalId)`
- **Check Status**: Monitor proposal state via `mechanism.state(proposalId)`
- **Await Results**: Wait for voting finalization and outcome determination

**System Response:**
- Real-time vote tracking available
- Proposal state updates based on vote progress
- Final outcome determined by quorum and net vote calculation

**Possible Outcomes:**
- ✅ **Succeeded**: Net votes meet quorum requirement
- ❌ **Defeated**: Failed to meet quorum or negative net votes
- ❌ **Canceled**: Proposer canceled before completion

#### Phase 3: Share Allocation & Redemption
**User Story:** "As a successful recipient, I want to claim my allocated shares and redeem them for underlying assets"

**Actions (for Successful Proposals):**
1. **Wait for Queuing**: Admin must call `queueProposal(pid)` after finalization
2. **Receive Shares**: Shares automatically minted to recipient address
3. **Wait for Timelock**: Cannot redeem until `redeemableAfter` timestamp
4. **Redeem Assets**: `mechanism.redeem(shares, recipient, recipient)` to claim underlying tokens

**System Response:**
- Shares minted directly to recipient (ERC20-compatible)
- Timelock enforced (typically 1+ days for security)
- Share-to-asset conversion follows ERC4626 standard
- Assets transferred from mechanism vault to recipient

**Key Benefits:**
- ✅ **ERC20 Shares**: Can be transferred, traded, or delegated before redemption
- ✅ **Flexible Redemption**: Can redeem partial amounts over time
- ✅ **Timelock Protection**: Prevents immediate extraction, enables intervention if needed
- ✅ **Fair Conversion**: Share value based on actual vote allocation

#### Phase 4: Asset Utilization
**User Story:** "As a funded recipient, I want to use allocated resources for the intended purpose"

**Actions:**
- **Claim Underlying Assets**: Redeem shares for tokens (USDC, ETH, etc.)
- **Execute Project**: Use funds according to proposal description
- **Report Back**: Provide community updates on fund utilization (off-chain)

**System Response:**
- Assets transferred to recipient's control
- Share supply reduced, maintaining vault accounting
- Allocation mechanism completes its role

**Long-term Considerations:**
- ✅ Recipients have full control over redeemed assets
- ✅ Can potentially redeem incrementally based on project milestones*
- ⚠️ **No enforcement** of fund usage (social/legal layer responsibility)

---

## Cross-Journey Integration Points

### 🔄 Multi-User Interactions

1. **Admin-Community Coordination**: Admins manage timing while community participates
2. **Voter-Recipient Dynamics**: Voting decisions directly impact recipient funding
3. **Timelock Security**: Protects all parties by preventing immediate extraction

### 📊 System-Wide Invariants

- **Conservation of Value**: Total allocated shares ≤ total deposited assets
- **Fairness Guarantee**: All participants operate under same rules and timing
- **Transparency**: All votes, proposals, and allocations are publicly visible
- **Immutability**: Key decisions (votes, proposals) cannot be reversed once committed

### 🛡️ Security & Governance Features

- **Timelock Protection**: Delays execution to enable intervention if needed
- **Hook Customization**: Allows different voting strategies while maintaining security
- **Owner Controls**: Admin functions for emergency management
- **Event Transparency**: Complete audit trail via blockchain events

## Hook Implementation Guidelines

### Critical Implementation Pattern (Yearn V3)
All hooks follow a dual-layer pattern:
1. **Internal Hook**: `function _hookName(...) internal virtual returns (...)`
2. **External Interface**: `function hookName(...) external onlySelf returns (...) { return _hookName(...); }`
3. **Interface Call**: TokenizedAllocationMechanism calls via `IBaseAllocationStrategy(address(this)).hookName(...)`

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

### Integration Requirements
- ERC20 asset must be specified at deployment time via AllocationConfig
- Vault share minting system integrated into TokenizedAllocationMechanism (ERC4626 compliant*)
- Event emission provides off-chain integration points for monitoring and indexing
- Factory pattern ensures proper owner context (deployer becomes owner, not factory)


### Performance Metrics
- **Gas Savings**: ~3.5M gas saved per additional strategy deployment vs traditional inheritance
- **Code Reuse**: 100% of core logic shared across all voting strategies
- **Audit Surface**: Reduced to only custom hook implementations per strategy
- **Deployment Success**: Factory successfully deploys lightweight strategies using shared implementation

### Architecture Validation
- **Voter Journey**: Complete registration → voting → monitoring flow working
- **Admin Journey**: Deployment → monitoring → finalization → execution flow working  
- **Recipient Journey**: Advocacy → outcome → share receipt → redemption flow working
- **Security Features**: Timelock protection, hook validation, owner controls all functional
- **Economic Model**: Fair vote-to-share conversion, proper vault accounting, asset conservation

## MEV Protection Requirements

### Keeper Requirements and Security assumptions

**Required Keeper Configuration**:
- **Private Mempool Protection**: Keepers MUST use private transaction relays such as:
  - Flashbots Protect RPC
  - MEV Blocker RPC
  - Other trusted private mempool services
- **Transaction Submission**: When calling `report()` on SkyCompounderStrategy, transactions MUST be submitted through private channels to prevent front-running
- **Risk Without Protection**: Without MEV protection, malicious actors can:
  - Front-run the reward swap with a buy transaction
  - Back-run with a sell transaction
  - Extract significant value from the strategy's rewards

**Implementation Note**: This requirement exists because the strategy prioritizes simplicity over on-chain slippage protection. Future versions may implement proper slippage calculations, but until then, MEV protection at the transaction layer is mandatory.

## Harvest Reporting and Loss Protection

### Strategy Reporting Mechanisms
Both yield donating and yield skimming strategies use the same reporting mechanism with built-in health checks for loss protection.

### Health Check Flag: `doHealthCheck`
**Key Configuration**: All strategies use the `doHealthCheck` boolean flag (default: `true`) to control loss protection validation during harvest reporting.

**Flag Behavior**:
- **When `doHealthCheck = true`**: The strategy validates that profit/loss is within acceptable bounds defined by `_profitLimitRatio` and `_lossLimitRatio`
- **When `doHealthCheck = false`**: The check is bypassed for one report cycle, then automatically re-enabled
- **Purpose**: Prevents reporting of excessive losses or suspicious profits that could indicate an exploit or price manipulation

### Loss Protection Mechanisms

#### Burning Flag: `enableBurning`
**Key Configuration**: All strategies use the `enableBurning` boolean flag to control whether shares can be burned from the donation address during loss events.

**Flag Behavior**:
- **When `enableBurning = true`**: The strategy can burn shares from the donation address (dragon router) to cover losses
- **When `enableBurning = false`**: No share burning occurs; losses are absorbed by all shareholders proportionally
- **Purpose**: Protects principal depositors by socializing losses to the donation recipient when enabled *and supported*

**Loss Protection Implementation**:

**Yield Donating Strategies**:
- Uses `_handleDragonLossProtection()` in YieldDonatingTokenizedStrategy
- Burns shares from donation address to cover losses when `enableBurning = true`
- Protects principal depositors from losses by reducing donation recipient's shares

**Yield Skimming Strategies**:
- Uses the same `_handleDragonLossProtection()` mechanism as yield donating strategies
- Operates identically: burns dragon router shares during losses if burning is enabled
- Ensures consistent loss protection across both strategy types

**Management Controls**:
- `setDoHealthCheck(bool)`: Enable/disable health checks (management only)
- `setProfitLimitRatio(uint16)`: Set maximum allowed profit percentage (management only)
- `setLossLimitRatio(uint16)`: Set maximum allowed loss percentage (management only)
