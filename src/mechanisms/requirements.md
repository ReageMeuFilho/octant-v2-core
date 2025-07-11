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

The allocation mechanism system follows the **Yearn V3 Tokenized Strategy Pattern** with three main components:

1. **TokenizedAllocationMechanism.sol** - Shared implementation containing all standard logic (voting, proposals, ERC4626 vault functionality, storage management)
2. **BaseAllocationMechanism.sol** - Lightweight proxy contract with fallback delegation and hook definitions
3. **ProperQF.sol** - Abstract contract providing incremental quadratic funding algorithm with alpha-weighted distribution (used by quadratic voting strategies)

The system uses a hook-based architecture that allows implementers to customize voting behaviors while maintaining core security and flow invariants. This pattern provides significant gas savings and code reuse compared to traditional inheritance patterns.

### Yearn V3 Pattern Benefits
- **Gas Efficiency**: Deploy shared implementation once, reuse for all strategies
- **Reduced Audit Surface**: Core logic audited once, strategies only need hook review  
- **Code Reuse**: All standard functionality (signup, propose, castVote) shared across strategies
- **Storage Isolation**: Each strategy maintains independent storage despite shared implementation

### Delegation Pattern Architecture

The Yearn V3 pattern implements a sophisticated delegation mechanism:

1. **Storage Location**: All storage lives in the proxy contract (e.g., QuadraticVotingMechanism) following TokenizedAllocationMechanism's layout
2. **Logic Execution**: Shared logic executes in TokenizedAllocationMechanism's context via delegatecall
3. **Access Pattern**: Proxy contracts access storage through helper functions that return interfaces at `address(this)`

#### How It Works:
- When a proxy calls `_tokenizedAllocation().management()`, it returns `TokenizedAllocationMechanism(address(this))`
- This call to a non-existent function triggers the fallback, delegating to TokenizedAllocationMechanism
- The implementation reads from the proxy's storage slots, returning the stored management address
- This enables role-based access control (`owner`, `management`, `keeper`, `emergencyAdmin`) across all mechanisms

#### Role Hierarchy:
- **Owner**: Primary admin with full control (can transfer ownership, pause/unpause)
- **Management**: Can configure operational parameters and settings
- **Keeper**: Can execute routine maintenance operations
- **Emergency Admin**: Can act in emergencies alongside management

### Hook-Based Modular Approach

The contract defines 11 strategic hooks that implementers must override to create specific voting mechanisms:

**Key Architectural Decision - Permissionless Queuing:**
The system implements **permissionless proposal queuing** (`queueProposal()` has no `onlyOwner` modifier), enabling flexible governance models:
- **Community-Driven**: Anyone can queue successful proposals, removing admin bottlenecks
- **Custom Access Control**: Mechanisms can enforce restrictions via `_requestCustomDistributionHook()` if needed
- **Governance Flexibility**: Supports both permissionless and permissioned models through hook customization

#### Core Validation Hooks
- **`_beforeSignupHook(address user)`** - Controls user registration eligibility
  - **Security Assumptions**: 
    - MUST return false for address(0) to prevent zero address registration
    - MUST be view function to prevent state manipulation during validation
    - SHOULD implement consistent eligibility criteria that cannot be gamed
    - MUST NOT allow re-registration if user already has voting power
- **`_beforeProposeHook(address proposer)`** - Validates proposal creation rights
  - **Security Assumptions**:
    - MUST verify proposer has legitimate right to create proposals (e.g., voting power > 0, role-based access)
    - MUST be view function to prevent state changes during validation
    - SHOULD prevent spam by implementing appropriate restrictions
    - MUST return false for address(0) proposers
    - MAY restrict to specific roles (e.g., QuadraticVotingMechanism restricts to keeper/management only)
- **`_validateProposalHook(uint256 pid)`** - Ensures proposal ID validity
  - **Security Assumptions**:
    - MUST validate pid is within valid range (1 <= pid <= proposalCount)
    - MUST be view function for gas efficiency and security
    - MUST NOT validate canceled proposals as valid
    - SHOULD be used consistently before any proposal state access
