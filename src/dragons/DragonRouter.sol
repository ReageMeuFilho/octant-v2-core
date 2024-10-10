// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ITransformer {
    function transform(address fromToken, address toToken, uint256 amount) external returns (uint256);
}

/**
 * @title Advanced Non-Transferable Single Token Split Vault
 * @dev This contract manages the distribution of a single ERC20 token among shareholders,
 * with the ability to transform the split token into another token upon withdrawal,
 * and allows authorized pushers to directly distribute splits.
 */
contract DragonRouter is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Constants ---
    bytes32 public constant SPLIT_DISTRIBUTOR_ROLE = keccak256("SPLIT_DISTRIBUTOR_ROLE");
    bytes32 public constant SPLIT_PUSHER_ROLE = keccak256("SPLIT_PUSHER_ROLE");
    uint256 private constant SPLIT_PRECISION = 1e18;

    // --- State Variables ---
    IERC20 public immutable asset;
    string public name;
    string public symbol;
    uint256 public splitPerShare;
    uint256 public totalSplit;
    uint256 public totalShares;

    // --- Structs ---
    struct UserTransformer {
        ITransformer transformer;
        address targetToken;
    }

    // --- Mappings ---
    mapping(address => uint256) public sharesOf;
    mapping(address => uint256) public splitClaimed;
    mapping(address => uint256) public userSplitPerShare;
    mapping(address => UserTransformer) public userTransformers;

    // --- Events ---
    event SplitDistributed(uint256 amount);
    event SplitClaimed(address indexed user, uint256 amount, address token);
    event SharesMinted(address indexed user, uint256 amount);
    event SharesBurned(address indexed user, uint256 amount);
    event UserTransformerSet(address indexed user, address transformer, address targetToken);
    event SplitPushed(address indexed user, uint256 amount, address token);

    /**
     * @dev Constructor to initialize the contract with the asset token and metadata.
     * @param _asset The ERC20 token to be distributed.
     * @param _name The name of the vault.
     * @param _symbol The symbol of the vault.
     */
    constructor(IERC20 _asset, string memory _name, string memory _symbol) {
        asset = _asset;
        name = _name;
        symbol = _symbol;
    }

    /**
     * @dev Allows a user to set their transformer for split withdrawals.
     * @param transformer The address of the transformer contract.
     * @param targetToken The address of the token to transform into.
     */
    function setUserTransformer(address transformer, address targetToken) external {
        require(sharesOf[msg.sender] > 0, "Must have shares to set transformer");
        userTransformers[msg.sender] = UserTransformer(ITransformer(transformer), targetToken);
        emit UserTransformerSet(msg.sender, transformer, targetToken);
    }

    /**
     * @dev Distributes new splits to all shareholders.
     * @param amount The amount of tokens to distribute.
     */
    function distribute(uint256 amount) external onlyRole(SPLIT_DISTRIBUTOR_ROLE) nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(totalShares > 0, "No shares exist");

        asset.safeTransferFrom(msg.sender, address(this), amount);

        splitPerShare += (amount * SPLIT_PRECISION) / totalShares;
        totalSplit += amount;

        emit SplitDistributed(amount);
    }

    /**
     * @dev Mints new shares for a user.
     * @param to The address receiving the shares.
     * @param amount The number of shares to mint.
     */
    function mint(address to, uint256 amount) external onlyRole(SPLIT_DISTRIBUTOR_ROLE) {
        require(amount > 0, "Amount must be greater than 0");

        _updateUserSplit(to);

        sharesOf[to] += amount;
        totalShares += amount;

        emit SharesMinted(to, amount);
    }

    /**
     * @dev Burns shares from a user.
     * @param from The address to burn shares from.
     * @param amount The number of shares to burn.
     */
    function burn(address from, uint256 amount) external onlyRole(SPLIT_DISTRIBUTOR_ROLE) {
        require(amount > 0, "Amount must be greater than 0");
        require(sharesOf[from] >= amount, "Insufficient shares");

        _updateUserSplit(from);

        sharesOf[from] -= amount;
        totalShares -= amount;

        emit SharesBurned(from, amount);
    }

    /**
     * @dev Allows a user to claim their available split, optionally transforming it.
     */
    function claimSplit() external nonReentrant {
        _updateUserSplit(msg.sender);
        uint256 claimableAmount = _calculateClaimableSplit(msg.sender);
        require(claimableAmount > 0, "No split to claim");

        splitClaimed[msg.sender] += claimableAmount;

        _transferSplit(msg.sender, claimableAmount);
    }

    /**
     * @dev Allows an authorized pusher to directly distribute splits to a user.
     * @param user The address of the user to receive the split.
     */
    function pushSplit(address user) external onlyRole(SPLIT_PUSHER_ROLE) nonReentrant {
        _updateUserSplit(user);
        uint256 claimableAmount = _calculateClaimableSplit(user);
        require(claimableAmount > 0, "No split to push");

        splitClaimed[user] += claimableAmount;

        _transferSplit(user, claimableAmount);
    }

    /**
     * @dev Internal function to transfer split to a user, applying transformation if set.
     * @param user The address of the user to receive the split.
     * @param amount The amount of split to transfer.
     */
    function _transferSplit(address user, uint256 amount) internal {
        UserTransformer memory userTransformer = userTransformers[user];
        if (address(userTransformer.transformer) != address(0)) {
            asset.approve(address(userTransformer.transformer), amount);
            uint256 transformedAmount = userTransformer.transformer.transform(
                address(asset),
                userTransformer.targetToken,
                amount
            );
            IERC20(userTransformer.targetToken).safeTransfer(user, transformedAmount);
            emit SplitClaimed(user, transformedAmount, userTransformer.targetToken);
        } else {
            asset.safeTransfer(user, amount);
            emit SplitClaimed(user, amount, address(asset));
        }
    }

    /**
     * @dev Updates the user's split accounting.
     * @param user The address of the user.
     */
    function _updateUserSplit(address user) private {
        userSplitPerShare[user] = splitPerShare;
    }

    /**
     * @dev Calculates the claimable split for a user.
     * @param user The address of the user.
     * @return The amount of split that is claimable.
     */
    function _calculateClaimableSplit(address user) private view returns (uint256) {
        uint256 newSplit = (sharesOf[user] * (splitPerShare - userSplitPerShare[user])) / SPLIT_PRECISION;
        return newSplit;
    }

    /**
     * @dev Returns the amount of split a user can claim.
     * @param user The address of the user.
     * @return The amount of split the user can claim.
     */
    function getClaimableSplit(address user) external view returns (uint256) {
        return _calculateClaimableSplit(user);
    }

    /**
     * @dev Returns the total amount of the asset token held by this contract.
     * @return The balance of the asset token in this contract.
     */
    function totalAssets() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
