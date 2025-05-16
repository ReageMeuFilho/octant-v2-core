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

// Interfaces (if defined locally)
// TODO: Bind this to the real contract.
interface IGrantRound {
    /// @notice Grants voting power to `receiver` by
    /// depositing exactly `assets` of underlying tokens.
    /// @param assets The amount of underlying to deposit in.
    /// @param receiver The address to receive the `shares`.
    /// @return votingPower The actual amount of votingPower issued.
    function signup(uint256 assets, address receiver) external returns (uint256 votingPower);

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
contract RegenStaker is Staker, StakerDelegateSurrogateVotes, StakerPermitAndStake, StakerOnBehalf, Pausable {
    IWhitelist public stakerWhitelist;
    IWhitelist public contributionWhitelist;

    uint256 public constant MIN_PREFERENCES = 1;
    uint256 public constant MAX_PREFERENCES = 16;

    event StakerWhitelistSet(IWhitelist whitelist);
    event ContributionWhitelistSet(IWhitelist whitelist);
    event EarningPowerWhitelistSet(IWhitelist whitelist); // Note: No direct setter in RegenStaker currently
    event GrantRoundVoteFailed(address grantRound, address contributor, uint256 projectId, uint256 votingPower);

    error NotWhitelisted(IWhitelist whitelist, address user);
    error CantAfford(uint256 requested, uint256 available);
    error GrantRoundSignUpFailed(address grantRound, address contributor, uint256 amount, address votingDelegatee);
    error PreferencesAndPreferenceWeightsMustHaveTheSameLength();
    error InvalidNumberOfPreferences(uint256 actual, uint256 min, uint256 max); // Changed uint to uint256 for consistency
    error NotImplemented(); // Note: Currently unused

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
    ) external override(Staker) whenNotPaused returns (DepositIdentifier _depositId) {
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
    function withdraw(Staker.DepositIdentifier _depositId, uint256 _amount) external override whenNotPaused {
        Deposit storage deposit = deposits[_depositId];
        _revertIfNotDepositOwner(deposit, msg.sender);
        _withdraw(deposit, _depositId, _amount);
    }

    /// @notice Claim reward tokens earned by a given deposit.
    function claimReward(Staker.DepositIdentifier _depositId) external override whenNotPaused returns (uint256) {
        Deposit storage deposit = deposits[_depositId];
        if (deposit.claimer != msg.sender && deposit.owner != msg.sender) {
            revert Staker__Unauthorized("not claimer or owner", msg.sender);
        }
        return _claimReward(_depositId, deposit, msg.sender);
    }

    function contribute(
        DepositIdentifier _depositId,
        address _grantRoundAddress,
        address _votingDelegatee,
        uint256 _amount,
        uint256[] memory _preferences,
        uint256[] memory _preferenceWeights
    ) public whenNotPaused {
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
        uint256 unclaimedAmount = _scaledUnclaimedReward(deposit) / SCALE_FACTOR;
        require(_amount <= unclaimedAmount, CantAfford(_amount, unclaimedAmount));

        uint256 scaledAmount = _amount * SCALE_FACTOR;
        deposit.scaledUnclaimedRewardCheckpoint = deposit.scaledUnclaimedRewardCheckpoint - scaledAmount;

        SafeERC20.safeIncreaseAllowance(REWARD_TOKEN, _grantRoundAddress, _amount);
        require(
            IGrantRound(_grantRoundAddress).signup(_amount, _votingDelegatee) > 0,
            GrantRoundSignUpFailed(_grantRoundAddress, msg.sender, _amount, _votingDelegatee)
        );

        for (uint256 i = 0; i < _preferences.length; i++) {
            try IGrantRound(_grantRoundAddress).vote(_preferences[i], _preferenceWeights[i]) {} catch {
                emit GrantRoundVoteFailed(_grantRoundAddress, msg.sender, _preferences[i], _preferenceWeights[i]);
            }
        }
    }
}
