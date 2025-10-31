// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IHatsEligibility } from "src/utils/hats/interfaces/IHatsEligibility.sol";
import { IHatsToggle } from "src/utils/hats/interfaces/IHatsToggle.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Hats__InvalidAddressFor, Hats__InvalidHat, Hats__DoesNotHaveThisHat, Hats__HatAlreadyExists, Hats__HatDoesNotExist, Hats__TooManyInitialHolders, Hats__NotAdminOfHat } from "./HatsErrors.sol";

/**
 * @title AbstractHatsManager
 * @notice Abstract pattern for managing hierarchical roles through Hats Protocol
 * @dev Implements base logic for creating and managing role-based hats under a branch
 */
abstract contract AbstractHatsManager is ReentrancyGuard, IHatsEligibility, IHatsToggle {
    IHats public immutable HATS;

    // Core hat structure
    uint256 public immutable adminHat; // Parent admin hat
    uint256 public immutable branchHat; // Branch admin hat

    // Role management
    mapping(bytes32 => uint256) public roleHats; // Maps role identifiers to hat IDs
    mapping(uint256 => bytes32) public hatRoles; // Reverse mapping of hats to role identifiers

    bool public isActive = true;

    event RoleHatCreated(bytes32 roleId, uint256 hatId);
    event RoleGranted(bytes32 roleId, address account, uint256 hatId);
    event RoleRevoked(bytes32 roleId, address account, uint256 hatId);

    /**
     * @notice Initializes the hat hierarchy
     * @param hats The Hats protocol address
     * @param _adminHat The admin hat ID that will have admin privileges
     * @param _branchHat The branch hat ID
     */
    constructor(address hats, uint256 _adminHat, uint256 _branchHat) {
        require(hats != address(0), Hats__InvalidAddressFor("Hats", hats));
        HATS = IHats(hats);

        require(HATS.isWearerOfHat(msg.sender, _adminHat), Hats__DoesNotHaveThisHat(msg.sender, _adminHat));
        adminHat = _adminHat;
        branchHat = _branchHat;
    }

    /**
     * @notice Allows admin to toggle role availability
     */
    function toggleBranch() external virtual {
        require(HATS.isWearerOfHat(msg.sender, adminHat), Hats__DoesNotHaveThisHat(msg.sender, adminHat));
        isActive = !isActive;
    }

    /**
     * @notice Virtual function to check if an address is eligible for a role
     * @dev Must be implemented by inheriting contracts
     */
    function getWearerStatus(
        address wearer,
        uint256 hatId
    ) external view virtual override returns (bool eligible, bool standing);

    /**
     * @notice Checks if roles are currently enabled
     * @param hatId The hat ID being checked
     * @return bool Whether the hat is active
     */
    function getHatStatus(uint256 hatId) external view override returns (bool) {
        require(hatId == branchHat || hatRoles[hatId] != 0, Hats__InvalidHat(hatId));
        return isActive;
    }

    /**
     * @notice Grants a role to an address by minting the corresponding hat
     * @dev This function may only be called by the admin hat of this contract
     * @param roleId The role to grant
     * @param account The address to receive the role
     */
    function grantRole(bytes32 roleId, address account) public virtual {
        require(HATS.isWearerOfHat(msg.sender, adminHat), Hats__DoesNotHaveThisHat(msg.sender, adminHat));
        require(account != address(0), Hats__InvalidAddressFor("account", account));

        uint256 hatId = roleHats[roleId];
        require(hatId != 0, Hats__HatDoesNotExist(roleId));

        // Mint role hat
        HATS.mintHat(hatId, account);
        emit RoleGranted(roleId, account, hatId);
    }

    /**
     * @notice Revokes a role from an address by burning the corresponding hat
     * @param roleId The role to revoke
     * @param account The address to revoke the role from
     */
    function revokeRole(bytes32 roleId, address account) public virtual {
        require(HATS.isWearerOfHat(msg.sender, adminHat), Hats__DoesNotHaveThisHat(msg.sender, adminHat));

        uint256 hatId = roleHats[roleId];
        require(hatId != 0, Hats__HatDoesNotExist(roleId));
        require(HATS.isWearerOfHat(account, hatId), Hats__DoesNotHaveThisHat(account, hatId));

        // Burn role hat
        HATS.setHatWearerStatus(hatId, account, false, false);
        emit RoleRevoked(roleId, account, hatId);
    }

    /**
     * @notice Creates a new role hat under the branch
     * @param roleId Unique identifier for the role
     * @param details Human-readable description of the role
     * @param maxSupply Maximum number of addresses that can hold this role
     * @param initialHolders Optional array of addresses to grant the role to immediately
     * @return hatId The ID of the newly created role hat
     */
    function _createRole(
        bytes32 roleId,
        string memory details,
        uint256 maxSupply,
        address[] memory initialHolders
    ) internal virtual nonReentrant returns (uint256 hatId) {
        require(HATS.isAdminOfHat(msg.sender, adminHat), Hats__NotAdminOfHat(msg.sender, adminHat));
        require(roleHats[roleId] == 0, Hats__HatAlreadyExists(roleId));
        require(initialHolders.length <= maxSupply, Hats__TooManyInitialHolders(initialHolders.length, maxSupply));

        // Create role hat under branch
        // False positive: marked nonReentrant
        //slither-disable-next-line reentrancy-no-eth
        hatId = HATS.createHat(
            branchHat,
            details,
            uint32(maxSupply),
            address(this), // this contract determines eligibility
            address(this), // this contract controls activation
            true, // can be modified by admin
            "" // no custom image
        );

        roleHats[roleId] = hatId;
        hatRoles[hatId] = roleId;

        // Mint hats to initial holders
        for (uint256 i = 0; i < initialHolders.length; i++) {
            address holder = initialHolders[i];
            require(holder != address(0), Hats__InvalidAddressFor("initial holder", holder));

            // mintHat(
            //    uint256 hatId,    // Hat ID to mint
            //    address wearer    // Address to receive hat
            // )
            HATS.mintHat(hatId, holder);
            emit RoleGranted(roleId, holder, hatId);
        }

        emit RoleHatCreated(roleId, hatId);
    }
}