- **`_beforeFinalizeVoteTallyHook()`** - Guards vote tally finalization
  - **Security Assumptions**:
    - CAN implement additional timing or state checks before finalization
    - MUST NOT revert unless finalization should be blocked
    - MAY update state if needed (e.g., snapshot values)
    - SHOULD return true in most implementations unless specific conditions aren't met

#### Voting Power & Processing Hooks
- **`_getVotingPowerHook(address user, uint256 deposit)`** - Calculates initial voting power
  - **Security Assumptions**:
    - MUST return deterministic voting power based on deposit amount
    - MUST be view function to ensure consistency
    - MUST NOT exceed MAX_SAFE_VALUE (type(uint128).max) to prevent overflow
    - SHOULD implement fair and transparent power calculation
    - MAY normalize decimals for consistent voting power across different assets
- **`_processVoteHook(pid, voter, choice, weight, oldPower)`** - Processes vote and updates tallies
  - **Security Assumptions**:
    - MUST return newPower <= oldPower (power conservation invariant)
    - MUST accurately update vote tallies based on weight and choice
    - MUST prevent double voting by checking hasVoted mapping
    - MUST validate weight does not exceed voter's available power
    - SHOULD implement vote cost calculation (e.g., quadratic cost in QF)
    - MUST handle all VoteType choices appropriately (Against/For/Abstain)
- **`_hasQuorumHook(uint256 pid)`** - Determines if proposal meets quorum requirements
  - **Security Assumptions**:
    - MUST implement consistent quorum calculation logic
    - MUST be view function for deterministic results
    - SHOULD base quorum on objective metrics (vote count, funding amount, etc.)
    - MUST NOT change quorum logic after voting has started
    - SHOULD return false for proposals with zero votes

#### Distribution Hooks
- **`_convertVotesToShares(uint256 pid)`** - Converts vote tallies to vault shares
  - **Security Assumptions**:
    - MUST implement fair and consistent vote-to-share conversion
    - MUST be view function for predictable outcomes
    - MUST return 0 shares for proposals that don't meet quorum
    - SHOULD consider total available assets to prevent over-allocation
    - MUST handle mathematical operations safely (no overflow/underflow)
    - MAY implement complex formulas (e.g., quadratic funding with alpha)
- **`_getRecipientAddressHook(uint256 pid)`** - Retrieves proposal recipient
  - **Security Assumptions**:
    - MUST return the correct recipient address for the proposal
    - MUST be view function to prevent manipulation
    - MUST NOT return address(0) for valid proposals
    - SHOULD revert with descriptive error for invalid proposals
    - MUST return consistent recipient throughout proposal lifecycle
- **`_requestCustomDistributionHook(address recipient, uint256 shares)`** - Handles custom share distribution
  - **Security Assumptions**:
    - MUST return true ONLY if custom distribution is fully handled
    - MUST mint/transfer exact share amount if returning true
    - MUST NOT mint shares if returning false (default minting will occur)
    - MAY implement vesting, splitting, or other distribution logic
    - MUST handle reentrancy safely if making external calls
  - **Access Control Pattern**: Since `queueProposal()` is permissionless, this hook can enforce custom access control:
    - **Example**: `require(msg.sender == owner || hasRole(QUEUER_ROLE, msg.sender), "Unauthorized queuing")`
    - **Governance Models**: Can implement community-driven queuing, role-based access, or other patterns
    - **Flexibility**: Enables different governance models without requiring core contract changes
- **`_availableWithdrawLimit(address shareOwner)`** - Controls withdrawal limits with timelock enforcement
  - **Security Assumptions**:
    - MUST enforce timelock by returning 0 before redeemableAfter timestamp
    - MUST enforce grace period by returning 0 after expiration
    - SHOULD return type(uint256).max for no limit (within valid window)
    - MUST be view function for consistent results
    - MUST coordinate with redeemableAfter mapping in storage
- **`_calculateTotalAssetsHook()`** - Calculates total assets including matching pools
  - **Security Assumptions**:
    - MUST accurately reflect total assets available for distribution
    - MUST include any external funding sources (matching pools, grants)
    - MUST be view function when called during finalization
    - SHOULD snapshot values if they might change after finalization
    - MUST NOT double-count assets or include unauthorized funds

