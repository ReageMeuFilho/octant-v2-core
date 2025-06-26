// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Module } from "zodiac/core/Module.sol";

import { BaseStrategy } from "src/zodiac-core/BaseStrategy.sol";
// TokenizedStrategy interface used for internal view delegateCalls.
import { ITokenizedStrategy } from "src/zodiac-core/interfaces/ITokenizedStrategy.sol";

/**
 * @title Dragon Base Strategy
 */
abstract contract DragonBaseStrategy is BaseStrategy, Module {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
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
    // NOTE: This is a holder address based on expected deterministic location for testing
    address public tokenizedStrategyImplementation;

    uint256 public maxReportDelay;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // using this address to represent native ETH

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

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
    fallback() external payable {
        assembly ("memory-safe") {
            if and(iszero(calldatasize()), not(iszero(callvalue()))) {
                return(0, 0)
            }
        }
        // load our target address
        address _tokenizedStrategyAddress = tokenizedStrategyImplementation;
        // Execute external function using delegatecall and return any value.
        assembly ("memory-safe") {
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

    /// @dev Handle the liquidation of strategy assets.
    /// @param _amountNeeded Amount to be liquidated.
    /// @return _liquidatedAmount liquidated amount.
    /// @return _loss loss amount if it resulted in liquidation.
    function liquidatePosition(
        uint256 _amountNeeded
    ) external virtual onlyManagement returns (uint256 _liquidatedAmount, uint256 _loss) {}

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /// @dev Handle the strategy’s core position adjustments.
    /// @param _debtOutstanding Amount of position to adjust.
    function adjustPosition(uint256 _debtOutstanding) external virtual onlyManagement {}

    /*//////////////////////////////////////////////////////////////
                        TokenizedStrategy HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Provide a signal to the keeper that `report()` should be called.
     * @return timeToReport `true` if `report()` should be called, `false` otherwise.
     */
    function harvestTrigger() external view virtual returns (bool timeToReport) {
        // Should not trigger if strategy is not active (no assets) or harvest has been recently called.
        if (
            TokenizedStrategy.totalAssets() != 0 && (block.timestamp - TokenizedStrategy.lastReport()) >= maxReportDelay
        ) return true;
    }

    /**
     * @notice Used to initialize the strategy on deployment.
     *
     * This will set the `TokenizedStrategy` variable for easy
     * internal view calls to the implementation. As well as
     * initializing the default storage variables based on the
     * parameters.
     *
     * @param _tokenizedStrategyImplementation Address of the TokenStrategyImplementation contract.
     * @param _asset Address of the underlying asset.
     * @param _management Address of the strategy manager.
     * @param _keeper Address of keeper.
     * @param _dragonRouter Address of the dragon router.
     * @param _name Name the strategy will use.
     *
     */
    function __BaseStrategy_init(
        address _tokenizedStrategyImplementation,
        address _asset,
        address _owner,
        address _management,
        address _keeper,
        address _dragonRouter,
        uint256 _maxReportDelay,
        string memory _name,
        address _regenGovernance
    ) internal onlyInitializing {
        tokenizedStrategyImplementation = _tokenizedStrategyImplementation;
        asset = ERC20(_asset);
        maxReportDelay = _maxReportDelay;

        // Set instance of the implementation for internal use.
        TokenizedStrategy = ITokenizedStrategy(address(this));

        // Initialize the strategy's storage variables.
        _delegateCall(
            abi.encodeCall(
                ITokenizedStrategy.initialize,
                (_asset, _name, _owner, _management, _keeper, _dragonRouter, _regenGovernance)
            )
        );

        // Store the tokenizedStrategyImplementation at the standard implementation
        // address storage slot so etherscan picks up the interface. This gets
        // stored on initialization and never updated.
        assembly ("memory-safe") {
            sstore(
                // keccak256('eip1967.proxy.implementation' - 1)
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
                _tokenizedStrategyImplementation
            )
        }
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
        //slither-disable-next-line controlled-delegatecall
        (bool success, bytes memory result) = tokenizedStrategyImplementation.delegatecall(_calldata);

        // If the call reverted. Return the error.
        if (!success) {
            assembly ("memory-safe") {
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
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     */
    function _tendTrigger() internal view virtual override returns (bool) {
        return (address(asset) == ETH ? address(this).balance : asset.balanceOf(address(this))) > 0;
    }
}
