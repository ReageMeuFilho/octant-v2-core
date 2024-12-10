// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.25;

import {IProjectRegistry} from "../../src/interfaces/IProjectRegistry.sol";

contract MockProjectRegistry is IProjectRegistry {
    mapping(address => bool) public registry;
    address[] public projects;

    function isRegistered(address _project) external view override returns (bool) {
        return registry[_project];
    }

    function addProject(address _project) external override {
        require(_project != address(0), "ZERO_ADDRESS");
        require(!registry[_project], "ALREADY_REGISTERED");
        
        registry[_project] = true;
        projects.push(_project);
        
        emit ProjectAdded(_project);
    }

    function removeProject(address _project) external override {
        require(registry[_project], "NOT_REGISTERED");
        
        registry[_project] = false;
        
        // Remove from projects array
        for (uint256 i = 0; i < projects.length; i++) {
            if (projects[i] == _project) {
                projects[i] = projects[projects.length - 1];
                projects.pop();
                break;
            }
        }
        
        emit ProjectRemoved(_project);
    }

    function getProjects() external view override returns (address[] memory) {
        return projects;
    }
} 