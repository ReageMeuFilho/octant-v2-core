// SPDX-License-Identifier: GPL-3.0

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.23;

import {IOctantRouter} from "../interfaces/IOctantRouter.sol";
import {IOctantForwarder} from "../interfaces/IOctantForwarder.sol";
import {ICapitalTransformer} from "../interfaces/ICapitalTransformer.sol";

enum RouterState {
    VOID,
    LOADED,
    TRANSFORMED
}

/**
 * @author  .
 * @title   Octant Router
 * @notice  .
 * @dev     Octant Router is a base classs for all transformers
 * This contract is intentionally NOT gas-efficient, optimizing for the desirable behaviour first
 */

abstract contract OctantRouter is IOctantRouter, IOctantForwarder, ICapitalTransformer {
    /**
     * Errors
     */
    error OctantRouter__LengthMismatch();
    error OctantRouter__DepositAmountsMismatch();
    error OctantRouter__OnlyOwnerCanUpdateCapitalTransformer();
    error OctantRouter__CantForwardEmptyBalance();

    RouterState state;
    uint256 thisBalance;

    // Temporary mapping, the givers will be added to the log
    mapping(address source => mapping(address giver => uint256 amount)) public sourceRoutes;
    mapping(address source => ICapitalTransformer transformer) capitalTransformers;
    mapping(address source => address owner) sourceOwners;
    address[] sources;

    mapping(address target => uint256 transferred) targetRoutesTransferred;
    mapping(address target => uint256 queue) targetRoutesQueue;
    address[] targets;

    receive() external payable {
        sourceRoutes[msg.sender][msg.sender] += msg.value;
        _receive();
    }

    /**
     * @notice  Defines ownership of funds sources. Not clear if this function is needed.
     * @dev     .
     * @param   source  .
     * @param   capitalTransformer  .
     */
    function registerCapitalSource(address source, ICapitalTransformer capitalTransformer) external {
        if (sourceOwners[source] == address(0)) {
            // Claim ownership of a source
            // should it be possible to assign ownership on behalf of?
            sourceOwners[source] = msg.sender;
        } else if (sourceOwners[source] != msg.sender) {
            revert OctantRouter__OnlyOwnerCanUpdateCapitalTransformer();
        }
        capitalTransformers[source] = capitalTransformer;
    }

    /**
     * @notice  Function to deposit assets and give ownership to this contract
     * @dev     Call when this contract is the destination. Can be called by anyone.
     */
    function deposit() external payable {
        sourceRoutes[msg.sender][msg.sender] += msg.value;
        _receive();
    }

    /**
     * @notice  depositWithGivers is a method that receives ETH into this contract and logs givers
     * @dev     Call when this contract is the destination. Can be called by anyone.
     * @param   givers  .
     * @param   amounts  .
     */
    function depositWithGivers(address[] memory givers, uint256[] memory amounts) public payable {
        _enqueueWithGivers(givers, amounts);
        _receive();
    }

    function enqueueTo(address target) public payable {
        if (targetRoutesQueue[target] == 0 && targetRoutesTransferred[target] == 0) {
            targets.push(target);
        }
        targetRoutesQueue[target] += msg.value;
        state = RouterState.LOADED;
    }

    function enqueueToWithGivers(address[] calldata givers, uint256[] calldata amounts, address target)
        external
        payable
    {
        _enqueueWithGivers(givers, amounts);
        enqueueTo(target);
    }

    /**
     * @notice  .
     * @dev     Figure out exactly how it works. Do we need to pass amount or not?
     * @param   amount  .
     */
    function transform(uint256 amount) public payable {
        _transform(amount);
        for (uint256 i = 0; i < sources.length; i++) {
            ICapitalTransformer transformer = capitalTransformers[sources[i]];
            if (address(transformer) != address(0)) {
                transformer.transform{value: amount}(amount, "");
            }
        }
        state = RouterState.TRANSFORMED;
    }

    function forward() public payable {
        for (uint256 i = 0; i < targets.length; i++) {
            forwardTo(targets[i]);
        }
        state = RouterState.VOID;
    }

    function forwardTo(address target) public payable {
        uint256 amountToForward = targetRoutesQueue[target];
        if (amountToForward == 0) revert OctantRouter__CantForwardEmptyBalance();
        targetRoutesQueue[target] -= amountToForward;
        targetRoutesTransferred[target] += amountToForward;
        target.call{value: amountToForward};
    }

    function forwardToWithGivers(address[] calldata givers, uint256[] calldata amounts, address target)
        external
        payable
    {
        _enqueueWithGivers(givers, amounts);
        forwardTo(target);
    }

    /**
     * Internal & Private
     */
     
    function _receive() internal {
        thisBalance += msg.value;
        state = RouterState.LOADED;
    }

    function _enqueueWithGivers(address[] memory givers, uint256[] memory amounts) internal {
        uint256 totalAmount;
        if (givers.length != amounts.length) revert OctantRouter__LengthMismatch();
        for (uint256 i = 0; i < givers.length; i++) {
            sourceRoutes[msg.sender][givers[i]] += amounts[i];
            totalAmount += amounts[i];
        }
        if (totalAmount != msg.value) revert OctantRouter__DepositAmountsMismatch();
    }

    /**
     * @notice  _transform function contains logic that is specific to each transformer
     * @dev     implement this function in the inherited contract
     * @param   amount  .
     */
    function _transform(uint256 amount) internal virtual {}
}
