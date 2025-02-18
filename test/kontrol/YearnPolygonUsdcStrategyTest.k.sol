// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import "src/errors.sol";

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

struct UserInfo {
    uint256 balance;
    uint256 lockupTime;
    uint256 unlockTime;
    uint256 lockedShares;
    uint8 isRageQuit;
}

contract YearnPolygonUsdcStrategyTest is Setup {
    ProofState private preState;
    ProofState private posState;

    function setupSymbolicUser(address user) internal returns (UserInfo memory info) {
        info.balance = freshUInt256Bounded("userBalance");
        _storeMappingUInt256(address(strategy), BALANCES_SLOT, uint256(uint160(user)), 0, info.balance);

        info.lockupTime = freshUInt256Bounded("userLockupTime");
        _storeMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(user)), 0, info.lockupTime);

        info.unlockTime = freshUInt256Bounded("userUnlockTime");
        _storeMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(user)), 1, info.unlockTime);

        info.lockedShares = freshUInt256Bounded("userLockupShares");
        _storeMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(user)), 2, info.lockedShares);

        info.isRageQuit = freshUInt8("userHasRageQuit");
        _storeMappingData(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(user)), 3, 0, 1, info.isRageQuit);
    }

    function depositAssumptions(uint256 amount, address receiver, UserInfo memory receiverInfo, uint256 lockupDuration) internal returns (uint256) {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(strategy));
        vm.assume(receiver != address(dragonRouter));

        // Assume strategy is not shutdown
        _storeData(address(strategy), SHUTDOWN_SLOT, SHUTDOWN_OFFSET, SHUTDOWN_WIDTH, 0);
        // Assume non-reentrant
        _storeData(address(strategy), ENTERED_SLOT, ENTERED_OFFSET, ENTERED_WIDTH, 0);

        vm.assume(receiverInfo.isRageQuit == 0);

        vm.assume(receiver == safeOwner || receiverInfo.balance == 0);

        if(lockupDuration > 0) {
            uint256 minimumLockupDuration = _loadUInt256(address(strategy), MINIMUM_LOCKUP_DURATION_SLOT);
            if(receiverInfo.unlockTime <= block.timestamp) {
                vm.assume(lockupDuration > minimumLockupDuration);
                // Overflow assumption
                vm.assume(block.timestamp <= type(uint256).max - lockupDuration);
            }
            else{
                vm.assume(receiverInfo.unlockTime <= type(uint256).max - lockupDuration);
                vm.assume(receiverInfo.unlockTime + lockupDuration >= block.timestamp + minimumLockupDuration);
            }
        }

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

    function withdrawAssumptions(address sender, uint256 assets, address receiver, address _owner, uint256 maxLoss) internal {
        vm.assume(sender != address(0));
        
        // Assume non-reentrant
        _storeData(address(strategy), ENTERED_SLOT, ENTERED_OFFSET, ENTERED_WIDTH, 0);

        UserInfo memory owner = setupSymbolicUser(_owner);

        vm.assume(owner.isRageQuit != 0 || owner.unlockTime <= block.timestamp);

        vm.assume(receiver != address(0));
        vm.assume(maxLoss <= 10_000); // MAX_BPS = 10_000

        vm.assume(0 < assets);
        
        if (owner.unlockTime <= block.timestamp) {
            vm.assume(assets <= owner.balance);
            if(owner.isRageQuit != 0) {
                vm.assume(assets <= owner.lockedShares);
            }
        } else {
            // Since we assume that ownerHasRageQuit || ownerUnlockTime <= block.timestamp 
            // at this point we know that ownerHasRageQuit is true
            vm.assume(owner.lockupTime <= block.timestamp);
            vm.assume(owner.lockupTime < owner.unlockTime);
            uint256 timeElapsed = block.timestamp - owner.lockupTime;
            uint256 unlockedPortion = (timeElapsed * owner.balance) / (owner.unlockTime - owner.lockupTime);
            uint256 withdrawable = Math.min(unlockedPortion, owner.balance);
            vm.assume(assets <= withdrawable);
            vm.assume(assets <= owner.lockedShares);
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
        assertEq(posState.assetYieldSourceBalance, preState.assetYieldSourceBalance + amount + preState.assetStrategyBalance);
        assertEq(posState.assetStrategyBalance, 0);
        assertEq(posState.stateTotalAssets, preState.stateTotalAssets + amount);
        assertEq(posState.stateTotalSupply, preState.stateTotalSupply + amount);
        assertEq(posState.receiverStrategyShares, preState.receiverStrategyShares + amount);
        assertEq(posState.strategyYieldSourcesShares, preState.strategyYieldSourcesShares + amount + preState.assetStrategyBalance);
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
        uint256 ownerLockupTime = _loadMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(user)), 0);
        uint256 ownerUnlockTime = _loadMappingUInt256(address(strategy), VOLUNTARY_LOCKUPS_SLOT, uint256(uint160(user)), 1);

        _establish(mode, ownerLockupTime <= block.timestamp);
        _establish(mode, ownerLockupTime <= ownerUnlockTime);
    }

    function userBalancesTotalSupplyConsistency(Mode mode, address user) internal view {
        _establish(mode, strategy.balanceOf(user) <= strategy.totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                            ONLY OWNER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testDeposit(uint256 assets, address receiver) public {
        UserInfo memory receiverInfo = setupSymbolicUser(receiver);
        uint256 depositedAmount = depositAssumptions(assets, receiver, receiverInfo, 0);

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
        UserInfo memory receiverInfo = setupSymbolicUser(receiver);
        uint256 depositedAmount = depositAssumptions(assets, receiver, receiverInfo, lockupDuration);

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
        UserInfo memory receiverInfo = setupSymbolicUser(receiver);
        shares = depositAssumptions(shares, receiver, receiverInfo, 0);

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
        UserInfo memory receiverInfo = setupSymbolicUser(receiver);
        shares = depositAssumptions(shares, receiver, receiverInfo, lockupDuration);

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
        withdrawAssumptions(sender, assets, receiver, _owner, maxLoss);

        principalPreservationInvariant(Mode.Assume);
        lockupDurationInvariant(Mode.Assume, _owner);
        userBalancesTotalSupplyConsistency(Mode.Assume, _owner);

        //uint256 withdrawable = strategy.maxWithdraw(_owner);
        //vm.assume(assets <= withdrawable);
        //vm.assume(withdrawable <= IStrategy(YIELD_SOURCE).maxWithdraw(address(strategy)));
        //uint256 assetStrategyBalance = TestERC20(_asset).balanceOf(address(strategy));
        //if(assetStrategyBalance < assets) {
        //    vm.assume(assets - assetStrategyBalance <= IStrategy(YIELD_SOURCE).balanceOf(address(strategy)));
        //}

        vm.startPrank(sender);
        strategy.withdraw(assets, receiver, _owner, maxLoss);
        vm.stopPrank();

        principalPreservationInvariant(Mode.Assert);
        lockupDurationInvariant(Mode.Assert, _owner);
        userBalancesTotalSupplyConsistency(Mode.Assert, _owner);

        //TODO: assert expected state changes
    }

    function testWithdrawRevert(uint256 assets, address receiver, address _owner, uint256 maxLoss) public {
        // Sender has to be concrete, otherwise it will branch a lot when setting prank 
        address sender = makeAddr("SENDER");

        UserInfo memory user = setupSymbolicUser(_owner);
        // Avoid error DragonTokenizedStrategy__SharesStillLocked()
        vm.assume(user.isRageQuit == 0 && block.timestamp < user.unlockTime);

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(DragonTokenizedStrategy__SharesStillLocked.selector));
        strategy.withdraw(assets, receiver, _owner, maxLoss);
        vm.stopPrank();
    }

    function testRedeem(uint256 shares, address receiver, address _owner, uint256 maxLoss) public {
       // Sender has to be concrete, otherwise it will branch a lot when setting prank 
        address sender = makeAddr("SENDER");
        // TODO Remove this assumption
        vm.assume(sender == _owner);
        withdrawAssumptions(sender, shares, receiver, _owner, maxLoss);

        principalPreservationInvariant(Mode.Assume);
        lockupDurationInvariant(Mode.Assume, _owner);
        userBalancesTotalSupplyConsistency(Mode.Assume, _owner);

        //uint256 withdrawable = strategy.maxWithdraw(_owner);
        //vm.assume(assets <= withdrawable);
        //vm.assume(withdrawable <= IStrategy(YIELD_SOURCE).maxWithdraw(address(strategy)));
        //uint256 assetStrategyBalance = TestERC20(_asset).balanceOf(address(strategy));
        //if(assetStrategyBalance < shares) {
        //    vm.assume(shares - assetStrategyBalance <= IStrategy(YIELD_SOURCE).balanceOf(address(strategy)));
        //}
        
        vm.startPrank(sender);
        strategy.redeem(shares, receiver, _owner, maxLoss);
        vm.stopPrank();

        principalPreservationInvariant(Mode.Assert);
        lockupDurationInvariant(Mode.Assert, _owner);
        userBalancesTotalSupplyConsistency(Mode.Assert, _owner);

        //TODO: assert expected state changes
    }

    function testRedeemRevert(uint256 shares, address receiver, address _owner, uint256 maxLoss) public {
        // Sender has to be concrete, otherwise it will branch a lot when setting prank 
        address sender = makeAddr("SENDER");

        UserInfo memory user = setupSymbolicUser(_owner);
        // Avoid error DragonTokenizedStrategy__SharesStillLocked()
        vm.assume(user.isRageQuit == 0 && block.timestamp < user.unlockTime);

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(DragonTokenizedStrategy__SharesStillLocked.selector));
        strategy.redeem(shares, receiver, _owner, maxLoss);
        vm.stopPrank();
    }

    function testInitiateRageQuit() public {
        address sender = makeAddr("SENDER");

        UserInfo memory user = setupSymbolicUser(sender);
        vm.assume(user.balance > 0);
        vm.assume(block.timestamp < user.unlockTime);
        vm.assume(user.isRageQuit == 0);

        principalPreservationInvariant(Mode.Assume);
        lockupDurationInvariant(Mode.Assume, sender);
        userBalancesTotalSupplyConsistency(Mode.Assume, sender);

        vm.startPrank(sender);
        strategy.initiateRageQuit();
        vm.stopPrank();

        principalPreservationInvariant(Mode.Assert);
        lockupDurationInvariant(Mode.Assert, sender);
        userBalancesTotalSupplyConsistency(Mode.Assert, sender);

        //TODO: assert expected state changes
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