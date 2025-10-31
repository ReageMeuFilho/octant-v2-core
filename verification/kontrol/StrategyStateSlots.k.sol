// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/*
╭---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------╮
| Name                      | Type                                                     | Slot | Offset | Bytes | Contract                                       |
+===============================================================================================================================================================+
| asset                     | address                                                  | 0    | 0      | 20    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| operator                  | address                                                  | 1    | 0      | 20    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| dragonRouter              | address                                                  | 2    | 0      | 20    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| decimals                  | uint8                                                    | 2    | 20     | 1     | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| name                      | string                                                   | 3    | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| totalSupply               | uint256                                                  | 4    | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| nonces                    | mapping(address => uint256)                              | 5    | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| balances                  | mapping(address => uint256)                              | 6    | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| allowances                | mapping(address => mapping(address => uint256))          | 7    | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| voluntaryLockups          | mapping(address => struct StrategyStateSlots.LockupInfo) | 8    | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| totalAssets               | uint256                                                  | 9    | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| keeper                    | address                                                  | 10   | 0      | 20    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| lastReport                | uint96                                                   | 10   | 20     | 12    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| management                | address                                                  | 11   | 0      | 20    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| pendingManagement         | address                                                  | 12   | 0      | 20    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| emergencyAdmin            | address                                                  | 13   | 0      | 20    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| entered                   | uint8                                                    | 13   | 20     | 1     | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| shutdown                  | bool                                                     | 13   | 21     | 1     | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| MINIMUM_LOCKUP_DURATION   | uint256                                                  | 14   | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| RAGE_QUIT_COOLDOWN_PERIOD | uint256                                                  | 15   | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| REGEN_GOVERNANCE          | address                                                  | 16   | 0      | 20    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| HATS                      | address                                                  | 17   | 0      | 20    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| KEEPER_HAT                | uint256                                                  | 18   | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| MANAGEMENT_HAT            | uint256                                                  | 19   | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| EMERGENCY_ADMIN_HAT       | uint256                                                  | 20   | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| REGEN_GOVERNANCE_HAT      | uint256                                                  | 21   | 0      | 32    | test/kontrol/StrategyState.k.sol:StrategyState |
|---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------|
| hatsInitialized           | bool                                                     | 22   | 0      | 1     | test/kontrol/StrategyState.k.sol:StrategyState |
╰---------------------------+----------------------------------------------------------+------+--------+-------+------------------------------------------------╯
*/

