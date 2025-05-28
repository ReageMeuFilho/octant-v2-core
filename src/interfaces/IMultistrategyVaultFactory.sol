// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

/**
 * @title Yearn Vault Factory Interface
 * @author yearn.finance
 * @notice Interface for Yearn Vault Factory that can deploy ERC4626 compliant vaults
 */
interface IMultistrategyVaultFactory {
    // Events
    event NewVault(address indexed vault_address, address indexed asset);
    event UpdateProtocolFeeBps(uint16 old_fee_bps, uint16 new_fee_bps);
    event UpdateProtocolFeeRecipient(address indexed old_fee_recipient, address indexed new_fee_recipient);
    event UpdateCustomProtocolFee(address indexed vault, uint16 new_custom_protocol_fee);
    event RemovedCustomProtocolFee(address indexed vault);
    event FactoryShutdown();
    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);
    event UpdatePendingGovernance(address indexed newPendingGovernance);

    // Constants
    function API_VERSION() external pure returns (string memory);
    function MAX_FEE_BPS() external pure returns (uint16);
    function FEE_BPS_MASK() external pure returns (uint256);

    // View functions
    function VAULT_ORIGINAL() external view returns (address);
    function shutdown() external view returns (bool);
    function governance() external view returns (address);
    function pendingGovernance() external view returns (address);
    function name() external view returns (string memory);

    // Core functionality
    function deployNewVault(
        address asset,
        string memory _name,
        string memory symbol,
        address roleManager,
        uint256 profitMaxUnlockTime
    ) external returns (address);

    function vaultOriginal() external view returns (address);
    function apiVersion() external pure returns (string memory);
    function protocolFeeConfig(address vault) external view returns (uint16, address);
    function useCustomProtocolFee(address vault) external view returns (bool);

    // Administrative functions
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external;
    function setProtocolFeeRecipient(address newProtocolFeeRecipient) external;
    function setCustomProtocolFeeBps(address vault, uint16 newCustomProtocolFee) external;
    function removeCustomProtocolFee(address vault) external;
    function shutdownFactory() external;
    function transferGovernance(address newGovernance) external;
    function acceptGovernance() external;
}
