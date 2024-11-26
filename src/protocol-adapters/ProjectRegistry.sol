// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {Create3} from "../libraries/Create3.sol";

import {ProjectWarBond} from "./ProjectWarBond.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title ProjectRegistry
 * @notice Registry for Octant projects that manages project registration and war bond NFTs
 */
contract ProjectRegistry is OwnableRoles, Initializable {
    // Add role constant
    uint256 public constant ROUNDS_MASTER_ROLE = _ROLE_0;
    uint256 public constant FUNDING_POOL_ROLE = _ROLE_1;

    // Structs
    struct Project {
        address owner;
        address warBondToken;
        bytes metadata; // DAOIP-5 compatible metadata
        bool isRegistered;
        mapping(uint256 => bool) approvedRounds; // roundId => approval status
    }

    // TODO decide on the metadata format allowed - https://docs.google.com/document/d/1Kl2-LYbNC_FN7E3XmaUJtxu-VjOoX9g8i819n_cByGI/
    struct Metadata {
        string name;
        string description;
        string logoUrl;
    }

    // State variables
    mapping(address => Project) public projects;

    // Events
    event ProjectRegistered(address indexed projectAddress, address indexed owner, address tokenId);
    event ProjectApprovedForRound(address indexed projectAddress, uint256 indexed roundId);
    event WarBondMinted(address indexed projectAddress, address indexed recipient, uint256 amount);
    event MetadataUpdated(address indexed projectAddress, bytes metadata);


    // @notice owner here will be the octant governance multisig
    function initialize(address _owner) external initializer {
        _initializeOwner(_owner);
    }

    function registerProject(bytes calldata _metadata, string memory _uri, address _lzEndpoint) external {
        require(!projects[msg.sender].isRegistered, "Project already registered");
        
        // Generate deterministic salt based on project address
        bytes32 salt = keccak256(abi.encodePacked(msg.sender));
        
        // Create the initialization code for ProjectWarBond
        bytes memory creationCode = abi.encodePacked(
            type(ProjectWarBond).creationCode,
            abi.encode(msg.sender, address(this), _lzEndpoint, _uri) // Constructor arguments
        );
        
        // Deploy using Create3
        address warBond = Create3.create3(salt, creationCode);
        
        Project storage newProject = projects[msg.sender];
        newProject.owner = msg.sender;
        newProject.warBondToken = warBond; // TODO: should we make this so that a user can come with their own war bond?
        newProject.metadata = _metadata;
        newProject.isRegistered = true;

        emit ProjectRegistered(msg.sender, msg.sender, warBond);
    }

    function approveProjectForRound(address _project, uint256 _roundId) external onlyOwnerOrRoles(ROUNDS_MASTER_ROLE) {
        require(projects[_project].isRegistered, "Project not registered");
        projects[_project].approvedRounds[_roundId] = true;
        emit ProjectApprovedForRound(_project, _roundId);
    }

    function isProjectApprovedForRound(address _project, uint256 _roundId) external view returns (bool) {
        return projects[_project].approvedRounds[_roundId];
    }

    function mintWarBonds(address _recipient, uint256 _amount) external onlyOwnerOrRoles(FUNDING_POOL_ROLE) {
        require(projects[msg.sender].isRegistered, "Project not registered");
        ProjectWarBond(projects[msg.sender].warBondToken).mint(_recipient, _amount);
        emit WarBondMinted(msg.sender, _recipient, _amount);
    }

    // Metadata functions
    function updateMetadata(address _project, bytes calldata _metadata) external {
        require(msg.sender == projects[_project].owner, "Not project owner");
        projects[_project].metadata = _metadata;
        emit MetadataUpdated(_project, _metadata);
    }

    function getProjectMetadata(address _project) external view returns (bytes memory) {
        return projects[_project].metadata;
    }
}