uint256 constant BASE_STRATEGY_STORAGE = uint256(keccak256("octant.base.strategy.storage")) - 1;
// BASE_STRATEGY_STORAGE = 36322111583268810930865516033209118031032626896612168719443967026533794718293
uint256 constant ASSET_SLOT = BASE_STRATEGY_STORAGE + 0;
uint256 constant OPERATOR_SLOT = BASE_STRATEGY_STORAGE + 1;
uint256 constant DRAGON_ROUTER_SLOT = BASE_STRATEGY_STORAGE + 2;
uint256 constant DECIMALS_SLOT = BASE_STRATEGY_STORAGE + 2;
uint256 constant NAME_SLOT = BASE_STRATEGY_STORAGE + 3;
uint256 constant TOTAL_SUPLLY_SLOT = BASE_STRATEGY_STORAGE + 4;
uint256 constant NONCES_SLOT = BASE_STRATEGY_STORAGE + 5;
uint256 constant BALANCES_SLOT = BASE_STRATEGY_STORAGE + 6;
uint256 constant ALLOWANCES_SLOT = BASE_STRATEGY_STORAGE + 7;
uint256 constant VOLUNTARY_LOCKUPS_SLOT = BASE_STRATEGY_STORAGE + 8;
uint256 constant TOTAL_ASSETS_SLOT = BASE_STRATEGY_STORAGE + 9;
uint256 constant KEEPER_SLOT = BASE_STRATEGY_STORAGE + 10;
uint256 constant LAST_REPORT_SLOT = BASE_STRATEGY_STORAGE + 10;
uint256 constant MANAGEMENT_SLOT = BASE_STRATEGY_STORAGE + 11;
uint256 constant PENDING_MANAGEMENT_SLOT = BASE_STRATEGY_STORAGE + 12;
uint256 constant EMERGENCY_ADMIN_SLOT = BASE_STRATEGY_STORAGE + 13;
uint256 constant ENTERED_SLOT = BASE_STRATEGY_STORAGE + 13;
uint256 constant ENTERED_OFFSET = 20;
uint256 constant ENTERED_WIDTH = 1;
uint256 constant SHUTDOWN_SLOT = BASE_STRATEGY_STORAGE + 13;
uint256 constant SHUTDOWN_OFFSET = 21;
uint256 constant SHUTDOWN_WIDTH = 1;
uint256 constant MINIMUM_LOCKUP_DURATION_SLOT = BASE_STRATEGY_STORAGE + 14;
uint256 constant RAGE_QUIT_COOLDOWN_PERIOD_SLOT = BASE_STRATEGY_STORAGE + 15;
uint256 constant REGEN_GOVERNANCE_SLOT = BASE_STRATEGY_STORAGE + 16;
uint256 constant HATS_SLOT = BASE_STRATEGY_STORAGE + 17;
uint256 constant KEEPER_HAT_SLOT = BASE_STRATEGY_STORAGE + 18;
uint256 constant MANAGEMENT_HAT_SLOT = BASE_STRATEGY_STORAGE + 19;
uint256 constant EMERGENCY_ADMIN_HAT_SLOT = BASE_STRATEGY_STORAGE + 20;
uint256 constant REGEN_GOVERNANCE_HAT_SLOT = BASE_STRATEGY_STORAGE + 21;
uint256 constant HATS_INITIALIZED_SLOT = BASE_STRATEGY_STORAGE + 22;

/*
contract StrategyState {
    
    //struct LockupInfo {
        uint256 lockupTime;
        uint256 unlockTime;
        uint256 lockedShares;
        bool isRageQuit;
    //}

    //struct StrategyData {
        // The ERC20 compliant underlying asset that will be
        // used by the Strategy
        address asset; //ERC20 asset;
        address operator;
        address dragonRouter;
        // These are the corresponding ERC20 variables needed for the
        // strategies token that is issued and burned on each deposit or withdraw.
        uint8 decimals; // The amount of decimals that `asset` and strategy use.
        string name; // The name of the token for the strategy.
        uint256 totalSupply; // The total amount of shares currently issued.
        mapping(address => uint256) nonces; // Mapping of nonces used for permit functions.
        mapping(address => uint256) balances; // Mapping to track current balances for each account that holds shares.
        mapping(address => mapping(address => uint256)) allowances; // Mapping to track the allowances for the strategies shares.
        mapping(address => uint256) voluntaryLockups; // Mapping allowing us to track lockups.
        // We manually track `totalAssets` to prevent PPS manipulation through airdrops.
        uint256 totalAssets;
        address keeper; // Address given permission to call {report} and {tend}.
        uint96 lastReport; // The last time a {report} was called.
        // Access management variables.
        address management; // Main address that can set all configurable variables.
        address pendingManagement; // Address that is pending to take over `management`.
        address emergencyAdmin; // Address to act in emergencies as well as `management`.
        // Strategy Status
        uint8 entered; // To prevent reentrancy. Use uint8 for gas savings.
        bool shutdown; // Bool that can be used to stop deposits into the strategy.
        uint256 MINIMUM_LOCKUP_DURATION;
        uint256 RAGE_QUIT_COOLDOWN_PERIOD;
        address REGEN_GOVERNANCE;
        // Hats protocol integration
        address HATS; //IHats HATS;
        uint256 KEEPER_HAT;
        uint256 MANAGEMENT_HAT;
        uint256 EMERGENCY_ADMIN_HAT;
        uint256 REGEN_GOVERNANCE_HAT;
        bool hatsInitialized; // Flag for Hats Protocol initialization
    //}
}
*/
