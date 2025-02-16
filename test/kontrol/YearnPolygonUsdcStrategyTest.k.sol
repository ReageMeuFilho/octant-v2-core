// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";

import {TestERC20} from "test/kontrol/TestERC20.k.sol";
import {Setup} from "test/kontrol/Setup.k.sol";
import {MockYieldSource} from "test/kontrol/MockYieldSource.k.sol";
import "test/kontrol/StrategyStateSlots.k.sol";
import "test/kontrol/Constants.k.sol";

struct ProofState {
    uint256 assetOwnerBalance;
    uint256 assetYieldSourceBalance;
    uint256 assetStrategyBalance;
    uint256 stateTotalAssets;
    uint256 stateTotalSupply;
    uint256 receiverStrategyShares;
    uint256 strategyYieldSourcesShares;
}

contract YearnPolygonUsdcStrategyTest is Setup {
    ProofState private preState;
    ProofState private posState;


    function receiverSetup(address receiver, uint256 lockupDuration) private {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(strategy));
        vm.assume(receiver != address(dragonRouterProxy));

        // Assume that receiver has not rage quit
        uint256 receiverHasRageQuit = 0;
        _storeMappingData(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(receiver)), 3, 0, 1, receiverHasRageQuit);

        uint256 balanceReceiver = freshUInt256Bounded("balanceOfReceiver");
        _storeMappingUInt256(address(strategy), BALANCES_SLOT, uint256(uint160(receiver)), 0, balanceReceiver);

        uint256 unlockTimeReceiver = freshUInt256Bounded("unlockTimeReceiver");
        _storeMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(receiver)), 1, unlockTimeReceiver);

        vm.assume(balanceReceiver == 0 || receiver == safeOwner);

        if(lockupDuration > 0) {
            uint256 minimumLockupDuration = _loadUInt256(address(strategy), MINIMUM_LOCKUP_DURATION_SLOT);
            if(unlockTimeReceiver <= block.timestamp) {
                vm.assume(lockupDuration > minimumLockupDuration);
                // Overflow assumption
                vm.assume(block.timestamp <= type(uint256).max - lockupDuration);
            }
            else{
                vm.assume(unlockTimeReceiver <= type(uint256).max - lockupDuration);
                vm.assume(unlockTimeReceiver + lockupDuration >= block.timestamp + minimumLockupDuration);
            }
        }
    }

    function depositAssumptions(uint256 amount) internal returns (uint256) {
        // Assume strategy is not shutdown
        _storeData(address(strategy), SHUTDOWN_SLOT, SHUTDOWN_OFFSET, SHUTDOWN_WIDTH, 0);
        // Assume non-reentrant
        _storeData(address(strategy), ENTERED_SLOT, ENTERED_OFFSET, ENTERED_WIDTH, 0);

        vm.assume(amount > 0);
        if (amount == type(uint256).max) {
            uint256 balance = freshUInt256Bounded("ownerBalance");
            vm.assume(0 < balance);
            TestERC20(_asset).mint(safeOwner, balance);
            return balance;
        }
        else {
            vm.assume(amount <= ETH_UPPER_BOUND);
            TestERC20(_asset).mint(safeOwner, amount);
            return amount;
        }
    }

    function withdrawAssumptions(address sender, uint256 assets, address receiver, address _owner, uint256 maxLoss) internal returns (uint256) {
        vm.assume(sender != address(0));
        
        // Assume non-reentrant
        _storeData(address(strategy), ENTERED_SLOT, ENTERED_OFFSET, ENTERED_WIDTH, 0);

        // Assume that _owner has not rage quit
        bool ownerHasRageQuit = kevm.freshBool("ownerHasRageQuit");
        _storeMappingData(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(_owner)), 3, 0, 1, ownerHasRageQuit ? 1 : 0);

        uint256 ownerBalance = freshUInt256Bounded("ownerBalance");
        _storeMappingUInt256(address(strategy), BALANCES_SLOT, uint256(uint160(_owner)), 0, ownerBalance);

        uint256 ownerLockupTime = freshUInt256Bounded("ownerLockupTime");
        _storeMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(_owner)), 0, ownerLockupTime);

        uint256 ownerUnlockTime = freshUInt256Bounded("ownerUnlockTime");
        _storeMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(_owner)), 1, ownerUnlockTime);
        // Avoid error DragonTokenizedStrategy__SharesStillLocked()
        vm.assume(ownerUnlockTime <= block.timestamp || ownerHasRageQuit);

        uint256 ownerLockupShares = freshUInt256Bounded("ownerLockupShares");
        _storeMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(_owner)), 2, ownerLockupShares);

        vm.assume(receiver != address(0));
        vm.assume(maxLoss <= 10_000); // MAX_BPS = 10_000

        vm.assume(0 < assets);
        //vm.assume(assets <= ETH_UPPER_BOUND);
        if (ownerUnlockTime <= block.timestamp) {
            vm.assume(assets <= ownerBalance);
            if(ownerHasRageQuit) {
                vm.assume(assets <= ownerLockupShares);
            }
            return ownerBalance;
        } else {
            // Since we assume that ownerUnlockTime <= block.timestamp || ownerHasRageQuit 
            // at this point we know that ownerHasRageQuit is true
            vm.assume(ownerLockupTime <= block.timestamp);
            vm.assume(ownerLockupTime < ownerUnlockTime);
            uint256 timeElapsed = block.timestamp - ownerLockupTime;
            uint256 unlockedPortion = (timeElapsed * ownerBalance) / (ownerUnlockTime - ownerLockupTime);
            uint256 withdrawable = Math.min(unlockedPortion, ownerBalance);
            vm.assume(assets <= withdrawable);
            vm.assume(assets <= ownerLockupShares);
            return withdrawable;
        }
    }

    function _snapshop(ProofState storage state, address receiver) internal {
        state.assetOwnerBalance = TestERC20(_asset).balanceOf(safeOwner);
        state.assetYieldSourceBalance = TestERC20(_asset).balanceOf(YIELD_SOURCE);
        state.assetStrategyBalance = TestERC20(_asset).balanceOf(address(strategy));
        state.stateTotalAssets = strategy.totalAssets();
        state.stateTotalSupply = strategy.totalSupply();
        state.receiverStrategyShares = strategy.balanceOf(receiver);
        state.strategyYieldSourcesShares = IStrategy(YIELD_SOURCE).balanceOf(address(strategy));
    }

    /*//////////////////////////////////////////////////////////////
                            STATE CHANGES
    //////////////////////////////////////////////////////////////*/
    function assertDepositStateChanges(uint256 amount) internal view {
        assertEq(posState.assetOwnerBalance, preState.assetOwnerBalance - amount);
        assertEq(posState.assetYieldSourceBalance, preState.assetYieldSourceBalance + amount);
        assertEq(posState.assetStrategyBalance, preState.assetStrategyBalance);
        assertEq(posState.stateTotalAssets, preState.stateTotalAssets + amount);
        assertEq(posState.stateTotalSupply, preState.stateTotalSupply + amount);
        assertEq(posState.receiverStrategyShares, preState.receiverStrategyShares + amount);
        assertEq(posState.strategyYieldSourcesShares, preState.strategyYieldSourcesShares + amount);
    } 

    /*//////////////////////////////////////////////////////////////
                            INVARIANTS
    //////////////////////////////////////////////////////////////*/

    // TotalAssets should always equal totalSupply of shares
    function principalPreservationInvariant(Mode mode) internal view {
        uint256 totalSupply = strategy.totalSupply();
        uint256 totalAssets = strategy.totalAssets();

        _establish(mode, totalSupply == totalAssets);
    }

    function lockupDurationInvariant(Mode mode, address user) internal view {
        uint256 minimumLockupDuration = _loadUInt256(address(strategy), MINIMUM_LOCKUP_DURATION_SLOT);
        uint256 ownerLockupTime = _loadMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(user)), 0);
        uint256 ownerUnlockTime = _loadMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(user)), 1);
        _establish(mode, ownerLockupTime <= block.timestamp);
        _establish(mode, ownerLockupTime <= ownerUnlockTime);
        _establish(mode, ownerUnlockTime - ownerLockupTime >= minimumLockupDuration);
    }

    function userBalancesTotalSupplyConsistency(Mode mode, address user) internal view {
        _establish(mode, strategy.balanceOf(user) <= strategy.totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                            ONLY OWNER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testDeposit(uint256 assets, address receiver) public {
        receiverSetup(receiver, 0);
        uint256 depositedAmount = depositAssumptions(assets);

        _snapshop(preState, receiver);

        principalPreservationInvariant(Mode.Assume);
        lockupDurationInvariant(Mode.Assume, receiver);
        userBalancesTotalSupplyConsistency(Mode.Assume, receiver);

        vm.startPrank(safeOwner);
        strategy.deposit(assets, receiver);
        vm.stopPrank();

        principalPreservationInvariant(Mode.Assert);
        lockupDurationInvariant(Mode.Assert, receiver);
        userBalancesTotalSupplyConsistency(Mode.Assert, receiver);

        _snapshop(posState, receiver);
        assertDepositStateChanges(depositedAmount);
    }

    function testDepositWithLockup(uint256 assets, address receiver, uint256 lockupDuration) public {
        vm.assume(lockupDuration > 0);
        receiverSetup(receiver, lockupDuration);
        uint256 depositedAmount = depositAssumptions(assets);

        _snapshop(preState, receiver);

        principalPreservationInvariant(Mode.Assume);
        lockupDurationInvariant(Mode.Assume, receiver);
        userBalancesTotalSupplyConsistency(Mode.Assume, receiver);

        vm.startPrank(safeOwner);
        strategy.depositWithLockup(assets, receiver, lockupDuration);
        vm.stopPrank();

        principalPreservationInvariant(Mode.Assert);
        lockupDurationInvariant(Mode.Assert, receiver);
        userBalancesTotalSupplyConsistency(Mode.Assert, receiver);

        _snapshop(posState, receiver);
        //TODO: assertions about the lockuptime and lockupshares
        assertDepositStateChanges(depositedAmount);
    }


    function testMint(uint256 shares, address receiver) public {
        vm.assume(shares != type(uint256).max);
        receiverSetup(receiver, 0);
        shares = depositAssumptions(shares);

        _snapshop(preState, receiver);

        principalPreservationInvariant(Mode.Assume);
        lockupDurationInvariant(Mode.Assume, receiver);
        userBalancesTotalSupplyConsistency(Mode.Assume, receiver);

        vm.startPrank(safeOwner);
        strategy.mint(shares, receiver);
        vm.stopPrank();

        principalPreservationInvariant(Mode.Assert);
        lockupDurationInvariant(Mode.Assert, receiver);
        userBalancesTotalSupplyConsistency(Mode.Assert, receiver);

        _snapshop(posState, receiver);
        assertDepositStateChanges(shares);
    }

    function testMintWithLockup(uint256 shares, address receiver, uint256 lockupDuration) public {
        vm.assume(lockupDuration > 0);
        vm.assume(shares != type(uint256).max);
        receiverSetup(receiver, lockupDuration);
        shares = depositAssumptions(shares);

        _snapshop(preState, receiver);

        principalPreservationInvariant(Mode.Assume);
        lockupDurationInvariant(Mode.Assume, receiver);
        userBalancesTotalSupplyConsistency(Mode.Assume, receiver);

        vm.startPrank(safeOwner);
        strategy.mintWithLockup(shares, receiver, lockupDuration);
        vm.stopPrank();

        principalPreservationInvariant(Mode.Assert);
        lockupDurationInvariant(Mode.Assert, receiver);
        userBalancesTotalSupplyConsistency(Mode.Assert, receiver);

        _snapshop(posState, receiver);
        //TODO: assertions about the lockuptime and lockupshares
        assertDepositStateChanges(shares);
    }

    /*//////////////////////////////////////////////////////////////
                            ANY USER TESTS
    //////////////////////////////////////////////////////////////*/

    function testWithdraw(uint256 assets, address receiver, address _owner, uint256 maxLoss) public {
        // Sender has to be concrete, otherwise it will branch a lot when setting prank 
        address sender = makeAddr("SENDER");
        // TODO Remove this assumption
        vm.assume(sender == _owner);
        uint256 withdrawable = withdrawAssumptions(sender, assets, receiver, _owner, maxLoss);
        vm.assume(withdrawable <= IStrategy(YIELD_SOURCE).balanceOf(address(strategy)));

        principalPreservationInvariant(Mode.Assume);
        lockupDurationInvariant(Mode.Assume, _owner);
        userBalancesTotalSupplyConsistency(Mode.Assume, _owner);

        vm.startPrank(sender);
        strategy.withdraw(assets, receiver, _owner, maxLoss);
        vm.stopPrank();

        principalPreservationInvariant(Mode.Assert);
        lockupDurationInvariant(Mode.Assert, _owner);
        userBalancesTotalSupplyConsistency(Mode.Assert, _owner);

        //TODO: assert expected state changes
    }

    function testRedeem(address sender, uint256 shares, address receiver, address _owner, uint256 maxLoss) public {
        vm.startPrank(sender);
        strategy.redeem(shares, receiver, _owner, maxLoss);
        vm.stopPrank();
    }

    function testInitiateRageQuit(address sender) public {
        vm.startPrank(sender);
        strategy.initiateRageQuit();
        vm.stopPrank();
    }

    //approve
    //accceptManagement

    /*//////////////////////////////////////////////////////////////
                            ONLY MANAGER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetPendingManagement(address management) public {
        vm.startPrank(_management);
        strategy.setPendingManagement(management);
        vm.stopPrank();
    }

    function testSetKeeper(address keeper) public {
        vm.startPrank(_management);
        strategy.setKeeper(keeper);
        vm.stopPrank();
    }

    function testSetEmergencyAdmin(address _emergencyAdmin) public {
        vm.startPrank(_management);
        strategy.setEmergencyAdmin(_emergencyAdmin);
        vm.stopPrank();
    }

    function testSetName(string calldata _name) public {
        vm.startPrank(_management);
        strategy.setName(_name);
        vm.stopPrank();
    }

    //setupHatsProtocol

    /*//////////////////////////////////////////////////////////////
                            ONLY KEEPER TESTS
    //////////////////////////////////////////////////////////////*/

    function testReport() public {
        vm.startPrank(_keeper);
        strategy.report();
        vm.stopPrank();
    }

    function testTend() public {
        vm.startPrank(_keeper);
        strategy.tend();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            ONLY REGEN GOVERNANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetLockupDuration(uint256 _lockupDuration) public {
        vm.startPrank(_regenGovernance);
        strategy.setLockupDuration(_lockupDuration);
        vm.stopPrank();
    }

    function testSetRageQuitCooldownPeriod(uint256 _rageQuitCooldownPeriod) public {
        vm.startPrank(_regenGovernance);
        strategy.setRageQuitCooldownPeriod(_rageQuitCooldownPeriod);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            ONLY EMERGENCY TESTS
    //////////////////////////////////////////////////////////////*/

    function testShutdownStrategy() public {
        vm.startPrank(_emergencyAdmin);
        strategy.shutdownStrategy();
        vm.stopPrank();
    }

    function testEmergencyWithdraw(uint256 amount) public {
        vm.startPrank(_emergencyAdmin);
        strategy.emergencyWithdraw(amount);
        vm.stopPrank();
    }
}