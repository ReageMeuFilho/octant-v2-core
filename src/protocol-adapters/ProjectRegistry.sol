// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {ONFT1155} from "src/vendor/layerzero/ONFT1155.sol";

/**
 * @title ProjectRegistry
 * @notice Registry for Octant projects that manages project registration and war bond NFTs
 */
contract ProjectRegistry is Initializable, ONFT1155 {
    uint256 public constant ROUNDS_MASTER_ROLE = 1;
    uint256 public constant FUNDING_POOL_ROLE = 2;

    modifier onlyRoles(uint256 _role) {
        require(hasRole(_role, msg.sender), "Only roles can call this function");
        _;
    }

    // Structs
    struct Project {
        address owner;
        uint256 warBondToken;
        string metadataURI; // DAOIP-5 compatible metadata
        bool isRegistered;
        mapping(uint256 => bool) approvedRounds; // roundId => approval status
    }

    // State variables
    mapping(address => Project) public projects;
    mapping(address => mapping(uint256 => bool)) public roles;
    uint256 public nextTokenId;

    // Events
    event ProjectRegistered(address indexed projectAddress, address indexed owner, uint256 indexed tokenId);
    event ProjectApprovedForRound(address indexed projectAddress, uint256 indexed roundId);
    event WarBondMinted(address indexed projectAddress, address indexed recipient, uint256 amount);
    event MetadataUpdated(address indexed projectAddress, string metadataURI);


    // @notice owner here will be the octant governance multisig
    constructor(address _owner, string memory _uri, address _lzEndpoint) ONFT1155(_uri, _lzEndpoint, _owner) {
    }

    function setRole(uint256 _role, address _user, bool _on) external onlyOwner {
        _setRoles(_user, _role, _on);
    }

    function _setRoles(address _user, uint256 _role, bool _on) internal {
        roles[_user][_role] = _on;
    }

    function hasRole(uint256 _role, address _user) public view returns (bool) {
        return roles[_user][_role];
    }

    // TODO in mapping use project id. 
    function registerProject(string calldata _metadataURI) external {
        require(!projects[msg.sender].isRegistered, "Project already registered");
        
        Project storage newProject = projects[msg.sender];
        newProject.owner = msg.sender;
        newProject.warBondToken = nextTokenId;
        newProject.metadataURI = _metadataURI;
        newProject.isRegistered = true;

        nextTokenId++;

        emit ProjectRegistered(msg.sender, msg.sender, newProject.warBondToken);
    }

    function approveProjectForRound(address _project, uint256 _roundId) external onlyRoles(ROUNDS_MASTER_ROLE) {
        require(projects[_project].isRegistered, "Project not registered");
        projects[_project].approvedRounds[_roundId] = true;
        emit ProjectApprovedForRound(_project, _roundId);
    }

    function isProjectApprovedForRound(address _project, uint256 _roundId) external view returns (bool) {
        return projects[_project].approvedRounds[_roundId];
    }

    function mintWarBonds(address _recipient, uint256 _amount) external onlyRoles(FUNDING_POOL_ROLE) {
        require(projects[msg.sender].isRegistered, "Project not registered");
        uint256 tokenId = projects[msg.sender].warBondToken;
        _mint(_recipient, tokenId, _amount, "");
        emit WarBondMinted(msg.sender, _recipient, _amount);
    }

    // Metadata functions
    function updateMetadata(address _project, string calldata _metadataURI) external {
        require(msg.sender == projects[_project].owner, "Not project owner");
        projects[_project].metadataURI = _metadataURI;
        emit MetadataUpdated(_project, _metadataURI);
    }

    function getProjectMetadata(address _project) external view returns (string memory) {
        return projects[_project].metadataURI;
    }
}
