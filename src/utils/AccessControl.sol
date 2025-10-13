// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IWhitelist } from "./IWhitelist.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AccessControl
/// @author [Golem Foundation](https://golem.foundation)
/// @notice Flexible access control supporting both allowlist and blocklist modes
/// @dev Implements IWhitelist interface for backward compatibility but adds mode selection
///      In ALLOWLIST mode: listed addresses are allowed (default behavior)
///      In BLOCKLIST mode: listed addresses are blocked, unlisted are allowed
contract AccessControl is IWhitelist, Ownable {
    enum Mode {
        ALLOWLIST, // Listed = allowed, unlisted = denied (default whitelist behavior)
        BLOCKLIST // Listed = blocked, unlisted = allowed (blacklist/denylist behavior)
    }

    error IllegalAccessControlOperation(address account, string reason);
    error EmptyArray();

    event AccessControlAltered(address indexed account, AccessControlOperation indexed operation);
    event ModeSet(Mode indexed newMode);

    enum AccessControlOperation {
        Add,
        Remove
    }

    Mode public mode;
    mapping(address => bool) public isListed;

    /// @param _mode The access control mode (ALLOWLIST or BLOCKLIST)
    constructor(Mode _mode) Ownable(msg.sender) {
        mode = _mode;
        emit ModeSet(_mode);
    }

    /// @notice Set the access control mode
    /// @param _mode The new mode
    /// @dev Can only be called by owner. Changing mode inverts the meaning of all entries.
    function setMode(Mode _mode) external onlyOwner {
        mode = _mode;
        emit ModeSet(_mode);
    }

    /// @inheritdoc IWhitelist
    /// @dev In ALLOWLIST mode: returns true if listed
    ///      In BLOCKLIST mode: returns true if NOT listed (i.e., not blocked)
    function isWhitelisted(address account) external view override returns (bool) {
        if (mode == Mode.ALLOWLIST) {
            return isListed[account]; // Listed = allowed
        } else {
            return !isListed[account]; // Not listed = allowed (not blocked)
        }
    }

    /// @inheritdoc IWhitelist
    /// @dev In ALLOWLIST mode: adds to allowed set
    ///      In BLOCKLIST mode: adds to blocked set
    function addToWhitelist(address[] memory accounts) external override onlyOwner {
        require(accounts.length > 0, EmptyArray());

        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) {
                revert IllegalAccessControlOperation(accounts[i], "Address zero not allowed.");
            }
            if (isListed[accounts[i]]) {
                revert IllegalAccessControlOperation(accounts[i], "Address already listed.");
            }
            isListed[accounts[i]] = true;
            emit AccessControlAltered(accounts[i], AccessControlOperation.Add);
        }
    }

    /// @inheritdoc IWhitelist
    /// @dev In ALLOWLIST mode: adds to allowed set
    ///      In BLOCKLIST mode: adds to blocked set
    function addToWhitelist(address account) external override onlyOwner {
        if (account == address(0)) {
            revert IllegalAccessControlOperation(account, "Address zero not allowed.");
        }
        if (isListed[account]) {
            revert IllegalAccessControlOperation(account, "Address already listed.");
        }

        isListed[account] = true;
        emit AccessControlAltered(account, AccessControlOperation.Add);
    }

    /// @inheritdoc IWhitelist
    function removeFromWhitelist(address[] memory accounts) external override onlyOwner {
        require(accounts.length > 0, EmptyArray());

        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) {
                revert IllegalAccessControlOperation(accounts[i], "Address zero not allowed.");
            }
            if (!isListed[accounts[i]]) {
                revert IllegalAccessControlOperation(accounts[i], "Address not listed.");
            }
            isListed[accounts[i]] = false;
            emit AccessControlAltered(accounts[i], AccessControlOperation.Remove);
        }
    }

    /// @inheritdoc IWhitelist
    function removeFromWhitelist(address account) external override onlyOwner {
        if (account == address(0)) {
            revert IllegalAccessControlOperation(account, "Address zero not allowed.");
        }
        if (!isListed[account]) {
            revert IllegalAccessControlOperation(account, "Address not listed.");
        }
        isListed[account] = false;
        emit AccessControlAltered(account, AccessControlOperation.Remove);
    }
}
