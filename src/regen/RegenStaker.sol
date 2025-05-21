// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

// OpenZeppelin Imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Staker Library Imports
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { Staker } from "staker/Staker.sol";
import { StakerDelegateSurrogateVotes } from "staker/extensions/StakerDelegateSurrogateVotes.sol";
import { StakerPermitAndStake } from "staker/extensions/StakerPermitAndStake.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

// Local Imports
import { Whitelist } from "./whitelist/Whitelist.sol";
import { IWhitelist } from "./whitelist/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "./IWhitelistedEarningPowerCalculator.sol";

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

interface IGrantRound {
    /// @notice Grants voting power to `receiver` by
    /// depositing exactly `assets` of underlying tokens.
    /// @param assets The amount of underlying to deposit in.
    /// @param receiver The address to receive the `shares`.
    /// @param signature The signature of the user.
    /// @return votingPower The actual amount of votingPower issued.
    function signup(uint256 assets, address receiver, bytes32 signature) external returns (uint256 votingPower);

    /// @notice Process a vote for a project with a contribution amount and vote weight
    /// @dev This function validates and processes votes according to the implemented formula
    /// @dev Must check if the user can vote in _processVote
    /// @dev Must check if the project is whitelisted in _processVote
    /// @dev Must update the project tally in _processVote
    /// Only keepers can call this function to prevent spam and ensure proper vote processing.
    /// @param projectId The ID of the project being voted for
    /// @param votingPower the votingPower msg.sender will assign to projectId, must be checked in _processVote by strategist
    function vote(uint256 projectId, uint256 votingPower) external;
}

/// @title RegenStaker
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This contract is an extended version of the Staker contract by [ScopeLift](https://scopelift.co).
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

    event StakerWhitelistSet(IWhitelist whitelist);
    event ContributionWhitelistSet(IWhitelist whitelist);
    event GrantRoundVoteFailed(address grantRound, address contributor, uint256 projectId, uint256 votingPower);
    event RewardContributed(
        DepositIdentifier depositId,
        address contributor,
        address grantRound,
        uint256 amount,
        uint256 preference
    );

    error NotWhitelisted(IWhitelist whitelist, address user);
    error CantAfford(uint256 requested, uint256 available);
    error GrantRoundSignUpFailed(address grantRound, address contributor, uint256 amount, address votingDelegatee);
    error PreferencesAndPreferenceWeightsMustHaveTheSameLength();
    error InvalidNumberOfPreferences(uint256 actual, uint256 min, uint256 max); // Changed uint to uint256 for consistency

    constructor(
        IERC20 _rewardsToken,
        IERC20Staking _stakeToken,
        address _admin,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IEarningPowerCalculator _earningPowerCalculator
    )
        Staker(
            _rewardsToken,
            _stakeToken,
            _earningPowerCalculator,
            1e18, // maxBumpTip
            _admin
        )
        StakerPermitAndStake(_stakeToken)
        StakerDelegateSurrogateVotes(_stakeToken)
        EIP712("RegenStaker", "1")
    {
        stakerWhitelist = address(_stakerWhitelist) == address(0) ? new Whitelist() : _stakerWhitelist;
        contributionWhitelist = address(_contributionWhitelist) == address(0)
            ? new Whitelist()
            : _contributionWhitelist;

        MAX_CLAIM_FEE = 1e18;
        _setClaimFeeParameters(ClaimFeeParameters({ feeAmount: 0, feeCollector: address(0) }));
    }

    /// @notice Stakes a given amount of stake token and delegates voting power to a specific delegatee.
    /// @param amount The amount of stake token to stake.
    /// @param delegatee The address of the delegatee to delegate voting power to.
    /// @return _depositId The deposit identifier for the staked amount.
    function stake(
        uint256 amount,
        address delegatee
    ) external override(Staker) whenNotPaused nonReentrant returns (DepositIdentifier _depositId) {
        require(
            stakerWhitelist == IWhitelist(address(0)) || stakerWhitelist.isWhitelisted(msg.sender),
            NotWhitelisted(stakerWhitelist, msg.sender)
        );
        _depositId = _stake(msg.sender, amount, delegatee, msg.sender);
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

    /// @notice Withdraw staked tokens from an existing deposit.
    function withdraw(
        Staker.DepositIdentifier _depositId,
        uint256 _amount
    ) external override whenNotPaused nonReentrant {
        Deposit storage deposit = deposits[_depositId];
        _revertIfNotDepositOwner(deposit, msg.sender);
        _withdraw(deposit, _depositId, _amount);
    }

    /// @notice Claim reward tokens earned by a given deposit.
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
    /// @param _preferences The preferences for the contribution.
    /// @param _preferenceWeights The preference weights for the contribution.
    /// @param _signature The signature for the IGrantRound.signup call.
    function contribute(
        DepositIdentifier _depositId,
        address _grantRoundAddress,
        address _votingDelegatee,
        uint256 _amount,
        uint256[] memory _preferences,
        uint256[] memory _preferenceWeights,
        bytes32 _signature
    ) public whenNotPaused nonReentrant returns (uint256 amountContributedToGrant) {
        _revertIfAddressZero(_grantRoundAddress);
        require(
            contributionWhitelist == IWhitelist(address(0)) || contributionWhitelist.isWhitelisted(msg.sender),
            NotWhitelisted(contributionWhitelist, msg.sender)
        );
        require(
            _preferences.length == _preferenceWeights.length,
            PreferencesAndPreferenceWeightsMustHaveTheSameLength()
        );
        require(
            _preferences.length >= MIN_PREFERENCES && _preferences.length <= MAX_PREFERENCES,
            InvalidNumberOfPreferences(_preferences.length, MIN_PREFERENCES, MAX_PREFERENCES)
        );

        Deposit storage deposit = deposits[_depositId];

        _checkpointGlobalReward();
        _checkpointReward(deposit);

        uint256 unclaimedAmount = deposit.scaledUnclaimedRewardCheckpoint / SCALE_FACTOR;
        require(_amount <= unclaimedAmount, CantAfford(_amount, unclaimedAmount));

        // Account for claim fees
        uint256 fee = claimFeeParameters.feeAmount;
        require(_amount >= fee, CantAfford(fee, _amount));
        amountContributedToGrant = _amount - fee;

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

        emit RewardContributed(
            _depositId,
            msg.sender,
            _grantRoundAddress,
            amountContributedToGrant, // Log the net amount contributed to grant
            _preferences.length > 0 ? _preferences[0] : type(uint256).max
        );

        for (uint256 i = 0; i < _preferences.length; i++) {
            // Note: _preferenceWeights are used here. Ensure they relate to amountContributedToGrant if intended.
            try IGrantRound(_grantRoundAddress).vote(_preferences[i], _preferenceWeights[i]) {} catch {
                emit GrantRoundVoteFailed(_grantRoundAddress, msg.sender, _preferences[i], _preferenceWeights[i]);
            }
        }

        return amountContributedToGrant;
    }
}
