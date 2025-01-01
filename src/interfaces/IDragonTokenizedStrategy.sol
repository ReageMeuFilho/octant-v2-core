// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.25;

import { ITokenizedStrategy } from "./ITokenizedStrategy.sol";

interface IDragonTokenizedStrategy is ITokenizedStrategy {
    function unlockedShares(address user) external view returns (uint256);

    function getUnlockTime(address user) external view returns (uint256);

    function getUserLockupInfo(
        address user
    )
        external
        view
        returns (
            uint256 unlockTime,
            uint256 lockedShares,
            bool isRageQuit,
            uint256 totalShares,
            uint256 withdrawableShares
        );

    function depositWithLockup(
        uint256 assets,
        address receiver,
        uint256 lockupDuration
    ) external returns (uint256 shares);

    function initiateRageQuit() external;

    function mintWithLockup(uint256 shares, address receiver, uint256 lockupDuration) external returns (uint256 assets);

    function getRemainingCooldown(address user) external view returns (uint256 remainingTime);

    function setLockupDuration(uint256 newDuration) external;

    function setRageQuitCooldownPeriod(uint256 newPeriod) external;

    function minimumLockupDuration() external view returns (uint256);

    function rageQuitCooldownPeriod() external view returns (uint256);

    function regenGovernance() external view returns (address);
}
