// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// TokenizedStrategy interface used for internal view delegateCalls.
import { ITokenizedImpactStrategy } from "src/interfaces/ITokenizedImpactStrategy.sol";

/**
 * @title Base Impact Strategy
 * @author octant.finance
 * @notice
 *  BaseImpactStrategy implements all of the required functionality to
 *  seamlessly integrate with the `TokenizedStrategy` implementation contract
 *  while adding impact-specific features for quadratic funding and voting.
 *
 *  It utilizes an immutable proxy pattern that allows the BaseImpactStrategy
 *  to remain simple and small. All standard logic is held within the
 *  `TokenizedStrategy` and is reused over any n strategies all using the
 *  `fallback` function to delegatecall the implementation.
 *
 *  This contract should be inherited by specific impact strategies that implement
 *  the four main abstract methods:
 *  - `_convertToVotes`: Convert asset amounts to voting power
 *  - `_processVote`: Process individual votes and update tallies
 *  - `_tally`: Calculate current funding metrics for projects
 *  - `_finalize`: Finalize the voting results and allocations
 *
 *  The strategy maintains compatibility with the TokenizedStrategy storage model,
 *  allowing strategists to add custom storage variables without conflicts.
 *  Standard variables can be accessed through the TokenizedStrategy interface.
 */
