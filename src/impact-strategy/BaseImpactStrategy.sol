// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IImpactStrategy } from "../interfaces/IImpactStrategy.sol";
/**
 * @title Base Impact Strategy
 * @author yearn.finance
 * @notice
 *  BaseImpactStrategy implements all of the required functionality to
 *  seamlessly integrate with the `ImpactStrategy` implementation contract
 *  allowing anyone to easily build a fully permissionless voting strategy
 *  vault by inheriting this contract and overriding three simple functions.

 *  It utilizes an immutable proxy pattern that allows the BaseImpactStrategy
 *  to remain simple and small. All standard logic is held within the
 *  `ImpactStrategy` and is reused over any n strategies all using the
 *  `fallback` function to delegatecall the implementation so that strategists
 *  can only be concerned with writing their strategy specific code.
 *
*  Required functions to implement:
 *  - `3`: Determines veToken minting based on deposits
 *  - `_processVote`: Handles vote allocation logic
 *  - `_calculateShares`: Determines share allocation based on votes
 *
 *  Optional functions that can be overridden:
 *  - `availableDepositLimit`: Controls deposit restrictions (default: unlimited)
 *  - `availableWithdrawLimit`: Controls withdrawal restrictions (default: unlimited)
 *  - `checkSybilResistance`: Implements sybil resistance checks (default: allows all)
 
 *
 *  All default storage for the strategy is controlled and updated by the
 *  `ImpactStrategy`. The implementation holds a storage struct that
 *  contains all needed global variables in a manual storage slot. This
 *  means strategists can feel free to implement their own custom storage
 *  variables as they need with no concern of collisions. All global variables
 *  can be viewed within the Strategy by a simple call using the
 *  `ImpactStrategy` variable. IE: ImpactStrategy.globalVariable();.
 */
