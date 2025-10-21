// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.25;

import { IProjectRegistry } from "../../src/interfaces/IProjectRegistry.sol";

contract MockProjectRegistry is IProjectRegistry {
    uint256 public projectId;
    mapping(address => uint256) public projectIds;
    mapping(address => bool) public registry;
    mapping(uint256 => address) public projects;

    function isRegistered(address _project) external view override returns (bool) {
        return registry[_project];
    }

    function addProject(address _project) external override {
        require(_project != address(0), "ZERO_ADDRESS");
        require(!registry[_project], "ALREADY_REGISTERED");

        projectId++;
        projects[projectId] = _project;

        registry[_project] = true;
        projectIds[_project] = projectId;

        emit ProjectAdded(_project);
    }

    function getProjectId(address _project) external view override returns (uint256) {
        return projectIds[_project];
    }

    function removeProject(address _project) external override {
        require(registry[_project], "NOT_REGISTERED");

        registry[_project] = false;

        if (registry[projects[projectId]]) {
            projects[projectId] = address(0);
        }

        emit ProjectRemoved(_project);
    }
}
