# AbstractHatsManager

## Overview
AbstractHatsManager is a base contract pattern for managing hierarchical role-based systems using Hats Protocol. It provides a reusable foundation for creating and managing role-based permissions where:
- An admin hat controls the entire system
- A branch hat represents a specific domain/category of roles
- Multiple role types can exist under the branch
- Each role can have multiple holders
- All roles in the branch share a common active/inactive state

## Structure

### Core Components

1. **Hat Hierarchy**
   - `adminHat`: The top-level hat that has admin privileges
   - `branchHat`: A sub-hat under the admin hat that represents a specific domain
   - Role hats: Individual role hats created under the branch hat 

### Hat Structure Example

```solidity
1 (Top Hat)
└── 1.1 (Autonomous Admin Hat - Protocol)
    └── 1.1.1 (Autonomous Admin Hat - Dragons) - The hat that controls this contract
        └── 1.1.1 (Admin Hat - Dragon) - The hat that controls this contract
            └── 1.1.1.1 (Branch Hat - Vault Management) - Created by this contract
                ├── 1.1.1.1.1 (Role Hat - Keeper) - Managed by this contract
                ├── 1.1.1.1.2 (Role Hat - Management) - Managed by this contract
                └── 1.1.1.1.3 (Role Hat - EmergencyResponder) - Managed by this contract
```

This structure follows best practices by:
1. Starting with a Top Hat (1)
2. Reserving space for an Autonomous Admin (1.1) for future automation needs
3. Having a dedicated Admin Hat (1.1.1)
4. Placing the Branch Hat (1.1.1.1) at the same level as the Autonomous Admin
5. Creating Role Hats (1.1.1.1d.X) under the Branch Hat

The Autonomous Admin hat can initially be unworn but provides future flexibility for:
- Automated role management
- Batch operations
- Integration with other systems
- Claim-based role assignment

![alt text](image.png)

### Storage

1. **Role Mappings**
   - `roleHats`: Maps role identifiers (`bytes32`) to hat IDs (`uint256`)
   - `hatRoles`: Reverse mapping of hat IDs to role identifiers
   - `isActive`: Global toggle for all roles in the branch

### Key Functions

1. **Setup**
   - `constructor`: Creates the initial branch hat under the admin hat
   
2. **Role Management**
   - `createRole`: Creates a new role hat under the branch
   - `grantRole`: Assigns a role to an address
   - `revokeRole`: Removes a role from an address

3. **Status Checks**
   - `getWearerStatus`: Virtual function for custom eligibility logic
   - `getHatStatus`: Checks if roles are currently active
   - `toggleBranch`: Allows admin to enable/disable all roles

## How It Works

### 1. Initialization
When deployed, the contract:
- Validates the Hats Protocol address
- Confirms deployer has admin hat
- Creates a branch hat under the admin hat

### 2. Role Creation
To create a new role:
- Admin calls `createRole` with:
  - Role identifier
  - Role description
  - Maximum number of holders
  - Optional initial holders
- Contract creates hat under branch
- Maps role ID to hat ID
- Mints hats to initial holders

### 3. Role Assignment
To manage role holders:
- `grantRole`: Mints role hat to new holder
- `revokeRole`: Burns role hat from existing holder
- Both require admin hat

### 4. Status Management
- All roles inherit active status from branch
- Admin can toggle entire branch on/off
- Custom eligibility logic in child contracts


## Security Considerations

1. **Access Control**
   - Only admin hat can create/manage roles
   - Role operations validate hat existence
   - Zero address checks on all user inputs

2. **State Management**
   - Prevents duplicate role creation
   - Validates role existence before operations
   - Checks hat ownership before revocation

3. **Extensibility**
   - Child contracts can add custom logic
   - Core functionality remains consistent
   - Events for all important state changes

## Events

- `RoleHatCreated`: When new role type is created
- `RoleGranted`: When role is assigned to address
- `RoleRevoked`: When role is removed from address

## Integration Points

1. **Hats Protocol**
   - Implements `IHatsEligibility`
   - Implements `IHatsToggle`
   - Uses `IHats` for hat operations

2. **Child Contracts**
   - Must implement `getWearerStatus`
   - Can override role management functions
   - Can add custom functionality
