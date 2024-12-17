// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBaseImpactStrategy} from "src/interfaces/IBaseImpactStrategy.sol";
import {YearnTokenizedStrategy} from "./YearnTokenizedStrategy.sol";
import {IProjectRegistry} from "src/interfaces/IProjectRegistry.sol";


contract YearnTokenizedImpactStrategy is YearnTokenizedStrategy {
    using Math for uint256;
    using SafeERC20 for ERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
      /**
     * @notice Emitted when the 'projectRegistry' address is updated to 'newProjectRegistry'.
     */
    event UpdateProjectRegistry(address indexed projectRegistry);

    /**
     * @notice Emitted on the initialization of any new `strategy` that uses `asset`
     * with this specific `apiVersion`.
     */
    event NewTokenizedStrategy(
        address indexed strategy,
        address indexed asset,
        string apiVersion
    );

    /*//////////////////////////////////////////////////////////////
                        STORAGE STRUCT
    //////////////////////////////////////////////////////////////*/


    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/


    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Used to initialize storage for a newly deployed strategy.
     * @dev This should be called atomically whenever a new strategy is
     * deployed and can only be called once for each strategy.
     *
     * This will set all the default storage that must be set for a
     * strategy to function. Any changes can be made post deployment
     * through external calls from `management`.
     *
     * The function will also emit an event that off chain indexers can
     * look for to track any new deployments using this TokenizedStrategy.
     *
     * @param _asset Address of the underlying asset.
     * @param _name Name the strategy will use.
     * @param _management Address to set as the strategies `management`.
     * @param _projectRegistry Address to receive performance fees.
     * @param _keeper Address to set as strategies `keeper`.
     */
    function initialize(
        address _asset,
        string memory _name,
        address _management,
        address _projectRegistry,
        address _keeper
    ) external {
        // Cache storage pointer.
        StrategyData storage S = _strategyStorage();

        // Make sure we aren't initialized.
        require(address(S.asset) == address(0), "initialized");

        // Set the strategy's underlying asset.
        S.asset = ERC20(_asset);
        // Set the Strategy Tokens name.
        S.name = _name;
        // Set decimals based off the `asset`.
        S.decimals = ERC20(_asset).decimals();

        // Set address to receive performance fees.
        // Can't be address(0) or we will be burning fees.
        require(_projectRegistry != address(0), "ZERO ADDRESS");
        // Can't mint shares to its self because of profit locking.
        require(_projectRegistry != address(this), "self");
        S.projectRegistry = _projectRegistry;

        // Set the default management address. Can't be 0.
        require(_management != address(0), "ZERO ADDRESS");
        S.management = _management;
        // Set the keeper address
        S.keeper = _keeper;

        // Emit event to signal a new strategy has been initialized.
        emit NewTokenizedStrategy(address(this), _asset, API_VERSION);
    }

    /*//////////////////////////////////////////////////////////////
                      ERC4626 WRITE METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Grants voting power to `receiver` by 
     * depositing exactly `assets` of underlying tokens.
     * @param assets The amount of underlying to deposit in.
     * @param receiver The address to receive the `shares`.
     * @return votes The actual amount of shares issued.
     */
    function deposit(
        uint256 assets,
        address receiver
    ) external nonReentrant returns (uint256 votes) {
        // Get the storage slot for all following calls.
        StrategyData storage S = _strategyStorage();

        // Deposit full balance if using max uint.
        if (assets == type(uint256).max) {
            assets = S.asset.balanceOf(msg.sender);
        }

        // Checking max deposit will also check if shutdown.
        require(
            assets <= _maxDeposit(S, receiver),
            "ERC4626: deposit more than max"
        );
        // Check for rounding error.
        require(
            (votes = IBaseImpactStrategy(address(this)).convertToVotes(assets)) != 0,
            "ZERO_SHARES"
        );

        _deposit(S, receiver, assets, votes);
    }

    /**
     * @notice Redeems exactly `shares` from `owner` and
     * sends `assets` of underlying tokens to `receiver`.
     * @dev This will default to allowing any loss passed to be realized.
     * @param shares The amount of shares burnt.
     * @param receiver The address to receive `assets`.
     * @param owner The address whose shares are burnt.
     * @return assets The actual amount of underlying withdrawn.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256) {
        StrategyData storage S = _strategyStorage();
        require(
            shares <= _maxRedeem(S, owner),
            "ERC4626: redeem more than max"
        );
        uint256 assets;
        // Check for rounding error or 0 value.
        require(
            (assets = _convertToAssets(S, shares, Math.Rounding.Floor)) != 0,
            "ZERO_ASSETS"
        );

        // We need to return the actual amount withdrawn in case of a loss.
        return _withdraw(S, receiver, owner, assets, shares, MAX_BPS);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL 4626 VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal implementation of {totalAssets}.
    function _totalAssets(
        StrategyData storage S
    ) internal view override returns (uint256) {
        return S.totalAssets;
    }

    /// @dev Internal implementation of {totalSupply}.
    /// @notice Returns totalShares if finalized, otherwise returns zero
    /// @dev Returns totalShares if finalized, otherwise returns totalAssets
    /// @dev totalShares is capped at type(uint256).max to prevent overflow
    function _totalSupply(
        StrategyData storage S
    ) internal view override returns (uint256) {
        // If finalized, return totalShares capped at max uint256, otherwise return totalAssets
        return S.finalized ? S.finalizedTotalShares : 0;
    }
    
    /// @dev Internal implementation of {convertToShares}.
    function _convertToShares(
        StrategyData storage S,
        uint256 assets,
        Math.Rounding _rounding
    ) internal view override returns (uint256) {
        // Saves an extra SLOAD if values are non-zero.
        uint256 totalSupply_ = _totalSupply(S);
        // If supply is 0, PPS = 1.
        if (totalSupply_ == 0) return assets;

        uint256 totalAssets_ = _totalAssets(S);
        // If assets are 0 but supply is not PPS = 0.
        if (totalAssets_ == 0) return 0;

        return assets.mulDiv(totalSupply_, totalAssets_, _rounding);
    }

    /// @dev Internal implementation of {convertToAssets}.
    function _convertToAssets(
        StrategyData storage S,
        uint256 shares,
        Math.Rounding _rounding
    ) internal view override returns (uint256) {
        // Saves an extra SLOAD if totalSupply() is non-zero.
        uint256 supply = _totalSupply(S);

        return
            supply == 0
                ? shares
                : shares.mulDiv(_totalAssets(S), supply, _rounding);
    }

    /// @dev Internal implementation of {maxDeposit}.
    function _maxDeposit(
        StrategyData storage S,
        address receiver
    ) internal view override returns (uint256) {
        // Cannot deposit when shutdown or to the strategy.
        if (S.shutdown || receiver == address(this)) return 0;

        return IBaseImpactStrategy(address(this)).availableDepositLimit(receiver);
    }

    /// @dev Internal implementation of {maxRedeem}.
    function _maxRedeem(
        StrategyData storage S,
        address owner
    ) internal view override returns (uint256 maxRedeem_) {
        // Get the max the owner could withdraw currently.
        maxRedeem_ = IBaseImpactStrategy(address(this)).availableWithdrawLimit(owner);

        // Conversion would overflow and saves a min check if there is no withdrawal limit.
        if (maxRedeem_ == type(uint256).max) {
            maxRedeem_ = _balanceOf(S, owner);
        } else {
            maxRedeem_ = Math.min(
                // Can't redeem more than the balance.
                _convertToShares(S, maxRedeem_, Math.Rounding.Floor),
                _balanceOf(S, owner)
            );
        }
    }

     /// @dev Internal implementation of {balanceOf}.
    function _balanceOf(
        StrategyData storage S,
        address account
    ) internal view override returns (uint256) {
        IProjectRegistry projectRegistry = projectRegistry();
        uint256 projectId = projectRegistry.getProjectId(account);
        (uint256 projectShares,) = IBaseImpactStrategy(address(this)).tally(projectId);
        if (account == address(this)) {
            return 0;
        }
        return S.balances[account] + projectShares;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `to` cannot be the strategies address
     * - `from` must have a balance of at least `amount`.
     *
     */
    function _transfer(
        StrategyData storage S,
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(false, "cannot transfer shares");
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL 4626 WRITE METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Function to be called during {deposit}.
     *
     * This function handles all logic including transfers,
     * and accounting.
     *
     * We do all external calls before updating any internal
     * values to prevent view reentrancy issues from the token
     * transfers or the _deployFunds() calls.
     */
    function _deposit(
        StrategyData storage S,
        address receiver,
        uint256 assets,
        uint256 votes
    ) internal {
        // TODO: change to decouple from shares
        // Cache storage variables used more than once.
        ERC20 _asset = S.asset;

        // Need to transfer before minting or ERC777s could reenter.
        _asset.safeTransferFrom(msg.sender, address(this), assets);

        // Adjust total Assets.
        S.totalAssets += assets;

        // add voting power
        _addVotingPower(S, receiver, votes);

        emit Deposit(msg.sender, receiver, assets, votes);
    }

    /**
     * @dev To be called during {redeem} and {withdraw}.
     *
     * This will handle all logic, transfers and accounting
     * in order to service the withdraw request.
     *
     * If we are not able to withdraw the full amount needed, it will
     * be counted as a loss and passed on to the user.
     */
    function _withdraw(
        StrategyData storage S,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 maxLoss
    ) internal returns (uint256) {
        require(S.finalizedTally, "tally not finalized");
        require(receiver != address(0), "ZERO ADDRESS");
        require(maxLoss <= MAX_BPS, "exceeds MAX_BPS");

        // Spend allowance if applicable.
        if (msg.sender != owner) {
            _spendAllowance(S, owner, msg.sender, shares);
        }

        // Cache `asset` since it is used multiple times..
        ERC20 _asset = S.asset;

        // Update assets based on how much we took.
        S.totalAssets -= assets;

        _burn(S, owner, shares);

        // Transfer the amount of underlying to the receiver.
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        // Return the actual amount of assets withdrawn.
        return assets;
    }

    /**
     * @dev Adds voting power to an account
     * @param account The address to add voting power to
     * @param votes The amount of voting power to add
     */
    function _addVotingPower(
        StrategyData storage S,
        address account,
        uint256 votes
    ) internal {
        require(!S.finalizedTally, "tally finalized");
        require(account != address(0), "ZERO ADDRESS");
        S.totalVotingPower += votes;
        unchecked {
            S.votingPower[account] += votes;
        }
        //TODO: emit event?
    }

    /**
     * @dev Removes voting power from an account
     * @param account The address to remove voting power from
     * @param votes The amount of voting power to remove
     */
    function _removeVotingPower(
        StrategyData storage S,
        address account,
        uint256 votes
    ) internal {
        S.totalVotingPower -= votes;
        unchecked {
            S.votingPower[account] -= votes;
        }
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     *
     */
    function _mint(
        StrategyData storage S,
        address account,
        uint256 amount
    ) internal override {
        require(!S.finalizedTally, "tally finalized");
        require(account != address(0), "ERC20: mint to the zero address");

        S.totalSupply += amount;
        unchecked {
            S.balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(
        StrategyData storage S,
        address account,
        uint256 amount
    ) internal override {
        require(account != address(0), "ERC20: burn from the zero address");

        S.balances[account] -= amount;
        unchecked {
            S.totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            TENDING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Process a vote for a project with a contribution amount and vote weight
     * @dev This function validates and processes votes according to the implemented formula
     * @dev Must check that the voteWeight is appropriate for the contribution amount in _processVote
     * @dev Must check if the user can vote in _processVote
     * @dev Must check if the project exists in _processVote
     * @dev Must update the project tally in _processVote
     * Only keepers can call this function to prevent spam and ensure proper vote processing.
     *
     * @param projectId The ID of the project being voted for
     * @param contribution The amount being contributed to the project
     * @param voteWeight the weight of the vote, must be checked in _processVote by strategist
     */
    function vote(uint256 projectId, uint256 contribution, uint256 voteWeight) external nonReentrant {

        StrategyData storage S = _strategyStorage();
        // Tend the strategy with the current loose balance.
        IBaseImpactStrategy(address(this)).processVote(
            projectId,
            contribution,
            voteWeight
        );
        _removeVotingPower(S, msg.sender, contribution);
    }

     /**
     * @notice Returns the current funding metrics for a specific project
     * @dev This function aggregates all the relevant funding data for a project
     * @dev By convention project 0 should return 0 for projectShares
     * @param projectId The ID of the project to tally
     * @return projectShares The total shares allocated to this project
     * @return totalShares The total shares across all projects
     */
    function projectTally(uint256 projectId) external view returns (uint256 projectShares, uint256 totalShares) {
        return IBaseImpactStrategy(address(this)).tally(projectId);
    }

        /// @notice finalize the tally by assigning the totalShares to the totalAssets and setting the finalizedTally to true
    function finalizeTally(uint256 totalShares) external onlyManagement() {
        uint256 finalizedTotalShares = IBaseImpactStrategy(address(this)).finalize(totalShares);
        _strategyStorage().finalizedTotalShares = totalShares;
        _strategyStorage().finalizedTally = true;
    }

    /*//////////////////////////////////////////////////////////////
                        GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the current address that receives the performance fees.
     * @return . Address of projectRegistry
     */
    function projectRegistry() public view returns (IProjectRegistry) {
        return IProjectRegistry(_strategyStorage().projectRegistry);
    }


    /*//////////////////////////////////////////////////////////////
                        SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    /**
     * @notice Sets a new address to receive performance fees.
     * @dev Can only be called by the current `management`.
     *
     * Cannot set to address(0).
     *
     * @param _projectRegistry New address to set `management` to.
     */
    function setProjectRegistry(
        address _projectRegistry
    ) external onlyManagement {
        require(_projectRegistry != address(0), "ZERO ADDRESS");
        require(_projectRegistry != address(this), "Cannot be self");
        _strategyStorage().projectRegistry = _projectRegistry;

        emit UpdateProjectRegistry(_projectRegistry);
    }


    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev On contract creation we set `asset` for this contract to address(1).
     * This prevents it from ever being initialized in the future.
     */
    constructor() {
        _strategyStorage().asset = ERC20(address(1));
    }
}