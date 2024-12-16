// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";

contract RoleRegistry is OwnableRoles {
    mapping(string name => uint256 role) public roles;

    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    function addRole(string memory name, uint256 role) external onlyOwner {
        roles[name] = role;
    }

    function removeRole(string memory name) external onlyOwner {
        delete roles[name];
    }

    function hasRole(string memory name, address user) public view returns (bool) {
        return roles[name] != 0 && rolesOf(user) & roles[name] != 0;
    }
}
