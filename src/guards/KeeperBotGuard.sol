// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Keeper Bot Guard
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Simple guard that allows authorized keeper bots to call report() on strategies
 * @dev This contract serves as a bridge between monitoring systems and our strategy contracts
 */
contract KeeperBotGuard is Ownable {

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error KeeperBotGuard__NotAuthorizedBot();
    error KeeperBotGuard__InvalidStrategy();
    error KeeperBotGuard__ReportCallFailed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event BotAuthorized(address indexed bot, bool authorized);
    event StrategyReportCalled(address indexed strategy, address indexed bot);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Mapping of authorized keeper bot addresses
    mapping(address => bool) public authorizedBots;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Restricts function calls to authorized keeper bots only
    modifier onlyAuthorizedBot() {
        if (!authorizedBots[msg.sender]) {
            revert KeeperBotGuard__NotAuthorizedBot();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address _owner) Ownable(_owner) {}

    /*//////////////////////////////////////////////////////////////
                           BOT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calls report() on the specified strategy
     * @dev Can only be called by authorized keeper bots
     * @param strategy Address of the strategy to call report() on
     */
    function callStrategyReport(address strategy) external onlyAuthorizedBot {
        if (strategy == address(0)) {
            revert KeeperBotGuard__InvalidStrategy();
        }

        // Call report() on the strategy
        (bool success, ) = strategy.call(abi.encodeWithSignature("report()"));
        
        if (!success) {
            revert KeeperBotGuard__ReportCallFailed();
        }

        emit StrategyReportCalled(strategy, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Authorizes or deauthorizes a keeper bot
     * @dev Can only be called by contract owner
     * @param bot Address of the bot to authorize/deauthorize
     * @param authorized Whether the bot should be authorized
     */
    function setBotAuthorization(address bot, bool authorized) external onlyOwner {
        authorizedBots[bot] = authorized;
        emit BotAuthorized(bot, authorized);
    }

    /**
     * @notice Batch authorize/deauthorize multiple bots
     * @dev Can only be called by contract owner
     * @param bots Array of bot addresses
     * @param authorized Array of authorization statuses (must match bots array length)
     */
    function setBotAuthorizationBatch(
        address[] calldata bots, 
        bool[] calldata authorized
    ) external onlyOwner {
        require(bots.length == authorized.length, "Array length mismatch");
        
        for (uint256 i = 0; i < bots.length; i++) {
            authorizedBots[bots[i]] = authorized[i];
            emit BotAuthorized(bots[i], authorized[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Check if an address is an authorized bot
     * @param bot Address to check
     * @return Whether the address is authorized
     */
    function isBotAuthorized(address bot) external view returns (bool) {
        return authorizedBots[bot];
    }
}