abstract contract BaseImpactStrategy {
    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Used on ImpactStrategy callback functions to make sure it is post
     * a delegateCall from this address to the ImpactStrategy.
     */
    modifier onlySelf() {
        _onlySelf();
        _;
    }

    /**
     * @dev Use to assure that the call is coming from either the strategies
     * management or the keeper.
     */
    modifier onlyKeepers() {
        ImpactStrategy.requireKeeperOrManagement(msg.sender);
        _;
    }

    /**
     * @dev Use to assure that the call is coming from either the strategies
     * management or the emergency admin.
     */
    modifier onlyEmergencyAuthorized() {
        ImpactStrategy.requireEmergencyAuthorized(msg.sender);
        _;
    }

    /**
     * @dev Require that the msg.sender is this address.
     */
    function _onlySelf() internal view {
        require(msg.sender == address(this), "!self");
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev This is the address of the ImpactStrategy implementation
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
    address public constant impactStrategyAddress = 0x2e234DAe75C793f67A35089C9d99245E1C58470b;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Underlying asset used to calculate veTokens
     */
    ERC20 internal immutable ASSET;

    /**
     * @dev This variable is set to address(this) during initialization of each strategy.
     *
     * This can be used to retrieve storage data within the strategy
     * contract as if it were a linked library.
     *
     *       i.e. uint256 totalAssets = ImpactStrategy.totalAssets()
     *
     * Using address(this) will mean any calls using this variable will lead
     * to a call to itself. Which will hit the fallback function and
     * delegateCall that to the actual ImpactStrategy.
     */
    IImpactStrategy internal immutable ImpactStrategy;

    /**
     * @notice Used to initialize the strategy on deployment.
     *
     * This will set the `ImpactStrategy` variable for easy
     * internal view calls to the implementation. As well as
     * initializing the default storage variables based on the
     * parameters and using the deployer for the permissioned roles.
     *
     * @param _asset Address of the underlying asset.
     * @param _name Name the strategy will use.
     */
    constructor(address _asset, string memory _name) {
        ASSET = ERC20(_asset);

        // Set instance of the implementation for internal use.
        ImpactStrategy = IImpactStrategy(address(this));

        // Initialize the strategy's storage variables.
        _delegateCall(abi.encodeCall(IImpactStrategy.initialize, (_asset, _name, msg.sender, msg.sender, msg.sender)));

        // Store the impactStrategyAddress at the standard implementation
        // address storage slot so etherscan picks up the interface. This gets
        // stored on initialization and never updated.
        assembly {
            sstore(
                // keccak256('eip1967.proxy.implementation' - 1)
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
                impactStrategyAddress
            )
        }
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the amount of veTokens that will be minted for a deposit.
     * @dev Defaults to an empty implementation that must be overridden by strategists.
     *
     * This function will be called during deposit to calculate the amount of veTokens
     * to mint based on the deposit amount and lock time. The strategist can implement
     * any custom logic for the conversion rate between assets and veTokens.
     *
     * The calculation can take into account:
     * - The deposit amount in terms of underlying asset
     * - The user's address for any user specific multipliers
     * - The lock time for time-weighted voting power
     *
     * @param _amount The amount of underlying assets being deposited
     * @param _user The address that is depositing into the strategy
     * @param _lockTime The duration the deposit will be locked for
     * @return The amount of veTokens to mint for the deposit
     */
    function _calculateVeTokens(
        uint256 _amount,
        address _user,
        uint256 _lockTime
    ) internal view virtual returns (uint256);

    /**
     * @notice Processes a vote for a project in the strategy
     * @dev Defaults to an empty implementation that must be overridden by strategists.
     *
     * This function will be called during vote casting to handle the vote allocation
     * logic specific to the strategy. The strategist can implement any custom vote
     * processing mechanism.
     *
     * The implementation can handle:
     * - Vote weight calculation
     * - Vote validation rules
     * - Vote tracking and accounting
     * - Any strategy-specific vote processing logic
     *
     * @param _amount The amount of voting power to allocate
     * @param _projectRegistryId The ID of the project being voted for
     */
    function _processVote(uint256 _amount, uint256 _projectRegistryId) internal virtual;

    /**
     * @notice Calculates the shares to be allocated to a project based on votes received
     * @dev Defaults to an empty implementation that must be overridden by strategists.
     *
     * This function will be called during share allocation to determine how many shares
     * each project receives based on their votes. The strategist can implement any custom
     * share calculation logic.
     *
     * The calculation can take into account:
     * - The total votes received by the project
     * - The project's registry ID for any project-specific multipliers
     * - Any strategy-specific share calculation formulas
     *
     * @param _totalVotes The total number of votes received by the project
     * @param _projectRegistryId The ID of the project in the registry
     * @return The number of shares to allocate to the project
     */
    function _calculateShares(uint256 _totalVotes, uint256 _projectRegistryId) internal view virtual returns (uint256);

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
    function availableDepositLimit(address /*_voter*/) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used to implement donation caps.
     *
     *   EX:
     *       return ImpactStrategy.maxClaimable();
     *
     *
     * @param . The address that is claiming from the strategy.
     * @return . The available amount that can be claimed in terms of `asset`
     */
    function availableWithdrawLimit(address /*_project*/) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Performs a sybil resistance check on a voter address
     * @dev Default implementation that can be overridden by specific strategies
     * Returns a tuple containing:
     * - bool: whether the address passes the sybil check
     * - uint256: a sybil resistance score (higher is better)
     *
     * Strategists should override this function to implement specific sybil resistance checks such as:
     * - Proof of Humanity verification
     * - GitcoinPassport score
     * - Minimum token holdings
     * - Account age
     * - Previous voting history
     *
     * @param _voter The address to check for sybil resistance
     * @return (bool, uint256) Tuple containing (passes check, sybil resistance score)
     */
    function checkSybilResistance(address _voter) public view virtual returns (bool, uint256) {
        // Default implementation assumes no sybil resistance
        // Returns (true, assetBalance) to allow voting with asset balance
        return (true, ASSET.totalSupply() / ASSET.balanceOf(_voter));
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
        // Delegate call the impact strategy with provided calldata.
        (bool success, bytes memory result) = impactStrategyAddress.delegatecall(_calldata);

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
     * @dev Execute a function on the ImpactStrategy and return any value.
     *
     * This fallback function will be executed when any of the standard functions
     * defined in the ImpactStrategy are called since they wont be defined in
     * this contract.
     *
     * It will delegatecall the ImpactStrategy implementation with the exact
     * calldata and return any relevant values.
     *
     */
    fallback() external {
        // load our target address
        address _impactStrategyAddress = impactStrategyAddress;
        // Execute external function using delegatecall and return any value.
        assembly {
            // Copy function selector and any arguments.
            calldatacopy(0, 0, calldatasize())
            // Execute function delegatecall.
            let result := delegatecall(gas(), _impactStrategyAddress, 0, calldatasize(), 0, 0)
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

    /**
     * @notice Adjusts vote tally based on strategy rules
     * @dev Virtual function that can be overridden to implement vote decay or other adjustments
     * Default implementation returns unmodified tally
     *
     * Strategists can implement:
     * - Time-based vote decay
     * - Quadratic voting weights
     * - Reputation-based multipliers
     * - Historical participation bonuses
     *
     * @param _project Project address to adjust votes for
     * @param _rawTally The raw vote count before adjustments
     * @return The adjusted vote tally
     */
    function adjustVoteTally(address _project, uint256 _rawTally) public view virtual returns (uint256) {
        // Default implementation returns unmodified tally
        return _rawTally;
    }

    /**
     * @notice Adjusts share allocation based on strategy rules
     * @dev Virtual function that can be overridden to implement custom allocation formulas
     * Default implementation returns proportional allocation
     *
     * Strategists can implement:
     * - Quadratic allocation curves
     * - Bonding curves
     * - Minimum thresholds
     * - Project-specific multipliers
     *
     * @param _project Project address
     * @param _baseShares Linear share allocation
     * @param _projectVotes Project's vote tally
     * @param _totalVotes Total votes in system
     * @return The adjusted share allocation
     */
    function adjustShareAllocation(
        address _project,
        uint256 _baseShares,
        uint256 _projectVotes,
        uint256 _totalVotes
    ) public view virtual returns (uint256) {
        // Default implementation returns proportional allocation
        return _baseShares;
    }
}
