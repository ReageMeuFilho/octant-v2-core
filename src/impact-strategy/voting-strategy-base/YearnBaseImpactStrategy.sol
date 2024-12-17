// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// TokenizedStrategy interface used for internal view delegateCalls.
import {ITokenizedImpactStrategy} from "src/interfaces/ITokenizedImpactStrategy.sol";
import {YearnBaseStrategy} from "./YearnBaseStrategy.sol";


/**
 * @title YearnV3 Base Strategy
 * @author yearn.finance
 * @notice
 *  BaseStrategy implements all of the required functionality to
 *  seamlessly integrate with the `TokenizedStrategy` implementation contract
 *  allowing anyone to easily build a fully permissionless ERC-4626 compliant
 *  Vault by inheriting this contract and overriding three simple functions.

 *  It utilizes an immutable proxy pattern that allows the BaseStrategy
 *  to remain simple and small. All standard logic is held within the
 *  `TokenizedStrategy` and is reused over any n strategies all using the
 *  `fallback` function to delegatecall the implementation so that strategists
 *  can only be concerned with writing their strategy specific code.
 *
 *  This contract should be inherited and the three main abstract methods
 *  `_deployFunds`, `_freeFunds` and `_harvestAndReport` implemented to adapt
 *  the Strategy to the particular needs it has to generate yield. There are
 *  other optional methods that can be implemented to further customize
 *  the strategy if desired.
 *
 *  All default storage for the strategy is controlled and updated by the
 *  `TokenizedStrategy`. The implementation holds a storage struct that
 *  contains all needed global variables in a manual storage slot. This
 *  means strategists can feel free to implement their own custom storage
 *  variables as they need with no concern of collisions. All global variables
 *  can be viewed within the Strategy by a simple call using the
 *  `TokenizedStrategy` variable. IE: TokenizedStrategy.globalVariable();.
 */
abstract contract YearnBaseImpactStrategy is YearnBaseStrategy {
   
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    
    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Underlying asset the Strategy is earning yield on.
     * Stored here for cheap retrievals within the strategy.
     */
    ERC20 internal immutable asset;

    /**
     * @notice Used to initialize the strategy on deployment.
     *
     * This will set the `TokenizedStrategy` variable for easy
     * internal view calls to the implementation. As well as
     * initializing the default storage variables based on the
     * parameters and using the deployer for the permissioned roles.
     *
     * @param _asset Address of the underlying asset.
     * @param _name Name the strategy will use.
     */
    constructor(address _asset, string memory _name) {
        asset = ERC20(_asset);

        // Set instance of the implementation for internal use.
        TokenizedStrategy = ITokenizedImpactStrategy(address(this));

        // Initialize the strategy's storage variables.
        _delegateCall(
            abi.encodeCall(
                ITokenizedImpactStrategy.initialize,
                (_asset, _name, msg.sender, msg.sender, msg.sender)
            )
        );

        // Store the tokenizedStrategyAddress at the standard implementation
        // address storage slot so etherscan picks up the interface. This gets
        // stored on initialization and never updated.
        assembly {
            sstore(
                // keccak256('eip1967.proxy.implementation' - 1)
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
                tokenizedStrategyAddress
            )
        }
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Can convert assets to votes
     * @dev This function is used to convert assets to votes, defaults to 1:1 conversion
     * @param assets The amount of assets to convert
     * @param _rounding The rounding mode
     * @return The amount of votes
     */
    function _convertToVotes(uint256 assets, Math.Rounding _rounding) internal view virtual returns (uint256) {
        return assets;
    }

    /** 
     * @notice This function is used to process a vote and update the tally for the voting strategy
     * @dev Implements incremental update quadratic funding algorithm
     * @param projectId The ID of the project to update.
     * @param contribution The new contribution to add.
     */
    function _processVote(uint256 projectId, uint256 contribution, uint256 voteWeight) internal virtual{}

    /**
     * @notice Returns the current funding metrics for a specific project
     * @dev This function aggregates all the relevant funding data for a project
     * @param projectId The ID of the project to tally
     * @return projectShares The total shares allocated to this project
     * @return totalShares The total shares across all projects
     */
    function _tally(uint256 projectId) internal view virtual returns (uint256 projectShares, uint256 totalShares){}

    /**
     * @notice Finalizes the voting tally and returns the total shares between all projects
     * @dev This function is called when the allocation is finalized and voting is closed
     */
    function _finalize(uint256 totalShares) internal view virtual returns (uint256 finalizedTotalShares){}

    /*//////////////////////////////////////////////////////////////
                        TokenizedStrategy HOOKS 
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Can convert assets to votes
     */
    function convertToVotes(uint256 assets, Math.Rounding _rounding) external view virtual onlySelf returns (uint256) {
        return _convertToVotes(assets, _rounding);
    }
    /**
     * @notice Can incrementally process votes
     */
    function processVote(uint256 projectId, uint256 contribution, uint256 voteWeight) external virtual onlySelf {
        _processVote(projectId, contribution, voteWeight);
    }

    /**
     * @notice Can tally the current funding metrics for a specific project
     */
    function tally(uint256 projectId) external view virtual onlySelf returns (uint256 projectShares, uint256 totalShares) {
        return _tally(projectId);
    }

    /**
     * @notice Can finalize the allocation of assets to a project
     */
    function finalize(uint256 totalShares) external view onlySelf returns (uint256 finalizedTotalShares) {
        return _finalize(totalShares);
    }
    
}