### BaseAllocationMechanism Deep Dive

BaseAllocationMechanism.sol serves as the lightweight proxy contract in the Yearn V3 pattern. It contains minimal code while enabling full functionality through delegation:

**Core Architecture:**
- **Immutable Storage**: Only stores `tokenizedAllocationAddress` and `asset` as immutable values
- **Constructor Initialization**: Initializes TokenizedAllocationMechanism storage via delegatecall during deployment
- **Hook Definitions**: Defines 12 abstract internal hooks that concrete implementations must override
- **External Hook Wrappers**: Provides external versions of hooks with `onlySelf` modifier for security
- **Fallback Delegation**: Implements assembly-based fallback to delegate all undefined calls to TokenizedAllocationMechanism

**Security Pattern - onlySelf Modifier:**
```solidity
modifier onlySelf() {
    require(msg.sender == address(this), "!self");
    _;
}
```
This ensures hooks can only be called via delegatecall from TokenizedAllocationMechanism where `msg.sender == address(this)`. This prevents external actors from directly calling the TokenizedAllocationMechanism contract to invoke hooks, maintaining strict security boundaries.

**Hook Implementation Pattern:**
Each hook follows a three-layer pattern:
1. **Abstract Internal**: `function _hookName(...) internal virtual returns (...)`
2. **External Wrapper**: `function hookName(...) external onlySelf returns (...) { return _hookName(...); }`
3. **Interface Call**: TokenizedAllocationMechanism calls via `IBaseAllocationStrategy(address(this)).hookName(...)`

**Helper Functions for Implementers:**
- `_tokenizedAllocation()`: Returns TokenizedAllocationMechanism interface at current address
- `_getProposalCount()`: Get total number of proposals
- `_proposalExists(pid)`: Check if proposal ID is valid
- `_getProposal(pid)`: Retrieve proposal details
- `_getVoteTally(pid)`: Get current vote tallies
- `_getVotingPower(user)`: Check user's voting power
- `_getQuorumShares()`: Get quorum requirement
- `_getRedeemableAfter(shareOwner)`: Check timelock status
- `_getGracePeriod()`: Get grace period configuration

**Fallback Function:**
The fallback uses inline assembly for gas-efficient delegation:
1. Copies calldata to memory
2. Performs delegatecall to TokenizedAllocationMechanism
3. Copies return data
4. Returns data or reverts based on delegatecall result

This pattern enables complete code reuse while maintaining storage isolation and upgrade safety through immutability.

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
  - In QuadraticVotingMechanism: Only keeper or management roles can create proposals

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
- **Implementation:** `queueProposal(uint256 pid)` with `_requestDistributionHook()` and direct `_mint()` calls
- **Access Control Design:** `queueProposal` is **permissionless** to enable flexible governance models, but access control can be enforced via `_requestCustomDistributionHook()` if needed
- **Acceptance Criteria:**
  - Can only queue proposals after tally finalization
  - Proposals must meet quorum requirements via `_hasQuorumHook()`
  - Share amount determined by `_convertVotesToShares()` hook
  - Shares actually minted to recipient via internal `_mint()` function
  - Timelock delay applied before redemption eligibility
  - **Permissionless queuing** enables community-driven execution without admin bottlenecks
  - **Custom distribution hook** can implement access control or other types of distributions altogether

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

#### FR-9: Optimal Alpha Calculation for Quadratic Funding
- **Requirement:** System must support dynamic calculation of optimal alpha parameter to ensure 1:1 shares-to-assets ratio given a fixed matching pool
- **Implementation:** `calculateOptimalAlpha(matchingPoolAmount, totalUserDeposits)` in QuadraticVotingMechanism and `_calculateOptimalAlpha()` in ProperQF
- **Acceptance Criteria:**
  - Calculates alpha that ensures total funding equals total available assets
  - Handles edge cases: no quadratic advantage (α=0), insufficient assets (α=0), excess assets (α=1)
  - Returns fractional alpha as numerator/denominator for precision
  - Can be called before finalization to determine optimal funding parameters
  - Supports dynamic adjustment of alpha via `setAlpha()` by mechanism owner

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
2. **Asset Safety**: ERC20 transfers use SafeERC20 for secure token handling
3. **Access Control**: Sensitive operations require proper validation
4. **Reentrancy Protection**: TokenizedAllocationMechanism uses ReentrancyGuard modifier
5. **Storage Isolation**: ProperQF uses EIP-1967 storage pattern to prevent collisions

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
- Voting power assigned (1:1 in SimpleVotingMechanism, scaled to 18 decimals in QuadraticVotingMechanism) 
- UserRegistered event emitted
- Voter can now participate in voting

