// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @dev Interface for the official deposit contract.
interface IDepositContract {
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable;
}

/**
 * @title NonfungibleDepositManager
 * @notice Manages 32 ETH validator deposits via a 4‐step process, representing each deposit as an ERC-721 NFT.
 *
 * The deposit lifecycle is:
 *   1. requestDeposit – Deposit manager calls this with exactly 32 ETH and an explicit withdrawal address (cold wallet). NFT is minted to the deposit manager.
 *   2. assignValidator – An approved operator assigns the validator’s 48-byte public key and 96-byte signature.
 *   3. claimValidator – The withdrawal address (cold wallet) confirms the deposit by passing in the deposit data root.
 *   4. issueValidator – An approved operator calls the official Deposit Contract on L1 with the stored deposit info.
 *
 * @dev a deposit may be cancelled in the Requested/Assigned states immediately. For deposits in the Confirmed state,
 * a cooldown of 1 week is required before cancellation to prevent funds from being locked if the operator never calls issueValidator.
 * Cancellation refunds 32 ETH to the withdrawal address.
 */
contract NonfungibleDepositManager is ERC721, Ownable, ReentrancyGuard {
    // Address of the official ETH2 Deposit Contract on mainnet.
    address public constant DEPOSIT_CONTRACT_ADDRESS = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    // The deposit process states.
    enum DepositState {
        None,
        Requested,
        Assigned,
        Confirmed,
        Finalized,
        Cancelled
    }

    // DepositInfo stores all information for a deposit.
    struct DepositInfo {
        DepositState state;
        address withdrawalAddress; // The withdrawal (cold) address provided in requestDeposit.
        bytes32 withdrawalCredentials; // 32-byte: 0x01 + 11 zeros + user's address.
        bytes pubkey; // 48-byte BLS pubkey (immutable once assigned).
        bytes signature; // 96-byte BLS signature (immutable once assigned).
        bytes32 depositDataRoot; // User-confirmed deposit data root.
        address assignedOperator; // Approved operator who called assignValidator.
        uint256 confirmedTimestamp; // Timestamp when deposit entered the Confirmed state.
    }

    // tokenId => DepositInfo
    mapping(uint256 => DepositInfo) public deposits;

    // Next tokenId for minting NFT deposit receipts.
    uint256 private nextTokenId = 1;

    // Approved operator addresses.
    mapping(address => bool) public operators;

    // Total ETH (in wei) held as pending deposits.
    uint256 public totalDeposits;

    // Events for each stage.
    event DepositRequested(uint256 indexed tokenId, address indexed depositManager, address indexed withdrawalAddress);
    event ValidatorAssigned(uint256 indexed tokenId, address indexed operator, bytes pubkey);
    event ValidatorConfirmed(uint256 indexed tokenId, address indexed withdrawalAddress, bytes32 depositDataRoot);
    event ValidatorIssued(uint256 indexed tokenId, address indexed operator);
    event DepositCancelled(uint256 indexed tokenId, address indexed cancelledBy);

    /**
     * @notice Initializes the NonfungibleDepositManager contract
     * @dev Sets up the ERC721 token with name "ValidatorDeposit" and symbol "VDEP"
     */
    constructor() ERC721("TrustMinimizedEth2Staking", "stOCT") Ownable(msg.sender) ReentrancyGuard() {}

    /**
     * @notice Approve or revoke an operator's ability to assign validator credentials
     * @param operator The address to approve or revoke operator status from
     * @param approved True to approve, false to revoke
     * @dev Only callable by contract owner
     * @dev Operators can call assignValidator() to provide validator credentials for deposits
     */
    function setOperator(address operator, bool approved) external onlyOwner {
        operators[operator] = approved;
    }

    /**
     * @notice Initiates a new validator deposit by accepting exactly 32 ETH and minting an NFT receipt
     * @dev Deposit manager sends 32 ETH and sets withdrawal address then mints NFT receipt.
     * @dev Withdrawal credentials format: 0x01 + 11 zero bytes + withdrawal address
     * @param withdrawalAddress The Ethereum address that will control validator withdrawals
     * @return tokenId The ID of the minted NFT representing this deposit
     */
    function requestDeposit(address withdrawalAddress) external payable nonReentrant returns (uint256 tokenId) {
        require(msg.value == 32 ether, "Must send exactly 32 ETH");
        tokenId = nextTokenId++;
        totalDeposits += msg.value;

        // Format withdrawal credentials: 0x01 + 11 zero bytes + 20-byte withdrawal address.
        bytes32 cred = _formatWithdrawalCredentials(withdrawalAddress);

        deposits[tokenId] = DepositInfo({
            state: DepositState.Requested,
            withdrawalAddress: withdrawalAddress,
            withdrawalCredentials: cred,
            pubkey: "",
            signature: "",
            depositDataRoot: 0,
            assignedOperator: address(0),
            confirmedTimestamp: 0
        });

        _safeMint(msg.sender, tokenId);
        emit DepositRequested(tokenId, msg.sender, withdrawalAddress);
    }

    /**
     * @notice Assigns validator credentials to a deposit request
     * @dev Only callable by approved operators when deposit is in Requested state
     * @param tokenId The ID of the deposit NFT to assign credentials to
     * @param pubkey The 48-byte BLS public key of the validator
     * @param signature The 96-byte BLS signature from the validator
     * @custom:security Validates pubkey and signature lengths to prevent invalid deposits
     * @custom:emits ValidatorAssigned when credentials are successfully assigned
     * @custom:access Restricted to approved operators via operators mapping
     */
    function assignValidator(uint256 tokenId, bytes calldata pubkey, bytes calldata signature) external {
        require(operators[msg.sender], "Not an approved operator");
        DepositInfo storage info = deposits[tokenId];
        require(info.state == DepositState.Requested, "Deposit not in Requested state");
        require(pubkey.length == 48, "Invalid pubkey length");
        require(signature.length == 96, "Invalid signature length");

        info.assignedOperator = msg.sender;
        info.pubkey = pubkey;
        info.signature = signature;
        info.state = DepositState.Assigned;
        emit ValidatorAssigned(tokenId, msg.sender, pubkey);
    }

    /**
     * @notice Confirms the validator assignment by verifying the deposit data root
     * @dev The deposit data root is computed via SSZ tree hash from:
     *      - validator public key (pubkey)
     *      - withdrawal credentials
     *      - deposit amount (32 ETH in gwei)
     *      - validator signature
     * @param tokenId The ID of the deposit NFT to confirm
     * @param depositDataRoot The expected SSZ tree hash of the deposit data
     * @dev Validates caller is withdrawal address or NFT owner, verifies deposit data root,
     *      and updates deposit state to Confirmed with timestamp
     */
    function claimValidator(uint256 tokenId, bytes32 depositDataRoot) external {
        DepositInfo storage info = deposits[tokenId];
        require(info.state == DepositState.Assigned, "Deposit not in Assigned state");
        // Allow claim if caller is either the designated withdrawal address or the NFT owner.
        require(msg.sender == info.withdrawalAddress || msg.sender == ownerOf(tokenId), "Not authorized to claim");
        // Compute the deposit data root and verify it matches the provided value.
        bytes32 computedRoot = _computeDepositDataRoot(info.pubkey, info.withdrawalCredentials, info.signature);
        require(computedRoot == depositDataRoot, "Deposit data root mismatch");

        info.depositDataRoot = depositDataRoot;
        info.state = DepositState.Confirmed;
        info.confirmedTimestamp = block.timestamp; // Record confirmation time for cooldown.
        emit ValidatorConfirmed(tokenId, msg.sender, depositDataRoot);
    }

    /**
     * @notice Issues a validator deposit only callable by approved operators. Requires deposit to be confirmed.
     * @dev Sends 32 ETH to deposit contract. Protected against reentrancy.
     * @dev Transfers 32 ETH and the validator credentials to the official deposit contract.
     *      Only callable by approved operators when deposit is in Confirmed state.
     *      Updates state before external call to prevent reentrancy.
     *      Emits ValidatorIssued event on success.
     * @param tokenId The ID of the deposit NFT to issue the validator for
     */
    function issueValidator(uint256 tokenId) external nonReentrant {
        require(operators[msg.sender], "Not an approved operator");
        DepositInfo storage info = deposits[tokenId];
        require(info.state == DepositState.Confirmed, "Deposit not in Confirmed state");

        // Update state before external call.
        info.state = DepositState.Finalized;
        totalDeposits -= 32 ether;

        // Call the official deposit contract.
        IDepositContract(DEPOSIT_CONTRACT_ADDRESS).deposit{ value: 32 ether }(
            info.pubkey,
            abi.encodePacked(info.withdrawalCredentials),
            info.signature,
            info.depositDataRoot
        );

        emit ValidatorIssued(tokenId, msg.sender);
    }

    /**
     * @notice Cancels a validator deposit, refunds the 32 ETH, burn the NFT
     * @dev This function allows cancellation of deposits in different states with specific rules:
     *      - Deposits in Requested or Assigned states can be cancelled immediately
     *      - Deposits in Confirmed state require a 7-day cooldown period
     *      - Finalized deposits cannot be cancelled
     *      - Cancelled deposits cannot be cancelled again
     * @param tokenId The ID of the deposit NFT to cancel
     */
    function cancelDeposit(uint256 tokenId) external nonReentrant {
        DepositInfo storage info = deposits[tokenId];
        // Allowed states: Requested, Assigned, or Confirmed (if cooldown period passed).
        require(
            info.state == DepositState.Requested ||
                info.state == DepositState.Assigned ||
                (info.state == DepositState.Confirmed && block.timestamp >= info.confirmedTimestamp + 7 days),
            "Cannot cancel now"
        );
        // Allow cancellation if caller is the withdrawal address or holds the NFT (deposit manager).
        require(msg.sender == info.withdrawalAddress || msg.sender == ownerOf(tokenId), "Not authorized to cancel");

        info.state = DepositState.Cancelled;
        emit DepositCancelled(tokenId, msg.sender);
        _burn(tokenId);
        totalDeposits -= 32 ether;
        (bool success, ) = info.withdrawalAddress.call{ value: 32 ether }("");
        require(success, "Refund failed");
        delete deposits[tokenId];
    }

    /**
     * @notice Formats withdrawal credentials for ETH2 validator deposits
     * @dev Creates a 32-byte credential by concatenating:
     *      - 0x01 prefix byte (indicating ETH1 withdrawal address)
     *      - 11 zero bytes as padding
     *      - 20-byte withdrawal address
     * @param _addr The ETH1 withdrawal address to format credentials for
     * @return bytes32 The formatted withdrawal credentials
     */
    function _formatWithdrawalCredentials(address _addr) internal pure returns (bytes32) {
        bytes20 addrBytes = bytes20(_addr);
        return bytes32(abi.encodePacked(bytes1(0x01), bytes11(0), addrBytes));
    }

    /**
     * @notice Computes the deposit data root hash according to the official ETH2 deposit contract specification
     * @dev Implements the SSZ tree hash algorithm used by the official deposit contract:
     *      1. Compute pubkey root: hash(pubkey + zero padding)
     *      2. Compute signature root: hash(hash(first 64 bytes) + hash(last 32 bytes + padding))
     *      3. Convert 32 ETH to gwei and get amount root
     *      4. Combine roots into final deposit data root
     * @param pubkey The 48-byte BLS public key of the validator
     * @param withdrawalCred The 32-byte withdrawal credentials (0x01 + zeros + ETH1 address)
     * @param signature The 96-byte BLS signature
     * @return bytes32 The computed deposit data root hash
     * @custom:tree-structure The deposit data tree has the following structure:
     *                        DepositData
     *                        /          \
     *                   PubKey +       Amount +
     *              WithdrawalCred    Signature
     */
    function _computeDepositDataRoot(
        bytes memory pubkey,
        bytes32 withdrawalCred,
        bytes memory signature
    ) internal pure returns (bytes32) {
        require(pubkey.length == 48, "Bad pubkey length");
        require(signature.length == 96, "Bad signature length");

        uint deposit_amount = 32 ether / 1 gwei;
        bytes memory amount = to_little_endian_64(uint64(deposit_amount));

        // Compute deposit data root (`DepositData` hash tree root)
        bytes32 pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));

        // Split signature into two parts and hash them separately
        bytes32 signature_root = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(_slice(signature, 0, 64))),
                sha256(abi.encodePacked(_slice(signature, 64, 32), bytes32(0)))
            )
        );

        bytes32 node = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(pubkey_root, withdrawalCred)),
                sha256(abi.encodePacked(amount, bytes24(0), signature_root))
            )
        );

        return node;
    }
    /**
     * @notice Converts a uint64 value to its 8-byte little-endian representation
     * @dev Used for deposit data root computation to match ETH2 deposit contract spec
     * @param value The uint64 value to convert
     * @return ret The 8-byte little-endian representation of the input value
     */
    function to_little_endian_64(uint64 value) internal pure returns (bytes memory ret) {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }

    /**
     * @notice Extracts a slice from a bytes array
     * @dev Used internally for processing validator signatures during deposit data root computation
     * @param data The source bytes array to slice from
     * @param start The starting index of the slice (inclusive)
     * @param len The length of the slice to extract
     * @return result A new bytes array containing the extracted slice
     * @custom:throws "Slice out of range" if start + len exceeds data length
     */
    function _slice(bytes memory data, uint256 start, uint256 len) internal pure returns (bytes memory result) {
        require(data.length >= (start + len), "Slice out of range");
        result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = data[i + start];
        }
    }

    /**
     * @notice Hook that is called before any token transfer
     * @dev Prevents transfer of active deposit NFTs. NFTs can only be transferred if the deposit is Finalized or Cancelled.
     * This does not affect minting (from = 0) or burning (to = 0).
     * @param from The address transferring the token
     * @param to The address receiving the token
     * @param tokenId The ID of the token being transferred
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal {
        if (from != address(0) && to != address(0)) {
            // not minting or burning
            DepositState st = deposits[tokenId].state;
            require(st == DepositState.Finalized, "Active deposit NFTs are non-transferable");
        }
    }
}
