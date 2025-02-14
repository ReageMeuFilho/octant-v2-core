# Trust Minimized Noncustodial Eth Validator Staking

## Overview
We implement a trust-minimized approach to ETH validator staking to allowan operator to run a validator on behalf of a user who provides the deposit and has a signed exit transaction they can broadcast to ragequit the system. Each deposit is tokenized as a unique NFT, which tracks its state through the staking lifecycle. This design enforces that users specify their withdrawal address upfront and that validator credentials become immutable once set. The lifecycle includes the initial deposit request (with NFT creation), processing the deposit (assigning validator keys and verifying depost data), claiming the deposit (which finalizes the deposit state and sends funds to the official deposit contract), and, if needed, cancellation of a pending deposit.

## User Stories

### Request Deposit (Withdrawal Credentials & NFT Creation)

A user (acting as the deposit manager) begins by calling requestDeposit on the contract, sending exactly 32 ETH along with an explicit withdrawal address (which prob should be a cold wallet). The contract constructs the withdrawal credentials in the Ethereum consensus layer’s expected format—by prefixing the provided address with the byte 0x01, followed by 11 zero bytes, and then the 20‑byte Ethereum address. This yields a 32‑byte credential that represents user’s chosen type 1 withdrawal address.
For example, if the withdrawal address is 0xABC...123, then the withdrawal credential is formed as:
0x01 00...00 <ABC...123> (with 11 zeros in between).

After receiving the deposit and constructing the withdrawal credentials, the contract mints a new ERC‑721 token to the deposit manager (i.e. the msg.sender). The token’s unique ID (tokenId) serves as the request identifier. Internally, a new deposit record is created (using a struct) that stores details such as:

    The deposit manager’s address (as the NFT owner)
    The explicit withdrawal address
    The constructed withdrawal credentials
    The fixed deposit amount
    The initial state (set to Requested)

Security: The NFT guarantees a unique deposit request and enables the contract to track its lifecycle. The deposit funds (32 ETH) are securely locked in the contract and are recorded via internal accounting (using the totalDeposits variable). The minting process follows the checks‑effects‑interactions pattern.

### Process Deposit (Validator Key Assignment)

Once the deposit request is made, an approved staking operator on the contract calls the assignValidator function to provide the validator’s public key and its corresponding BLS signature. This function:

    Verifies that the deposit is in the Requested state.
    Checks that the public key is exactly 48 bytes and the signature is 96 bytes.
    Stores the provided validator credentials in the deposit’s record.
    Updates the state to Assigned, indicating that the deposit now has its immutable validator identity set (in line with beacon chain rules).

Security: To ensure data integrity, the contract includes an on‑chain computation of the deposit data root (using the same SSZ tree hash algorithm as the official deposit contract). This computation uses the stored public key, withdrawal credentials (from phase 1), signature, and the fixed deposit amount (32 ETH, in gwei). The computed root is then compared with the provided deposit data root to ensure they match. If not, the transaction reverts—guarding against malformed or tampered input.

### Claim Validator (Confirmation by depositor)

The next phase is “claiming” the deposit. This step does not withdraw funds but finalizes the deposit’s state, linking the validator’s identity permanently to the NFT. In the updated design, the claimValidator function can be called by either:

    The designated withdrawal address (cold wallet), or
    The deposit manager (i.e. the owner of the NFT).

This dual authorization ensures that both parties—the one holding the withdrawal keys and the one managing the deposit request—are empowered to confirm the deposit. The function:

    Confirms that the deposit is in the Assigned state.
    Checks that the caller is either the withdrawal address or the NFT owner.
    Recomputes the deposit data root on‑chain and verifies it against the provided value.
    On success, updates the deposit’s state to Confirmed and records a confirmedTimestamp (the block timestamp).

Cooldown for Cancellation:
To minimize trust, a cooldown period of one week is enforced—after which the deposit can be canceled even after it has been confirmed, if still not processed.

### Issue Validator (Submitting to the Official Deposit Contract)
Once confirmed, an approved operator calls issueValidator to send the 32 ETH (with the associated validator credentials) to the official Ethereum 2.0 deposit contract (at address 0x00000000219ab540356cBB839Cbe05303d7705Fa). Following proper state updates (switching the deposit to Finalized) and adjusting the internal accounting, this external call registers the deposit on the beacon chain after the node is confirmed online by the staking operator.

### Cancellation and Fund Recovery

When Can a Deposit Be Canceled?
The contract permits cancellation under these conditions:

    Immediately: When the deposit is in the Requested or Assigned state.
    After a Cooldown: When the deposit is in the Confirmed state, cancellation is only permitted if at least one week (7 days) has passed since the deposit was confirmed. This ensures that funds are not permanently locked if an operator fails to issue the validator.

Who Can Cancel?
Cancellation can be initiated by:

    The withdrawal address, or
    The deposit manager (i.e. the NFT owner)

In either case, the refund (32 ETH) is sent to the withdrawal address to ensure that the user’s cold storage wallet receives the funds. This dual‑authorization model minimizes trust and protects against scenarios where one party becomes unresponsive. Following a successful cancellation, the deposit’s state is updated to Cancelled, the corresponding NFT is burned, and the contract’s internal accounting is adjusted. The refund is then processed using a low‑level call to send 32 ETH to the designated withdrawal address. (Developers should note that if the withdrawal address is a contract with a rejecting fallback, a withdrawal pattern might be considered.)

After the deposit is successfully submitted via issueValidator, the beacon chain eventually processes the deposit and assigns a validator index. Although the contract itself cannot directly verify validator activation on the beacon chain, the NFT’s state (now Finalized or Claimed) indicates that the deposit is in‑flight or active. The NFT may be maintained as a permanent record of the active validator, even if its associated funds remain locked until an eventual exit or withdrawal.

### Dynamic NFT Metadata:
The contract supports dynamic NFT metadata that reflects the current state of the deposit:

    Requested: The metadata may display “Deposit Request #tokenId” with an image indicating pending status.
    Assigned/Confirmed: The metadata can update to reflect that the validator credentials have been set, and after confirmation, show details such as the validator public key.
    Finalized/Claimed: The metadata indicates that the deposit has been submitted to the beacon chain and is now active.

Additionally we generate a base64 encoded URI response that includes a dynamically generated NFT that displays the current status