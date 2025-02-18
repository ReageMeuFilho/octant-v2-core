// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IDepositContract} from "src/dragons/eth2StakeVault/NonfungibleDepositManager.sol";

contract MockDepositContract is IDepositContract {
    // Event to track deposits for testing
    event DepositMade(
        bytes pubkey,
        bytes withdrawal_credentials,
        bytes signature,
        bytes32 deposit_data_root
    );

    // Track total deposits made
    uint256 public totalDeposits;
    
    // Store last deposit details for verification
    bytes public lastPubkey;
    bytes public lastWithdrawalCredentials;
    bytes public lastSignature;
    bytes32 public lastDepositDataRoot;

    /**
     * @notice Mock implementation of the deposit function
     * @dev Stores deposit details and emits event for testing
     */
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable {
        require(msg.value == 32 ether, "DepositContract: deposit value must be 32 ether");
        require(pubkey.length == 48, "DepositContract: invalid pubkey length");
        require(withdrawal_credentials.length == 32, "DepositContract: invalid withdrawal credentials length");
        require(signature.length == 96, "DepositContract: invalid signature length");
        
        // Store deposit details
        lastPubkey = pubkey;
        lastWithdrawalCredentials = withdrawal_credentials;
        lastSignature = signature;
        lastDepositDataRoot = deposit_data_root;
        
        totalDeposits += 1;
        
        emit DepositMade(
            pubkey,
            withdrawal_credentials,
            signature,
            deposit_data_root
        );
    }
}
