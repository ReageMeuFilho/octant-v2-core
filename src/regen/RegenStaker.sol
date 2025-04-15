// SPDX-License-Identifier: AGPL-3.0-only
// This contract inherits from Staker.sol by [ScopeLift](https://scopelift.co)
// Staker.sol is licensed under AGPL-3.0-only.
// Users of this should ensure compliance with the AGPL-3.0-only license terms of the inherited Staker.sol contract.

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Staker } from "staker/Staker.sol";
import { StakerDelegateSurrogateVotes } from "staker/extensions/StakerDelegateSurrogateVotes.sol";
import { StakerPermitAndStake } from "staker/extensions/StakerPermitAndStake.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { RegenEarningPowerCalculator } from "./RegenEarningPowerCalculator.sol";
import { Whitelist } from "./whitelist/Whitelist.sol";
import { IWhitelist } from "./whitelist/IWhitelist.sol";
import { IWhitelistedEarningPowerCalculator } from "./IWhitelistedEarningPowerCalculator.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

error NotWhitelisted(IWhitelist whitelist, address user);
error NotImplemented();

event StakerWhitelistSet(IWhitelist whitelist);
event ContributionWhitelistSet(IWhitelist whitelist);
event EarningPowerWhitelistSet(IWhitelist whitelist);

/// @title RegenStaker
/// @author [Golem Foundation](https://golem.foundation)
/// @notice This contract is an extended version of the Staker contract by [ScopeLift](https://scopelift.co).
contract RegenStaker is Staker, StakerDelegateSurrogateVotes, StakerPermitAndStake, StakerOnBehalf, Pausable {
    IWhitelist public stakerWhitelist;
    IWhitelist public contributionWhitelist;

    constructor(
        IERC20 _rewardsToken,
        IERC20Staking _stakeToken,
        address _admin,
        IWhitelist _stakerWhitelist,
        IWhitelist _contributionWhitelist,
        IWhitelist _earningPowerWhitelist
    )
        Staker(
            _rewardsToken,
            _stakeToken,
            new RegenEarningPowerCalculator(_admin, _earningPowerWhitelist),
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

        // Earning power calculator might be implementing a whitelist or not.
        try
            IERC165(address(earningPowerCalculator)).supportsInterface(
                type(IWhitelistedEarningPowerCalculator).interfaceId
            )
        returns (bool isSupported) {
            if (isSupported) {
                IWhitelist earningPowerWhitelist = address(_earningPowerWhitelist) == address(0)
                    ? new Whitelist()
                    : _earningPowerWhitelist;
                IWhitelistedEarningPowerCalculator(address(earningPowerCalculator)).setWhitelist(earningPowerWhitelist);
            }
        } catch {}

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
    function contribute(uint256) public view whenNotPaused {
        require(
            contributionWhitelist == IWhitelist(address(0)) || contributionWhitelist.isWhitelisted(msg.sender),
            NotWhitelisted(contributionWhitelist, msg.sender)
        );
        revert NotImplemented();
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
}
