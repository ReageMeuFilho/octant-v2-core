/* solhint-disable gas-custom-errors*/
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (finance/PaymentSplitter.sol)

pragma solidity ^0.8.25;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title PaymentSplitter
 * @dev This contract allows to split Ether payments among a group of accounts. The sender does not need to be aware
 * that the Ether will be split in this way, since it is handled transparently by the contract.
 *
 * The split can be in equal parts or in any other arbitrary proportion. The way this is specified is by assigning each
 * account to a number of shares. Of all the Ether that this contract receives, each account will then be able to claim
 * an amount proportional to the percentage of total shares they were assigned. The distribution of shares is set at the
 * time of contract deployment and can't be updated thereafter.
 *
 * `PaymentSplitter` follows a _pull payment_ model. This means that payments are not automatically forwarded to the
 * accounts but kept in this contract, and the actual transfer is triggered as a separate step by calling the {release}
 * function.
 *
 * NOTE: This contract assumes that ERC20 tokens will behave similarly to native tokens (Ether). Rebasing tokens, and
 * tokens that apply fees during transfers, are likely to not be supported as expected. If in doubt, we encourage you
 * to run tests before sending real value to this contract.
 */
contract PaymentSplitter is Context, Initializable {
    struct TokenEpoch {
        uint256 totalProfit; // Total profit accumulated
        uint256 totalLoss; // Total loss accumulated
        int256 netDistributable; // Profit - Loss (calculated at each recordProfit or recordLoss)
        bool finalized;
        mapping(address => bool) claimed;
    }

    struct Epoch {
        uint256 startTimestamp;
        uint256 endTimestamp;
    }

    // epoch state
    uint256 public currentEpoch;
    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public constant FINALIZATION_DELAY = 1 hours; // Safety buffer
    // epochsPerToken[epoch][token] -> TokenEpoch
    mapping(uint256 => mapping(address => TokenEpoch)) public epochsPerToken;
    // epochs[epoch] -> Epoch
    mapping(uint256 => Epoch) public epochs;
    // lastClaimedEpoch[account][token]
    mapping(address => mapping(address => uint256)) public lastClaimedEpoch;

    uint256 private _totalShares;
    uint256 private _totalReleased;

    mapping(address => uint256) private _shares;
    mapping(address => uint256) private _released;
    address[] private _payees;

    mapping(IERC20 => uint256) private _erc20TotalReleased;
    mapping(IERC20 => mapping(address => uint256)) private _erc20Released;

    event PayeeAdded(address account, uint256 shares);
    event PaymentReleased(address to, uint256 amount);
    event ERC20PaymentReleased(IERC20 indexed token, address to, uint256 amount);
    event PaymentReceived(address from, uint256 amount);
    event EpochCreated(uint256 epoch);
    event Reported(address indexed strategy, uint256 profit, uint256 loss);
    event NetDistributableUpdated(uint256 epoch, int256 amount);

    /**
     * @dev Creates an instance of `PaymentSplitter` where each account in `payees` is assigned the number of shares at
     * the matching position in the `shares` array.
     *
     * All addresses in `payees` must be non-zero. Both arrays must have the same non-zero length, and there must be no
     * duplicates in `payees`.
     */
    constructor() {
        _disableInitializers();
    }

    function initialize(address[] memory payees, uint256[] memory shares_) public payable initializer {
        require(payees.length == shares_.length, "PaymentSplitter: payees and shares length mismatch");
        require(payees.length > 0, "PaymentSplitter: no payees");

        for (uint256 i = 0; i < payees.length; i++) {
            _addPayee(payees[i], shares_[i]);
        }

        // create the first epoch
        currentEpoch = 1;
        epochs[currentEpoch].startTimestamp = block.timestamp;
        epochs[currentEpoch].endTimestamp = block.timestamp + EPOCH_DURATION;
        emit EpochCreated(1);
    }

    /**
     * @dev Getter for the total shares held by payees.
     */
    function totalShares() public view returns (uint256) {
        return _totalShares;
    }

    /**
     * @dev Getter for the total amount of Ether already released.
     */
    function totalReleased() public view returns (uint256) {
        return _totalReleased;
    }

    /**
     * @dev Getter for the total amount of `token` already released. `token` should be the address of an IERC20
     * contract.
     */
    function totalReleased(IERC20 token) public view returns (uint256) {
        return _erc20TotalReleased[token];
    }

    /**
     * @dev Getter for the amount of shares held by an account.
     */
    function shares(address account) public view returns (uint256) {
        return _shares[account];
    }

    /**
     * @dev Getter for the amount of Ether already released to a payee.
     */
    function released(address account) public view returns (uint256) {
        return _released[account];
    }

    /**
     * @dev Getter for the amount of `token` tokens already released to a payee. `token` should be the address of an
     * IERC20 contract.
     */
    function released(IERC20 token, address account) public view returns (uint256) {
        return _erc20Released[token][account];
    }

    /**
     * @dev Getter for the address of the payee number `index`.
     */
    function payee(uint256 index) public view returns (address) {
        return _payees[index];
    }

    /**
     * @dev Getter for the amount of payee's releasable `token` tokens. `token` should be the address of an
     * IERC20 contract.
     */
    function releasable(IERC20 token, address account) public view returns (uint256) {
        // fetch last claimed epoch for the token
        uint256 lastClaimedEpochValue = lastClaimedEpoch[account][address(token)];
        // if the last claimed epoch is the current epoch, return 0
        if (lastClaimedEpochValue == currentEpoch) {
            return 0;
        }

        // for each epoch between the last claimed epoch and the current epoch, add the net distributable to the total received
        uint256 totalReceived = 0;
        for (uint256 i = lastClaimedEpochValue + 1; i <= currentEpoch; i++) {
            int256 netDistributable = epochsPerToken[i][address(token)].netDistributable;
            if (netDistributable > 0) {
                totalReceived += uint256(netDistributable);
            }
        }

        return _pendingPayment(account, totalReceived, released(token, account));
    }

    /**
     * @dev Record profit for the current epoch.
     * @param amount The amount of profit to record.
     */
    function recordProfit(uint256 amount) public {
        _shouldCreateNewEpoch();
        require(currentEpoch > 0, "PaymentSplitter: no epoch");
        epochsPerToken[currentEpoch][msg.sender].totalProfit += amount;
        _updateNetDistributable(int256(amount));
        emit Reported(msg.sender, amount, 0);
    }

    /**
     * @dev Record loss for the current epoch.
     * @param amount The amount of loss to record.
     */
    function recordLoss(uint256 amount) public returns (uint256) {
        _shouldCreateNewEpoch();
        require(currentEpoch > 0, "PaymentSplitter: no epoch");
        epochsPerToken[currentEpoch][msg.sender].totalLoss += amount;

        _updateNetDistributable(-int256(amount));
        emit Reported(msg.sender, 0, amount);

        // return the amount of shares that were burned (profit in the current epoch - amount of loss)
        return epochsPerToken[currentEpoch][msg.sender].totalProfit - amount;
    }

    /**
     * @dev Create a new epoch if the current epoch is over.
     */
    function _shouldCreateNewEpoch() private {
        if (block.timestamp - epochs[currentEpoch].endTimestamp > EPOCH_DURATION) {
            uint256 newEpoch = ++currentEpoch;
            epochs[newEpoch].startTimestamp = block.timestamp;
            epochs[newEpoch].endTimestamp = block.timestamp + EPOCH_DURATION;
            emit EpochCreated(newEpoch);
        }
    }

    /**
     * @dev Update the net distributable for the current epoch.
     * @param amount The amount of vault shares to add or subtract to the net distributable for the current epoch.
     */
    function _updateNetDistributable(int256 amount) private {
        epochsPerToken[currentEpoch][msg.sender].netDistributable += amount;
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of `token` tokens they are owed, according to their
     * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
     * contract.
     */
    function release(IERC20 token, address account) public virtual {
        require(_shares[account] > 0, "PaymentSplitter: account has no shares");

        uint256 payment = releasable(token, account);

        require(payment != 0, "PaymentSplitter: account is not due payment");

        // _erc20TotalReleased[token] is the sum of all values in _erc20Released[token].
        // If "_erc20TotalReleased[token] += payment" does not overflow, then "_erc20Released[token][account] += payment"
        // cannot overflow.
        _erc20TotalReleased[token] += payment;
        unchecked {
            _erc20Released[token][account] += payment;
        }

        SafeERC20.safeTransfer(token, account, payment);
        emit ERC20PaymentReleased(token, account, payment);
    }

    /**
     * @dev internal logic for computing the pending payment of an `account` given the token historical balances and
     * already released amounts.
     */
    function _pendingPayment(
        address account,
        uint256 totalReceived,
        uint256 alreadyReleased
    ) private view returns (uint256) {
        return (totalReceived * _shares[account]) / _totalShares - alreadyReleased;
    }

    /**
     * @dev Add a new payee to the contract.
     * @param account The address of the payee to add.
     * @param shares_ The number of shares owned by the payee.
     */
    function _addPayee(address account, uint256 shares_) private {
        require(account != address(0), "PaymentSplitter: account is the zero address");
        require(shares_ > 0, "PaymentSplitter: shares are 0");
        require(_shares[account] == 0, "PaymentSplitter: account already has shares");

        _payees.push(account);
        _shares[account] = shares_;
        _totalShares = _totalShares + shares_;
        emit PayeeAdded(account, shares_);
    }
}
