// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// OpenZeppelin Imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// Staker Library Imports
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { Staker } from "staker/Staker.sol";
import { StakerDelegateSurrogateVotes } from "staker/extensions/StakerDelegateSurrogateVotes.sol";
import { StakerPermitAndStake } from "staker/extensions/StakerPermitAndStake.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

// Local Imports
import { Whitelist } from "src/utils/Whitelist.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "src/regen/IWhitelistedEarningPowerCalculator.sol";
import { IGrantRound } from "src/regen/IGrantRound.sol";

// --- EIP-712 Specification for IGrantRound Implementations ---
// To ensure security against replay attacks for the `signup` method,
// any contract implementing the `IGrantRound` interface is expected to:
//
// 1. Be EIP-712 Compliant:
//    The `IGrantRound` contract should have its own EIP-712 domain separator.
//    This typically includes:
//    - name: The name of the grant round contract (e.g., "SpecificGrantRound").
//    - version: The version of the signing domain (e.g., "1").
//    - chainId: The chainId of the network where the contract is deployed.
//    - verifyingContract: The address of the `IGrantRound` contract itself.
//
// 2. Define a Typed Data Structure for Signup:
//    The data signed by the user (e.g., `deposit.owner`) must include a nonce.
//    Example structure (names can vary):
//    /*
//    struct GrantRoundSignupPayload {
//        uint256 assets;        // The amount of tokens for signup
//        address receiver;      // The address receiving voting power/shares
//        uint256 nonce;         // The signer's current nonce for this action
//    }
//    */
//
// 3. Define the TYPEHASH for this Structure:
//    This is `keccak256` of the EIP-712 struct definition string.
//    Example:
//    // bytes32 constant SIGNUP_PAYLOAD_TYPEHASH =
//    //     keccak256("GrantRoundSignupPayload(uint256 assets,address receiver,uint256 nonce)");
//
// 4. Manage Nonces:
//    The `IGrantRound` contract must maintain a nonce for each signer to prevent signature reuse.
//    Example:
//    // mapping(address => uint256) public userNonces;
//    Upon successful processing of a `signup` call, the `IGrantRound` contract must:
//    - Verify that the nonce in the signed payload matches `userNonces[signer]`.
//    - Increment `userNonces[signer]`.
//
// 5. Signature Verification:
//    The `signup` function will use `ecrecover` with the EIP-712 hash derived from
//    its domain separator, the `SIGNUP_PAYLOAD_TYPEHASH`, and the specific
//    `assets`, `receiver`, and expected `nonce` for the signer.
//
// The `bytes32 signature` parameter in `IGrantRound.signup` is intended to be the
// EIP-712 signature (r, s, v components) of this structured data.
// --- End EIP-712 Specification for IGrantRound ---