abstract contract BaseImpactStrategy {
    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Used on TokenizedStrategy callback functions to make sure it is post
     * a delegateCall from this address to the TokenizedStrategy.
     */
    modifier onlySelf() {
        _onlySelf();
        _;
    }

    /**
     * @dev Use to assure that the call is coming from the strategies management.
     */
    modifier onlyManagement() {
        TokenizedStrategy.requireManagement(msg.sender);
        _;
    }

    /**
     * @dev Use to assure that the call is coming from either the strategies
     * management or the keeper.
     */
    modifier onlyKeepers() {
        TokenizedStrategy.requireKeeperOrManagement(msg.sender);
        _;
    }

    /**
     * @dev Use to assure that the call is coming from either the strategies
     * management or the emergency admin.
     */
    modifier onlyEmergencyAuthorized() {
        TokenizedStrategy.requireEmergencyAuthorized(msg.sender);
        _;
    }

    /**
     * @dev Require that the msg.sender is this address.
     */
    function _onlySelf() internal view {
        require(msg.sender == address(this), "!self");
    }

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev This is the address of the TokenizedStrategy implementation
     * contract that will be used by all strategies to handle the
     * accounting, logic, storage etc.
     *
     * Any external calls to the that don't hit one of the functions
     * defined in this base or the strategy will end up being forwarded
     * through the fallback function, which will delegateCall this address.
     *
     * This address should be the same for every strategy, never be adjusted
     * and always be checked before any integration with the Strategy.
     */
    address public immutable tokenizedStrategyAddress;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev This variable is set to address(this) during initialization of each strategy.
     *
     * This can be used to retrieve storage data within the strategy
     * contract as if it were a linked library.
     *
     *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
     *
     * Using address(this) will mean any calls using this variable will lead
     * to a call to itself. Which will hit the fallback function and
     * delegateCall that to the actual TokenizedStrategy.
     */
    ITokenizedImpactStrategy internal immutable TokenizedStrategy;

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
    constructor(address _asset, string memory _name, address _tokenizedStrategyImplementation) {
        tokenizedStrategyAddress = _tokenizedStrategyImplementation;
        asset = ERC20(_asset);

        // Set instance of the implementation for internal use.
        TokenizedStrategy = ITokenizedImpactStrategy(address(this));

        // Initialize the strategy's storage variables.
        _delegateCall(
            abi.encodeCall(ITokenizedImpactStrategy.initialize, (_asset, _name, msg.sender, msg.sender, msg.sender))
        );

        // Store the tokenizedStrategyAddress at the standard implementation
        // address storage slot so etherscan picks up the interface. This gets
        // stored on initialization and never updated.
        assembly {
            sstore(
                // keccak256('eip1967.proxy.implementation' - 1)
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
                _tokenizedStrategyImplementation
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
     * @param voteWeight The weight of the vote
     */
    function _processVote(uint256 projectId, uint256 contribution, uint256 voteWeight) internal virtual {}

    /**
     * @notice Returns the current funding metrics for a specific project
     * @dev This function aggregates all the relevant funding data for a project
     * @param projectId The ID of the project to tally
     * @return projectShares The total shares allocated to this project
     * @return totalShares The total shares across all projects
     */
    function _tally(uint256 projectId) internal view virtual returns (uint256 projectShares, uint256 totalShares) {}

    /**
     * @notice Finalizes the voting tally and returns the total shares between all projects
     * @dev This function is called when the allocation is finalized and voting is closed
     * @param totalShares The total shares to finalize
     * @return finalizedTotalShares The finalized total shares
     */
    function _finalize(uint256 totalShares) internal virtual returns (uint256 finalizedTotalShares) {}

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     */
    function availableDepositLimit(address /*_owner*/) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(address /*_owner*/) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal virtual {}

    /*//////////////////////////////////////////////////////////////
                        TokenizedStrategy HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Will call the internal '_emergencyWithdraw' function.
     * @dev Callback for the TokenizedStrategy during an emergency withdraw.
     *
     * This can only be called after a emergencyWithdraw() delegateCall to
     * the TokenizedStrategy so msg.sender == address(this).
     *
     * We name the function `shutdownWithdraw` so that `emergencyWithdraw`
     * calls are forwarded to the TokenizedStrategy.
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function shutdownWithdraw(uint256 _amount) external virtual onlySelf {
        _emergencyWithdraw(_amount);
    }

    /**
     * @notice Can convert assets to votes
     * @param assets The amount of assets to convert
     * @param _rounding The rounding mode
     * @return The amount of votes
     */
    function convertToVotes(uint256 assets, Math.Rounding _rounding) external view virtual onlySelf returns (uint256) {
        return _convertToVotes(assets, _rounding);
    }

    /**
     * @notice Can incrementally process votes
     * @param projectId The ID of the project to update
     * @param contribution The new contribution to add
     * @param voteWeight The weight of the vote
     */
    function processVote(uint256 projectId, uint256 contribution, uint256 voteWeight) external virtual onlySelf {
        _processVote(projectId, contribution, voteWeight);
    }

    /**
     * @notice Can tally the current funding metrics for a specific project
     * @param projectId The ID of the project to tally
     * @return projectShares The total shares allocated to this project
     * @return totalShares The total shares across all projects
     */
    function tally(
        uint256 projectId
    ) external view virtual onlySelf returns (uint256 projectShares, uint256 totalShares) {
        return _tally(projectId);
    }

    /**
     * @notice Can finalize the allocation of assets to a project
     * @param totalShares The total shares to finalize
     * @return finalizedTotalShares The finalized total shares
     */
    function finalize(uint256 totalShares) external onlySelf returns (uint256 finalizedTotalShares) {
        return _finalize(totalShares);
    }

    /**
     * @dev Function used to delegate call the TokenizedStrategy with
     * certain `_calldata` and return any return values.
     *
     * This is used to setup the initial storage of the strategy, and
     * can be used by strategist to forward any other call to the
     * TokenizedStrategy implementation.
     *
     * @param _calldata The abi encoded calldata to use in delegatecall.
     * @return . The return value if the call was successful in bytes.
     */
    function _delegateCall(bytes memory _calldata) internal returns (bytes memory) {
        // Delegate call the tokenized strategy with provided calldata.
        (bool success, bytes memory result) = tokenizedStrategyAddress.delegatecall(_calldata);

        // If the call reverted. Return the error.
        if (!success) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        // Return the result.
        return result;
    }

    /**
     * @dev Execute a function on the TokenizedStrategy and return any value.
     *
     * This fallback function will be executed when any of the standard functions
     * defined in the TokenizedStrategy are called since they wont be defined in
     * this contract.
     *
     * It will delegatecall the TokenizedStrategy implementation with the exact
     * calldata and return any relevant values.
     *
     */
    fallback() external {
        // load our target address
        address _tokenizedStrategyAddress = tokenizedStrategyAddress;
        // Execute external function using delegatecall and return any value.
        assembly {
            // Copy function selector and any arguments.
            calldatacopy(0, 0, calldatasize())
            // Execute function delegatecall.
            let result := delegatecall(gas(), _tokenizedStrategyAddress, 0, calldatasize(), 0, 0)
            // Get any return value
            returndatacopy(0, 0, returndatasize())
            // Return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
