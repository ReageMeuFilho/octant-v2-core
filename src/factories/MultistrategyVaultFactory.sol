/* solhint-disable gas-custom-errors */
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import { IMultistrategyVaultFactory } from "src/factories/interfaces/IMultistrategyVaultFactory.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";
/**
 * @title Yearn Vault Factory
 * @author yearn.finance
 * @notice
 *    This vault Factory is ported from the original vyper Yearn Vault Factory.
 *    It can be used by anyone wishing to deploy their own
 *    ERC4626 compliant Yearn V3 Vault of the same API version.
 *
 *    The factory clones new vaults from its specific `VAULT_ORIGINAL`
 *    immutable address set on creation of the factory.
 *
 *    The deployments are done through create2 with a specific `salt`
 *    that is derived from a combination of the deployer's address,
 *    the underlying asset used, as well as the name and symbol specified.
 *    Meaning a deployer will not be able to deploy the exact same vault
 *    twice and will need to use different name and or symbols for vaults
 *    that use the same other parameters such as `asset`.
 *
 *    The factory also holds the protocol fee configs for each vault and strategy
 *    of its specific `API_VERSION` that determine how much of the fees
 *    charged are designated "protocol fees" and sent to the designated
 *    `fee_recipient`. The protocol fees work through a revenue share system,
 *    where if the vault or strategy decides to charge X amount of total
 *    fees during a `report` the protocol fees are a percent of X.
 *    The protocol fees will be sent to the designated fee_recipient and
 *    then (X - protocol_fees) will be sent to the vault/strategy specific
 *    fee recipient.
 */

contract MultistrategyVaultFactory is IMultistrategyVaultFactory {
    // Constants
    string public constant override API_VERSION = "3.0.4";
    uint16 public constant override MAX_FEE_BPS = 5_000; // 50%
    uint256 public constant override FEE_BPS_MASK = 2 ** 16 - 1;

    // Immutables
    address public immutable override VAULT_ORIGINAL;

    // State variables
    bool public override shutdown;
    address public override governance;
    address public override pendingGovernance;
    string public override name;

    // Protocol Fee Data is packed into a single uint256 slot
    // 72 bits Empty | 160 bits fee recipient | 16 bits fee bps | 8 bits custom flag
    uint256 private defaultProtocolFeeData;
    mapping(address => uint256) private customProtocolFeeData;

    constructor(string memory _name, address _vaultOriginal, address _governance) {
        name = _name;
        VAULT_ORIGINAL = _vaultOriginal;
        governance = _governance;
    }

    function deployNewVault(
        address asset,
        string memory _name,
        string memory symbol,
        address roleManager,
        uint256 profitMaxUnlockTime
    ) external returns (address) {
        // Make sure the factory is not shutdown
        require(!shutdown, "shutdown");

        // Clone a new version of the vault using create2
        bytes32 salt = keccak256(abi.encode(msg.sender, asset, _name, symbol));
        address vaultAddress = _createClone(VAULT_ORIGINAL, salt);

        IMultistrategyVault(vaultAddress).initialize(asset, _name, symbol, roleManager, profitMaxUnlockTime);

        emit NewVault(vaultAddress, asset);
        return vaultAddress;
    }

    function vaultOriginal() external view returns (address) {
        return VAULT_ORIGINAL;
    }

    function apiVersion() external pure override returns (string memory) {
        return API_VERSION;
    }

    function protocolFeeConfig(address vault) external view override returns (uint16, address) {
        if (vault == address(0)) {
            vault = msg.sender;
        }

        // If there is a custom protocol fee set we return it
        uint256 configData = customProtocolFeeData[vault];
        if (_unpackCustomFlag(configData)) {
            // Always use the default fee recipient even with custom fees
            return (_unpackProtocolFee(configData), _unpackFeeRecipient(defaultProtocolFeeData));
        } else {
            // Otherwise return the default config
            configData = defaultProtocolFeeData;
            return (_unpackProtocolFee(configData), _unpackFeeRecipient(configData));
        }
    }

    function useCustomProtocolFee(address vault) external view override returns (bool) {
        return _unpackCustomFlag(customProtocolFeeData[vault]);
    }

    function setProtocolFeeBps(uint16 newProtocolFeeBps) external override {
        require(msg.sender == governance, "not governance");
        require(newProtocolFeeBps <= MAX_FEE_BPS, "fee too high");

        // Cache the current default protocol fee
        uint256 defaultFeeData = defaultProtocolFeeData;
        address recipient = _unpackFeeRecipient(defaultFeeData);

        require(recipient != address(0), "no recipient");

        // Set the new fee
        defaultProtocolFeeData = _packProtocolFeeData(recipient, newProtocolFeeBps, false);

        emit UpdateProtocolFeeBps(_unpackProtocolFee(defaultFeeData), newProtocolFeeBps);
    }

    function setProtocolFeeRecipient(address newProtocolFeeRecipient) external override {
        require(msg.sender == governance, "not governance");
        require(newProtocolFeeRecipient != address(0), "zero address");

        uint256 defaultFeeData = defaultProtocolFeeData;

        defaultProtocolFeeData = _packProtocolFeeData(
            newProtocolFeeRecipient,
            _unpackProtocolFee(defaultFeeData),
            false
        );

        emit UpdateProtocolFeeRecipient(_unpackFeeRecipient(defaultFeeData), newProtocolFeeRecipient);
    }

    function setCustomProtocolFeeBps(address vault, uint16 newCustomProtocolFee) external override {
        require(msg.sender == governance, "not governance");
        require(newCustomProtocolFee <= MAX_FEE_BPS, "fee too high");
        require(_unpackFeeRecipient(defaultProtocolFeeData) != address(0), "no recipient");

        customProtocolFeeData[vault] = _packProtocolFeeData(address(0), newCustomProtocolFee, true);

        emit UpdateCustomProtocolFee(vault, newCustomProtocolFee);
    }

    function removeCustomProtocolFee(address vault) external override {
        require(msg.sender == governance, "not governance");

        // Reset the custom fee to 0 and flag to False
        customProtocolFeeData[vault] = _packProtocolFeeData(address(0), 0, false);

        emit RemovedCustomProtocolFee(vault);
    }

    function shutdownFactory() external override {
        require(msg.sender == governance, "not governance");
        require(shutdown == false, "shutdown");

        shutdown = true;

        emit FactoryShutdown();
    }

    function transferGovernance(address newGovernance) external override {
        require(msg.sender == governance, "not governance");
        pendingGovernance = newGovernance;

        emit UpdatePendingGovernance(newGovernance);
    }

    function acceptGovernance() external override {
        require(msg.sender == pendingGovernance, "not pending governance");

        address oldGovernance = governance;

        governance = msg.sender;
        pendingGovernance = address(0);

        emit GovernanceTransferred(oldGovernance, msg.sender);
    }

    // Helper function to create a minimal proxy clone
    function _createClone(address target, bytes32 salt) internal returns (address result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            result := create2(0, clone, 0x37, salt)
        }
        return result;
    }

    function _unpackProtocolFee(uint256 configData) internal pure returns (uint16) {
        return uint16((configData >> 8) & FEE_BPS_MASK);
    }

    function _unpackFeeRecipient(uint256 configData) internal pure returns (address) {
        return address(uint160(configData >> 24));
    }

    function _unpackCustomFlag(uint256 configData) internal pure returns (bool) {
        return (configData & 1) == 1;
    }

    function _packProtocolFeeData(address recipient, uint16 fee, bool custom) internal pure returns (uint256) {
        return (uint256(uint160(recipient)) << 24) | (uint256(fee) << 8) | (custom ? 1 : 0);
    }
}
