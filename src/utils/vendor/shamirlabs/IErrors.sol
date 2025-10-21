// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

/**
 * @title IErrors
 * @author Shamir Labs
 * @custom:vendor Shamir Labs / Diva Protocol
 * @notice Common error definitions
 */
interface IErrors {
    error ZeroAddress();
    error ZeroAmount();
    error AccessDenied();
    error InvalidSignature();
    error OnlyValidatorManager();
    // Operator fee higher than 10%
    error ErrorHighOperatorFee();
}
