// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.25;

interface IProjectRegistry {
    /**
     * @notice Checks if a project is registered
     * @param _project The address of the project to check
     * @return bool True if project is registered
     */
    function isRegistered(address _project) external view returns (bool);

    /**
     * @notice Adds a new project to the registry
     * @param _project The address of the project to add
     */
    function addProject(address _project) external;

    /**
     * @notice Removes a project from the registry
     * @param _project The address of the project to remove
     */
    function removeProject(address _project) external;

    /**
     * @notice Gets all registered projects
     * @return address[] Array of registered project addresses
     */
    function getProjects() external view returns (address[] memory);

    /**
     * @notice Event emitted when a project is added
     * @param project The address of the added project
     */
    event ProjectAdded(address indexed project);

    /**
     * @notice Event emitted when a project is removed
     * @param project The address of the removed project
     */
    event ProjectRemoved(address indexed project);
}