/// @title RegenStaker
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This contract is an extended version of the Staker contract by [ScopeLift](https://scopelift.co).
/// @notice As defined by Staker, REWARD_DURATION is constant and set to 30 days.
/// @notice You can tax the rewards with a claim fee. If you don't want rewards to be taxable, set MAX_CLAIM_FEE to 0.
contract RegenStaker is
    Staker,
    StakerDelegateSurrogateVotes,
    StakerPermitAndStake,
    StakerOnBehalf,
    Pausable,
    ReentrancyGuard
{
    using SafeCast for uint256;

    IWhitelist public stakerWhitelist;
    IWhitelist public contributionWhitelist;

    uint256 public constant MIN_PREFERENCES = 1;
    uint256 public constant MAX_PREFERENCES = 16;

    event StakerWhitelistSet(IWhitelist indexed whitelist);
    event ContributionWhitelistSet(IWhitelist indexed whitelist);
    event RewardContributed(
        DepositIdentifier indexed depositId,
        address indexed contributor,
        address indexed grantRound,
        uint256 amount
    );

    error NotWhitelisted(IWhitelist whitelist, address user);
    error CantAfford(uint256 requested, uint256 available);
    error GrantRoundSignUpFailed(address grantRound, address contributor, uint256 amount, address votingDelegatee);
    error PreferencesAndPreferenceWeightsMustHaveTheSameLength();
    error InvalidNumberOfPreferences(uint256 actual, uint256 min, uint256 max); // Changed uint to uint256 for consistency

    modifier onlyWhitelistedIfWhitelistIsSet(IWhitelist _whitelist) {
        if (_whitelist != IWhitelist(address(0)) && !_whitelist.isWhitelisted(msg.sender)) {
            revert NotWhitelisted(_whitelist, msg.sender);
        }
        _;
    }

    // @notice Constructor for the RegenStaker contract.
    // @param _rewardsToken The token that will be used to reward contributors.
    // @param _stakeToken The token that will be used to stake.
    // @param _admin The address of the admin. TRUSTED.
    // @param _stakerWhitelist The whitelist for stakers. If passed as address(0), a new Whitelist contract will be deployed.
    // @param _contributionWhitelist The whitelist for contributors. If passed as address(0), a new Whitelist contract will be deployed.
    // @param _earningPowerCalculator The earning power calculator.
    // @param _maxBumpTip The maximum bump tip.
    // @param _maxClaimFee The maximum claim fee. You can set fees between 0 and _maxClaimFee. _maxClaimFee cannot be changed after deployment.
    constructor(
        IERC20 _rewardsToken,
        IERC20Staking _stakeToken,
        address _admin,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IEarningPowerCalculator _earningPowerCalculator,
        uint256 _maxBumpTip,
        uint256 _maxClaimFee
    )
        Staker(_rewardsToken, _stakeToken, _earningPowerCalculator, _maxBumpTip, _admin)
        StakerPermitAndStake(_stakeToken)
        StakerDelegateSurrogateVotes(_stakeToken)
        EIP712("RegenStaker", "1")
    {
        if (address(_stakerWhitelist) == address(0)) {
            stakerWhitelist = new Whitelist();
            Ownable(address(stakerWhitelist)).transferOwnership(_admin);
        } else {
            stakerWhitelist = _stakerWhitelist;
        }

        if (address(_contributionWhitelist) == address(0)) {
            contributionWhitelist = new Whitelist();
            Ownable(address(contributionWhitelist)).transferOwnership(_admin);
        } else {
            contributionWhitelist = _contributionWhitelist;
        }

        MAX_CLAIM_FEE = _maxClaimFee;
        _setClaimFeeParameters(ClaimFeeParameters({ feeAmount: 0, feeCollector: address(0) }));
    }

    /// @inheritdoc Staker
    function stake(
        uint256 amount,
        address delegatee
    )
        external
        override(Staker)
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(stakerWhitelist)
        returns (DepositIdentifier _depositId)
    {
        _depositId = _stake(msg.sender, amount, delegatee, msg.sender);
    }

    /// @inheritdoc Staker
    function stake(
        uint256 amount,
        address delegatee,
        address claimer
    )
        external
        override(Staker)
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(stakerWhitelist)
        returns (DepositIdentifier _depositId)
    {
        _depositId = _stake(msg.sender, amount, delegatee, claimer);
    }

    // @inheritdoc Staker
    function stakeMore(
        DepositIdentifier _depositId,
        uint256 _amount
    ) external override whenNotPaused nonReentrant onlyWhitelistedIfWhitelistIsSet(stakerWhitelist) {
        Deposit storage deposit = deposits[_depositId];

        _revertIfNotDepositOwner(deposit, msg.sender);
        _stakeMore(deposit, _depositId, _amount);
    }

    /// @inheritdoc StakerOnBehalf
    function stakeOnBehalf(
        uint256 _amount,
        address _delegatee,
        address _claimer,
        address _depositor,
        uint256 _deadline,
        bytes memory _signature
    ) external override whenNotPaused nonReentrant returns (DepositIdentifier _depositId) {
        _revertIfPastDeadline(_deadline);
        _revertIfSignatureIsNotValidNow(
            _depositor,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        STAKE_TYPEHASH,
                        _amount,
                        _delegatee,
                        _claimer,
                        _depositor,
                        _useNonce(_depositor),
                        _deadline
                    )
                )
            ),
            _signature
        );
        _depositId = _stake(_depositor, _amount, _delegatee, _claimer);
    }

    /// @inheritdoc StakerOnBehalf
    function stakeMoreOnBehalf(
        DepositIdentifier _depositId,
        uint256 _amount,
        address _depositor,
        uint256 _deadline,
        bytes memory _signature
    ) external override whenNotPaused nonReentrant {
        Deposit storage deposit = deposits[_depositId];
        _revertIfNotDepositOwner(deposit, _depositor);
        _revertIfPastDeadline(_deadline);
        _revertIfSignatureIsNotValidNow(
            _depositor,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(STAKE_MORE_TYPEHASH, _depositId, _amount, _depositor, _useNonce(_depositor), _deadline)
                )
            ),
            _signature
        );

        _stakeMore(deposit, _depositId, _amount);
    }

    /// @inheritdoc StakerPermitAndStake
    function permitAndStake(
        uint256 _amount,
        address _delegatee,
        address _claimer,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override whenNotPaused nonReentrant returns (DepositIdentifier _depositId) {
        try
            IERC20Permit(address(STAKE_TOKEN)).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s)
        {} catch {}
        _depositId = _stake(msg.sender, _amount, _delegatee, _claimer);
    }

    /// @inheritdoc StakerPermitAndStake
    function permitAndStakeMore(
        DepositIdentifier _depositId,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override whenNotPaused nonReentrant {
        Deposit storage deposit = deposits[_depositId];
        _revertIfNotDepositOwner(deposit, msg.sender);

        try
            IERC20Permit(address(STAKE_TOKEN)).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s)
        {} catch {}
        _stakeMore(deposit, _depositId, _amount);
    }

    /// @notice Sets the whitelist for the staker. If the whitelist is not set, the staking will be open to all users.
    /// @param _stakerWhitelist The whitelist to set.
    function setStakerWhitelist(Whitelist _stakerWhitelist) external {
        _revertIfNotAdmin();
        emit StakerWhitelistSet(_stakerWhitelist);
        stakerWhitelist = _stakerWhitelist;
    }

    /// @notice Sets the whitelist for the contribution. If the whitelist is not set, the contribution will be open to all users.
    /// @param _contributionWhitelist The whitelist to set.
    function setContributionWhitelist(Whitelist _contributionWhitelist) external {
        _revertIfNotAdmin();
        emit ContributionWhitelistSet(_contributionWhitelist);
        contributionWhitelist = _contributionWhitelist;
    }

    /// @notice Pauses the contract.
    function pause() external whenNotPaused {
        _revertIfNotAdmin();
        _pause();
    }

    /// @notice Unpauses the contract.
    function unpause() external whenPaused {
        _revertIfNotAdmin();
        _unpause();
    }

    // @inheritdoc Staker
    function withdraw(
        Staker.DepositIdentifier _depositId,
        uint256 _amount
    ) external override whenNotPaused nonReentrant {
        Deposit storage deposit = deposits[_depositId];
        _revertIfNotDepositOwner(deposit, msg.sender);
        _withdraw(deposit, _depositId, _amount);
    }

    /// @inheritdoc Staker
    function claimReward(
        Staker.DepositIdentifier _depositId
    ) external override whenNotPaused nonReentrant returns (uint256) {
        Deposit storage deposit = deposits[_depositId];
        if (deposit.claimer != msg.sender && deposit.owner != msg.sender) {
            revert Staker__Unauthorized("not claimer or owner", msg.sender);
        }
        return _claimReward(_depositId, deposit, msg.sender);
    }

    /// @notice Contributes to a grant round.
    /// @param _depositId The deposit identifier for the staked amount.
    /// @param _grantRoundAddress The address of the grant round.
    /// @param _votingDelegatee The address of the delegatee to delegate voting power to.
    /// @param _amount The amount of reward tokens to contribute.
    /// @param _signature The signature for the IGrantRound.signup call.
    function contribute(
        DepositIdentifier _depositId,
        address _grantRoundAddress,
        address _votingDelegatee,
        uint256 _amount,
        bytes32 _signature
    )
        public
        whenNotPaused
        nonReentrant
        onlyWhitelistedIfWhitelistIsSet(contributionWhitelist)
        returns (uint256 amountContributedToGrant)
    {
        _revertIfAddressZero(_grantRoundAddress);

        Deposit storage deposit = deposits[_depositId];

        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 unclaimedAmount = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;
        require(_amount <= unclaimedAmount, CantAfford(_amount, unclaimedAmount));

        uint256 fee = claimFeeParameters.feeAmount;
        if (fee == 0) {
            amountContributedToGrant = _amount;
        } else {
            require(_amount >= fee, CantAfford(fee, _amount));
            amountContributedToGrant = _amount - fee;
        }

        // Update deposit's reward checkpoint by the gross amount used
        uint256 scaledAmountConsumed = _amount * SCALE_FACTOR;
        deposit.scaledUnclaimedRewardCheckpoint = deposit.scaledUnclaimedRewardCheckpoint - scaledAmountConsumed;

        // Update earning power, similar to _claimReward logic
        uint256 newCalculatedEarningPower = earningPowerCalculator.getEarningPower(
            deposit.balance,
            deposit.owner,
            deposit.delegatee
        );

        totalEarningPower = _calculateTotalEarningPower(
            deposit.earningPower,
            newCalculatedEarningPower,
            totalEarningPower
        );
        depositorTotalEarningPower[deposit.owner] = _calculateTotalEarningPower(
            deposit.earningPower,
            newCalculatedEarningPower,
            depositorTotalEarningPower[deposit.owner]
        );
        deposit.earningPower = newCalculatedEarningPower.toUint96();

        // Emit Staker.RewardClaimed event for compatibility/observers, using net amount
        emit RewardClaimed(_depositId, msg.sender, amountContributedToGrant, deposit.earningPower);

        // Transfer fee if applicable
        if (fee > 0) {
            SafeERC20.safeTransfer(REWARD_TOKEN, claimFeeParameters.feeCollector, fee);
        }

        // Perform grant round actions with the net amount
        SafeERC20.safeIncreaseAllowance(REWARD_TOKEN, _grantRoundAddress, amountContributedToGrant);
        require(
            IGrantRound(_grantRoundAddress).signup(amountContributedToGrant, _votingDelegatee, _signature) > 0,
            GrantRoundSignUpFailed(_grantRoundAddress, msg.sender, amountContributedToGrant, _votingDelegatee)
        );

        emit RewardContributed(_depositId, msg.sender, _grantRoundAddress, amountContributedToGrant);

        return amountContributedToGrant;
    }
}
