Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NonfungibleDepositManager
 * @notice Manages 32 ETH validator deposits via a 4‐step process, representing each deposit as an ERC-721 NFT.
 * 
 * The deposit lifecycle is:
 *   1. requestDeposit – User sends 32 ETH; NFT is minted and withdrawal credentials (their address in proper format) are stored.
 *   2. assignValidator – An approved operator commits the validator’s 48-byte public key and 96-byte signature.
 *   3. claimValidator – The withdrawal address confirms the deposit by passing in the deposit data root.
 *   4. issueValidator – An approved operator calls the official Deposit Contract on L1 with the stored deposit info.
 *
 * Additionally, a user may cancel (in Requested/Assigned states) to get their 32 ETH refunded.
 */
contract NonfungibleDepositManager is ERC721, Ownable, ReentrancyGuard {
    // Address of the official ETH2 Deposit Contract on mainnet.
    address public constant DEPOSIT_CONTRACT_ADDRESS = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    /// @dev Interface for the official deposit contract.
    interface IDepositContract {
        function deposit(
            bytes calldata pubkey,
            bytes calldata withdrawal_credentials,
            bytes calldata signature,
            bytes32 deposit_data_root
        ) external payable;
    }

    // The deposit process states.
    enum DepositState { None, Requested, Assigned, Confirmed, Finalized, Cancelled }

    // DepositInfo stores all information for a deposit.
    struct DepositInfo {
        DepositState state;
        address withdrawalAddress;       // The address set at requestDeposit.
        bytes32 withdrawalCredentials;   // 32-byte: 0x01 + 11 zeros + user's address.
        bytes pubkey;                    // 48-byte BLS pubkey (immutable once assigned).
        bytes signature;                 // 96-byte BLS signature (immutable once assigned).
        bytes32 depositDataRoot;         // User-confirmed deposit data root.
        address assignedOperator;        // Approved operator who called assignValidator.
    }

    // tokenId => DepositInfo
    mapping(uint256 => DepositInfo) private deposits;

    // Next tokenId for minting NFT deposit receipts.
    uint256 private nextTokenId = 1;

    // Approved operator addresses.
    mapping(address => bool) public operators;

    // Total ETH (in wei) held as pending deposits.
    uint256 public totalDeposits;

    // Events for each stage.
    event DepositRequested(uint256 indexed tokenId, address indexed user);
    event ValidatorAssigned(uint256 indexed tokenId, address indexed operator, bytes pubkey);
    event ValidatorConfirmed(uint256 indexed tokenId, address indexed user, bytes32 depositDataRoot);
    event ValidatorIssued(uint256 indexed tokenId, address indexed operator);
    event DepositCancelled(uint256 indexed tokenId, address indexed user);

    constructor() ERC721("ValidatorDeposit", "VDEP") {}

    // --- Operator Management ---
    /**
     * @notice Approve or revoke an operator.
     */
    function setOperator(address operator, bool approved) external onlyOwner {
        operators[operator] = approved;
    }

    // --- Step 1: Request Deposit ---
    /**
     * @notice User requests a deposit by sending exactly 32 ETH.
     * The withdrawal credentials are set to the caller's address.
     */
    function requestDeposit() external payable nonReentrant returns (uint256 tokenId) {
        require(msg.value == 32 ether, "Must send exactly 32 ETH");
        tokenId = nextTokenId++;
        totalDeposits += msg.value;

        // Format withdrawal credentials: 0x01 + 11 zero bytes + 20-byte address.
        bytes32 cred = _formatWithdrawalCredentials(msg.sender);

        deposits[tokenId] = DepositInfo({
            state: DepositState.Requested,
            withdrawalAddress: msg.sender,
            withdrawalCredentials: cred,
            pubkey: "",
            signature: "",
            depositDataRoot: 0,
            assignedOperator: address(0)
        });

        _safeMint(msg.sender, tokenId);
        emit DepositRequested(tokenId, msg.sender);
    }

    // --- Step 2: Assign Validator ---
    /**
     * @notice Approved operator assigns validator credentials.
     * Can only be called when the deposit is in Requested state.
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

    // --- Step 3: Claim Validator ---
    /**
     * @notice Withdrawal address confirms the validator assignment by providing the deposit data root.
     * The data root is computed (via SSZ tree hash) from the pubkey, withdrawal credentials,
     * 32 ETH (in gwei) and signature. This confirms that the operator’s data is correct.
     * Only the original withdrawal address may call this.
     */
    function claimValidator(uint256 tokenId, bytes32 depositDataRoot) external {
        DepositInfo storage info = deposits[tokenId];
        require(info.state == DepositState.Assigned, "Deposit not in Assigned state");
        require(msg.sender == info.withdrawalAddress, "Only the withdrawal address can claim");
        // Compute the deposit data root off-chain style and compare.
        bytes32 computedRoot = _computeDepositDataRoot(info.pubkey, info.withdrawalCredentials, info.signature);
        require(computedRoot == depositDataRoot, "Deposit data root mismatch");

        info.depositDataRoot = depositDataRoot;
        info.state = DepositState.Confirmed;
        emit ValidatorConfirmed(tokenId, msg.sender, depositDataRoot);
    }

    // --- Step 4: Issue Validator ---
    /**
     * @notice Approved operator issues the validator deposit on L1.
     * This sends exactly 32 ETH and the stored deposit info to the official Deposit Contract.
     * Can only be called when the deposit is in Confirmed state.
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

    // --- Cancellation ---
    /**
     * @notice Allows the withdrawal address to cancel a deposit (if still in Requested or Assigned state).
     * Burns the NFT and refunds 32 ETH.
     */
    function cancelDeposit(uint256 tokenId) external nonReentrant {
        DepositInfo storage info = deposits[tokenId];
        require(info.state == DepositState.Requested || info.state == DepositState.Assigned, "Cannot cancel now");
        require(msg.sender == info.withdrawalAddress, "Only the withdrawal address can cancel");

        info.state = DepositState.Cancelled;
        emit DepositCancelled(tokenId, msg.sender);
        _burn(tokenId);
        totalDeposits -= 32 ether;
        (bool success, ) = msg.sender.call{ value: 32 ether }("");
        require(success, "Refund failed");
        delete deposits[tokenId];
    }

    // --- Helper Functions ---
    /**
     * @dev Formats withdrawal credentials: 0x01 (prefix) followed by 11 zero bytes and then the 20-byte address.
     */
    function _formatWithdrawalCredentials(address _addr) internal pure returns (bytes32) {
        // Convert address to bytes20.
        bytes20 addrBytes = bytes20(_addr);
        return bytes32(abi.encodePacked(bytes1(0x01), bytes11(0), addrBytes));
    }

    /**
     * @dev Computes the deposit data root according to the official deposit contract’s SSZ tree hash.
     *
     * The official algorithm is:
     *   pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));
     *   signature_root = sha256(abi.encodePacked(sha256(signature[0:64]), sha256(abi.encodePacked(signature[64:96], bytes32(0)))));
     *   amount_bytes = to_little_endian_64(amount)   // here, amount in gwei (32 ETH = 32000000000)
     *   amount_root = sha256(amount_bytes);
     *   left = sha256(abi.encodePacked(pubkey_root, withdrawal_credentials));
     *   right = sha256(abi.encodePacked(amount_root, signature_root));
     *   deposit_data_root = sha256(abi.encodePacked(left, right));
     */
    function _computeDepositDataRoot(
        bytes memory pubkey,
        bytes32 withdrawalCred,
        bytes memory signature
    ) internal pure returns (bytes32) {
        require(pubkey.length == 48, "Bad pubkey length");
        require(signature.length == 96, "Bad signature length");

        bytes32 pubkeyRoot = sha256(abi.encodePacked(pubkey, bytes16(0)));
        // For signature, slice into first 64 and last 32 bytes.
        bytes memory sigPart1 = _slice(signature, 0, 64);
        bytes memory sigPart2 = _slice(signature, 64, 32);
        bytes32 sigRootFirst = sha256(sigPart1);
        bytes32 sigRootSecond = sha256(abi.encodePacked(sigPart2, bytes32(0)));
        bytes32 signatureRoot = sha256(abi.encodePacked(sigRootFirst, sigRootSecond));

        // 32 ETH in gwei: 32 ETH = 32 * 1e9 = 32000000000.
        uint64 depositAmountGwei = 32000000000;
        bytes memory amountLE = _toLittleEndian64(depositAmountGwei);
        bytes32 amountRoot = sha256(amountLE);

        bytes32 left = sha256(abi.encodePacked(pubkeyRoot, withdrawalCred));
        bytes32 right = sha256(abi.encodePacked(amountRoot, signatureRoot));
        return sha256(abi.encodePacked(left, right));
    }

    /**
     * @dev Helper: convert a uint64 to its 8-byte little-endian representation.
     */
    function _toLittleEndian64(uint64 value) internal pure returns (bytes memory) {
        bytes8 b = bytes8(value);
        bytes memory out = new bytes(8);
        out[0] = b[7];
        out[1] = b[6];
        out[2] = b[5];
        out[3] = b[4];
        out[4] = b[3];
        out[5] = b[2];
        out[6] = b[1];
        out[7] = b[0];
        return out;
    }

    /**
     * @dev Helper: slices a bytes array.
     * @param data The original bytes array.
     * @param start The starting index.
     * @param len The length to slice.
     * @return result A new bytes array containing the requested slice.
     */
    function _slice(bytes memory data, uint256 start, uint256 len) internal pure returns (bytes memory result) {
        require(data.length >= (start + len), "Slice out of range");
        result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = data[i + start];
        }
    }

    /**
     * @dev Prevents transfer of active deposit NFTs.
     * NFTs can only be transferred if the deposit is Finalized or Cancelled.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        if (from != address(0) && to != address(0)) { // not minting or burning
            DepositState st = deposits[tokenId].state;
            require(st == DepositState.Finalized || st == DepositState.Cancelled, "Active deposit NFTs are non-transferable");
        }
    }
}