**Key Constraints:**
- ✅ One-time registration only (cannot re-register)
- ✅ Must register before voting period ends
- ⚠️ **No asset recovery** - deposited tokens locked until mechanism concludes
- ✅ Voting power calculation customizable per mechanism
- ✅ QuadraticVotingMechanism: Voting power normalized to 18 decimals regardless of asset decimals

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
- ✅ QuadraticVotingMechanism: To cast W votes costs W² voting power (quadratic cost)
- ✅ QuadraticVotingMechanism: Only "For" votes supported (no Against/Abstain)

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
1. **Deploy Mechanism**: Use `AllocationMechanismFactory.deploySimpleVotingMechanism(config)` or `deployQuadraticVotingMechanism(config, alphaNumerator, alphaDenominator)`
2. **Configure Parameters**: Set voting delays, periods, quorum requirements, timelock, and alpha (for quadratic)
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
1. **Calculate Optimal Alpha** (Optional): `mechanism.calculateOptimalAlpha(matchingPoolAmount, totalUserDeposits)` to determine optimal funding parameters
2. **Set Alpha** (Optional): `mechanism.setAlpha(alphaNumerator, alphaDenominator)` to adjust quadratic vs linear weighting
3. **Finalize Voting**: `mechanism.finalizeVoteTally()` (after voting period ends)
4. **Queue Successful Proposals** (Optional): `mechanism.queueProposal(pid)` for each successful proposal - **Note: This is permissionless and can be done by anyone**
5. **Monitor Redemption**: Track recipient share redemption after timelock

**System Response:**
- Optimal alpha calculated to ensure 1:1 shares-to-assets ratio
- Alpha parameter updated if admin chooses to adjust
- Vote tallies permanently finalized (tallyFinalized = true)
- Successful proposals transition to Queued state
- Shares minted to recipients with timelock enforcement
- ProposalQueued events emitted with redemption timeline

**Key Responsibilities:**
- ✅ **Consider optimal alpha** to maximize quadratic funding within budget constraints
- ✅ **Must finalize promptly** after voting period to enable queuing
- ✅ **Permissionless queuing** means anyone can queue successful proposals - admins can facilitate but are not required
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
- ⚠️ **QuadraticVotingMechanism**: Only keeper or management can propose (not regular voters)

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
- **`_processVoteHook()`**: MUST maintain vote tally accuracy and ensure power conservation. For quadratic funding implementations, integrates with ProperQF's incremental update algorithm
- **`_convertVotesToShares()`**: Should implement fair conversion from votes to economic value. In quadratic funding, uses alpha-weighted formula: `α × quadraticFunding + (1-α) × linearFunding`
- **`_hasQuorumHook()`**: Must implement consistent quorum calculation based on total funding for the proposal

### Integration Hooks
- **`_getRecipientAddressHook()`**: Should return consistent recipient for share distribution
- **`_requestDistributionHook()`**: Should handle integration with external distribution systems
- **`_beforeFinalizeVoteTallyHook()`**: Can implement additional safety checks or state validation

## Technical Constraints

### Integration Requirements
- ERC20 asset must be specified at deployment time via AllocationConfig
- Vault share minting system integrated into TokenizedAllocationMechanism (ERC4626 compliant)
- Event emission provides off-chain integration points for monitoring and indexing
- Factory pattern ensures proper owner context (deployer becomes owner, not factory)
- Factory supports multiple voting mechanisms: `deploySimpleVotingMechanism()` and `deployQuadraticVotingMechanism()`


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
