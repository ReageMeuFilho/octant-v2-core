// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./AbstractHatsManager.sol";

/**
 * @title DragonHatter
 * @notice Manages emergency response roles through a hierarchical hat structure
 * @dev Implements emergency response logic on top of AbstractHatsManager
 */
contract DragonHatter is AbstractHatsManager {
    // Cooldown period for emergency actions (24 hours)
    uint256 public constant COOLDOWN_PERIOD = 24 hours;
    
    // Reuse hatRoles mapping to store vault addresses (saves gas vs new mapping)
    // roleHats mapping stores vault => hatId
    
    mapping(address => uint256) public lastActionTimestamp;

    event ResponderAdded(address vault, address responder, uint256 hatId);
    event ResponderRemoved(address vault, address responder, uint256 hatId);

    constructor(
        address hats,
        uint256 _adminHat
    ) AbstractHatsManager(
        hats,
        _adminHat,
        "Emergency Response Branch"
    ) {}

    /**
     * @notice Creates a new emergency responder hat under the branch
     * @param vault Address of the vault to create responder hat for
     * @param maxSupply Maximum number of responders for this vault
     * @param initialResponders Initial set of responder addresses
     * @return hatId The ID of the newly created responder hat
     */
    function createVaultEmergencyHat(
        address vault,
        uint256 maxSupply,
        address[] calldata initialResponders
    ) external returns (uint256 hatId) {
        // Convert vault address to roleId to reuse storage
        bytes32 roleId = bytes32(uint256(uint160(vault)));
        
        // Reuse createRole logic from abstract contract
        hatId = this.createRole(
            roleId,
            "Vault Emergency Responder",
            maxSupply,
            initialResponders
        );

        // Emit vault-specific event
        // emit ResponderHatCreated(vault, hatId);
    }

    /**
     * @notice Adds a new responder for a vault
     * @param vault The vault address
     * @param responder The responder address to add
     */
    function addResponder(address vault, address responder) external {
        bytes32 roleId = bytes32(uint256(uint160(vault)));
        
        // Reuse grantRole logic
        this.grantRole(roleId, responder);
        
        // Emit vault-specific event
        emit ResponderAdded(vault, responder, roleHats[roleId]);
    }

    /**
     * @notice Removes a responder from a vault
     * @param vault The vault address
     * @param responder The responder address to remove
     */
    function removeResponder(address vault, address responder) external {
        bytes32 roleId = bytes32(uint256(uint160(vault)));
        
        // Reuse revokeRole logic
        this.revokeRole(roleId, responder);
        
        // Emit vault-specific event
        emit ResponderRemoved(vault, responder, roleHats[roleId]);
    }

    /**
     * @notice Checks if an address is eligible to wear a specific vault's responder hat
     * @param wearer The address to check
     * @param hatId The responder hat ID being checked
     * @return eligible Whether the address is approved
     * @return standing Whether the address is not in cooldown
     */
    function getWearerStatus(
        address wearer,
        uint256 hatId
    ) external view override returns (bool eligible, bool standing) {
        // Convert hatId back to vault address using hatRoles mapping
        bytes32 roleId = hatRoles[hatId];
        require(roleId != bytes32(0), "Invalid responder hat");
        
        // Check if the hat is active and the wearer's cooldown period has passed
        standing = block.timestamp >= lastActionTimestamp[wearer] + COOLDOWN_PERIOD;
        eligible = HATS.isAdminOfHat(msg.sender, adminHat);
        
        return (eligible, standing);
    }

    /**
     * @notice Helper to get vault address from hat ID
     * @param hatId The responder hat ID
     * @return vault The associated vault address
     */
    function getVaultFromHat(uint256 hatId) public view returns (address vault) {
        bytes32 roleId = hatRoles[hatId];
        require(roleId != bytes32(0), "Invalid hat");
        return address(uint160(uint256(roleId)));
    }

    /**
     * @notice Helper to get hat ID from vault address
     * @param vault The vault address
     * @return hatId The associated responder hat ID
     */
    function getHatFromVault(address vault) public view returns (uint256 hatId) {
        bytes32 roleId = bytes32(uint256(uint160(vault)));
        return roleHats[roleId];
    }
}