// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { Staker } from "staker/Staker.sol";
import { StakerDelegateSurrogateVotes } from "staker/extensions/StakerDelegateSurrogateVotes.sol";
import { StakerPermitAndStake } from "staker/extensions/StakerPermitAndStake.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

import { Whitelist } from "./whitelist/Whitelist.sol";
import { IWhitelist } from "./whitelist/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "./IWhitelistedEarningPowerCalculator.sol";

// TODO: Bind this to the real contract.
interface IGrantRound {
    function signUp(uint256 _amount, uint256 _preference) external returns (bool success);
}

/// @title RegenStaker
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This contract is an extended version of the Staker contract by [ScopeLift](https://scopelift.co).
contract RegenStaker is Staker, StakerDelegateSurrogateVotes, StakerPermitAndStake, StakerOnBehalf, Pausable {
    IWhitelist public stakerWhitelist;
    IWhitelist public contributionWhitelist;

    error NotWhitelisted(IWhitelist whitelist, address user);
    error NotImplemented();
    error CantAfford(uint256 requested, uint256 available);
    error GrantRoundSignUpFailed(address grantRound, address contributor, uint256 amount, uint256 preference);

    event StakerWhitelistSet(IWhitelist whitelist);
    event ContributionWhitelistSet(IWhitelist whitelist);
    event EarningPowerWhitelistSet(IWhitelist whitelist);
    event RewardContributed(
        Staker.DepositIdentifier depositId,
        address contributor,
        address grantRound,
        uint256 amount,
        uint256 preference
    );

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
        // Initialize whitelists
        stakerWhitelist = address(_stakerWhitelist) == address(0) ? new Whitelist() : _stakerWhitelist;
        contributionWhitelist = address(_contributionWhitelist) == address(0)
            ? new Whitelist()
            : _contributionWhitelist;

        // Override the maximum reward token fee for claiming rewards
        MAX_CLAIM_FEE = 1e18;
        // At deployment, there should be no reward claiming fee
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

    /// @dev TODO: Implement this.
    function contribute(
        DepositIdentifier _depositId,
        address _grantRoundAddress,
        uint256 _amount,
        uint256 _preference
    ) public whenNotPaused {
        _revertIfAddressZero(_grantRoundAddress);

        require(
            contributionWhitelist == IWhitelist(address(0)) || contributionWhitelist.isWhitelisted(msg.sender),
            NotWhitelisted(contributionWhitelist, msg.sender)
        );

        // Make sure _amount is not greater than the amount of unclaimed rewards for this deposit.
        // Get the deposit
        Deposit storage deposit = deposits[_depositId];

        // Calculate the unclaimed rewards for this deposit
        uint256 unclaimedAmount = _scaledUnclaimedReward(deposit) / SCALE_FACTOR;

        // Ensure the amount is not greater than the unclaimed rewards
        require(_amount <= unclaimedAmount, CantAfford(_amount, unclaimedAmount));

        // Update the deposit's unclaimed rewards by resetting the checkpoint
        uint256 scaledAmount = _amount * SCALE_FACTOR;
        deposit.scaledUnclaimedRewardCheckpoint = deposit.scaledUnclaimedRewardCheckpoint - scaledAmount;

        // Call the external functions and send the rewards to the grant round
        // TODO: Bind this to the real contract.
        SafeERC20.safeTransfer(REWARD_TOKEN, _grantRoundAddress, _amount);
        require(
            IGrantRound(_grantRoundAddress).signUp(_amount, _preference),
            GrantRoundSignUpFailed(_grantRoundAddress, msg.sender, _amount, _preference)
        );
        emit RewardContributed(_depositId, msg.sender, _grantRoundAddress, _amount, _preference);
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

    /// @notice Sets the whitelist for the earning power. If the whitelist is not set, the earning power will be open to all users.
    /// @notice If the earning power calculator is not implementing a whitelist, this function will revert.
    /// @param _earningPowerWhitelist The whitelist to set.
    function setEarningPowerWhitelist(Whitelist _earningPowerWhitelist) external {
        _revertIfNotAdmin();
        emit EarningPowerWhitelistSet(_earningPowerWhitelist);
        IWhitelistedEarningPowerCalculator(address(earningPowerCalculator)).setWhitelist(_earningPowerWhitelist);
    }

    /// @notice Checks if the earning power whitelist is enabled.
    /// @notice If the earning power calculator is not implementing a whitelist, this function will return false.
    /// @return _isEnabled True if the earning power whitelist is enabled, false otherwise.
    function isEarningPowerWhitelistEnabled() external view returns (bool _isEnabled) {
        try
            IERC165(address(earningPowerCalculator)).supportsInterface(
                type(IWhitelistedEarningPowerCalculator).interfaceId
            )
        returns (bool isSupported) {
            _isEnabled =
                isSupported &&
                IWhitelistedEarningPowerCalculator(address(earningPowerCalculator)).whitelist() !=
                IWhitelist(address(0));
        } catch {
            _isEnabled = false;
        }
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
}
