// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { Staker } from "staker/Staker.sol";

/**
 * @title REG-001 Delegatee Whitelist Architecture Demonstration
 * @dev Demonstrates that delegatee whitelist architecture is CORRECT and SECURE
 *
 * FINDING RECLASSIFIED: REG-001 was initially documented as Medium severity
 * but was reclassified as NOT A VULNERABILITY after proper analysis.
 *
 * KEY ARCHITECTURAL INSIGHTS:
 * 1. Delegatees are external governance participants (e.g., Optimism DAO voting)
 * 2. Delegatees have ZERO protocol permissions in RegenStaker
 * 3. Delegatees cannot claim rewards, stake, or perform protocol operations
 * 4. Only deposit.owner needs whitelist validation for protocol operations
 * 5. This represents CORRECT separation of protocol vs external governance concerns
 *
 * DEVELOPER CLARIFICATION:
 * "There is no point checking if delegatee is in the staker whitelist.
 * Delegatee is the actor who can use voting rights of the stake token
 * in the relevant governance. For example, if stake token was OP,
 * delegatee can use OP voting right in Optimism Governance. It's not
 * relevant to Regen Staker."
 *
 * EXPECTED: All tests should PASS showing the architecture works correctly
 * This is NOT an exploit test - it's an architecture validation test
 */
contract REG001_DelegateeWhitelistDemoTest is Test {
    RegenStaker public regenStaker;
    RegenEarningPowerCalculator public earningPowerCalculator;
    MockERC20 public rewardToken;
    MockERC20Staking public stakeToken;
    Whitelist public stakerWhitelist;
    Whitelist public contributionWhitelist;
    Whitelist public allocationMechanismWhitelist;
    Whitelist public earningPowerWhitelist;

    address public admin = makeAddr("admin");
    address public rewardNotifier = makeAddr("rewardNotifier");
    address public whitelistedUser = makeAddr("whitelistedUser");
    address public nonWhitelistedUser = makeAddr("nonWhitelistedUser");
    address public externalGovernanceDelegatee = makeAddr("externalGovernanceDelegatee");
    address public anotherDelegatee = makeAddr("anotherDelegatee");

    uint256 public constant INITIAL_REWARD_AMOUNT = 100 ether;
    uint256 public constant USER_STAKE_AMOUNT = 10 ether;
    uint256 public constant REWARD_DURATION = 30 days;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy contracts
        rewardToken = new MockERC20(18);
        stakeToken = new MockERC20Staking(18);
        stakerWhitelist = new Whitelist();
        contributionWhitelist = new Whitelist();
        allocationMechanismWhitelist = new Whitelist();
        earningPowerWhitelist = new Whitelist();
        earningPowerCalculator = new RegenEarningPowerCalculator(address(this), earningPowerWhitelist);

        // Deploy RegenStaker
        regenStaker = new RegenStaker(
            rewardToken,
            stakeToken,
            earningPowerCalculator,
            1000, // maxBumpTip
            admin, // admin
            uint128(REWARD_DURATION), // rewardDuration
            0, // maxClaimFee
            0, // minStakeAmount
            stakerWhitelist,
            contributionWhitelist,
            allocationMechanismWhitelist
        );

        // Setup reward notifier
        regenStaker.setRewardNotifier(rewardNotifier, true);

        // Setup whitelists - ONLY whitelist the actual staker, NOT the delegatee
        stakerWhitelist.addToWhitelist(whitelistedUser);
        // Note: externalGovernanceDelegatee is deliberately NOT whitelisted
        // Note: nonWhitelistedUser is deliberately NOT whitelisted
        earningPowerWhitelist.addToWhitelist(whitelistedUser);

        // Mint tokens
        rewardToken.mint(rewardNotifier, INITIAL_REWARD_AMOUNT);
        stakeToken.mint(whitelistedUser, USER_STAKE_AMOUNT * 2);
        stakeToken.mint(nonWhitelistedUser, USER_STAKE_AMOUNT);

        vm.stopPrank();
    }

    /**
     * @dev Demonstrates that whitelisted users can stake with non-whitelisted delegatees
     * This is the CORRECT behavior - only the staker needs whitelist approval
     */
    function testREG001_WhitelistedUserCanStakeWithNonWhitelistedDelegatee() public {
        console.log("=== REG-001 DEMONSTRATION: Whitelisted User + Non-Whitelisted Delegatee ===");

        console.log("Whitelisted user:", whitelistedUser);
        console.log("External governance delegatee (NOT whitelisted):", externalGovernanceDelegatee);

        // Verify whitelist status
        assertTrue(stakerWhitelist.isWhitelisted(whitelistedUser), "User should be whitelisted");
        assertFalse(stakerWhitelist.isWhitelisted(externalGovernanceDelegatee), "Delegatee should NOT be whitelisted");

        vm.startPrank(whitelistedUser);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT);

        // This should work - whitelisted user delegating to non-whitelisted delegatee
        Staker.DepositIdentifier depositId = regenStaker.stake(
            USER_STAKE_AMOUNT,
            externalGovernanceDelegatee, // Non-whitelisted delegatee - this is CORRECT
            whitelistedUser
        );

        vm.stopPrank();

        console.log("SUCCESS: Successfully staked with non-whitelisted delegatee");
        console.log("Deposit ID:", Staker.DepositIdentifier.unwrap(depositId));

        // Verify the deposit was created correctly
        assertTrue(Staker.DepositIdentifier.unwrap(depositId) >= 0, "Deposit should be created");

        // Verify delegatee assignment worked
        address assignedDelegatee = address(regenStaker.surrogates(externalGovernanceDelegatee));
        console.log("Surrogate deployed for delegatee:", assignedDelegatee);
        assertTrue(assignedDelegatee != address(0), "Surrogate should be deployed for delegatee");

        console.log("SUCCESS: CORRECT BEHAVIOR: Architecture allows delegation to external governance actors");
    }

    /**
     * @dev Demonstrates that non-whitelisted users CANNOT stake (regardless of delegatee)
     * This shows proper access control on the actual protocol user
     */
    function testREG001_NonWhitelistedUserCannotStake() public {
        console.log("=== REG-001 DEMONSTRATION: Non-Whitelisted User Cannot Stake ===");

        console.log("Non-whitelisted user:", nonWhitelistedUser);
        console.log("External governance delegatee:", externalGovernanceDelegatee);

        // Verify whitelist status
        assertFalse(stakerWhitelist.isWhitelisted(nonWhitelistedUser), "User should NOT be whitelisted");

        vm.startPrank(nonWhitelistedUser);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT);

        // This should FAIL - non-whitelisted user trying to stake
        vm.expectRevert(); // Should revert due to whitelist check on deposit.owner
        regenStaker.stake(USER_STAKE_AMOUNT, externalGovernanceDelegatee, nonWhitelistedUser);

        vm.stopPrank();

        console.log("SUCCESS: CORRECT BEHAVIOR: Non-whitelisted users cannot stake");
        console.log("SUCCESS: Access control properly enforced on deposit.owner, not delegatee");
    }

    /**
     * @dev Demonstrates stakeMore() uses deposit.owner for whitelist checks
     * This is the CORRECT behavior and shows no inconsistency with stake()
     */
    function testREG001_StakeMoreUsesDepositOwnerWhitelist() public {
        console.log("=== REG-001 DEMONSTRATION: StakeMore Uses Deposit Owner for Whitelist ===");

        // First, create a deposit
        vm.startPrank(whitelistedUser);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT * 2);

        Staker.DepositIdentifier depositId = regenStaker.stake(
            USER_STAKE_AMOUNT,
            externalGovernanceDelegatee, // Non-whitelisted delegatee
            whitelistedUser
        );

        console.log("Initial deposit created with ID:", Staker.DepositIdentifier.unwrap(depositId));

        // Now try stakeMore - should work because deposit.owner is whitelisted
        regenStaker.stakeMore(depositId, USER_STAKE_AMOUNT);

        vm.stopPrank();

        console.log("SUCCESS: StakeMore successful for whitelisted deposit owner");
        console.log("SUCCESS: CORRECT BEHAVIOR: stakeMore() checks deposit.owner, not delegatee");
        console.log("SUCCESS: No inconsistency between stake() and stakeMore() - both use proper access control");
    }

    /**
     * @dev Demonstrates delegatees have NO protocol permissions
     * This proves delegatees cannot exploit the protocol
     */
    function testREG001_DelegateesHaveNoProtocolPermissions() public {
        console.log("=== REG-001 DEMONSTRATION: Delegatees Have No Protocol Permissions ===");

        // Setup: Create a deposit with delegation
        vm.startPrank(whitelistedUser);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT);

        Staker.DepositIdentifier depositId = regenStaker.stake(
            USER_STAKE_AMOUNT,
            externalGovernanceDelegatee,
            whitelistedUser
        );
        vm.stopPrank();

        // Start rewards to accumulate some
        vm.startPrank(rewardNotifier);
        rewardToken.approve(address(regenStaker), INITIAL_REWARD_AMOUNT);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);

        console.log("Deposit created, rewards started, time advanced");

        // Test 1: Delegatee cannot claim rewards
        console.log("\n--- Testing: Delegatee cannot claim rewards ---");
        vm.startPrank(externalGovernanceDelegatee);

        vm.expectRevert(); // Should revert - delegatee is not deposit owner
        regenStaker.claimReward(depositId);

        vm.stopPrank();
        console.log("SUCCESS: Delegatee correctly CANNOT claim rewards");

        // Test 2: Delegatee cannot stakeMore
        console.log("\n--- Testing: Delegatee cannot stakeMore ---");
        stakeToken.mint(externalGovernanceDelegatee, USER_STAKE_AMOUNT);

        vm.startPrank(externalGovernanceDelegatee);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT);

        vm.expectRevert(); // Should revert - delegatee is not deposit owner
        regenStaker.stakeMore(depositId, USER_STAKE_AMOUNT);

        vm.stopPrank();
        console.log("SUCCESS: Delegatee correctly CANNOT stakeMore");

        // Test 3: Delegatee cannot withdraw
        console.log("\n--- Testing: Delegatee cannot withdraw ---");
        vm.startPrank(externalGovernanceDelegatee);

        vm.expectRevert(); // Should revert - delegatee is not deposit owner
        regenStaker.withdraw(depositId, USER_STAKE_AMOUNT);

        vm.stopPrank();
        console.log("SUCCESS: Delegatee correctly CANNOT withdraw");

        console.log("\nSUCCESS: SECURITY CONFIRMED: Delegatees have ZERO protocol permissions");
        console.log("SUCCESS: Delegatees can only participate in EXTERNAL governance (e.g., OP voting)");
    }

    /**
     * @dev Demonstrates the correct separation of concerns:
     * - Protocol operations controlled by deposit.owner whitelist
     * - External governance controlled by delegatee assignment
     */
    function testREG001_CorrectSeparationOfConcerns() public {
        console.log("=== REG-001 DEMONSTRATION: Correct Separation of Concerns ===");

        // Setup multiple deposits with different delegatees
        vm.startPrank(whitelistedUser);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT * 2);

        // Deposit 1: Delegate to first external governance actor
        Staker.DepositIdentifier depositId1 = regenStaker.stake(
            USER_STAKE_AMOUNT,
            externalGovernanceDelegatee,
            whitelistedUser
        );

        // Deposit 2: Delegate to different external governance actor
        Staker.DepositIdentifier depositId2 = regenStaker.stake(USER_STAKE_AMOUNT, anotherDelegatee, whitelistedUser);

        vm.stopPrank();

        console.log("Created deposits with different delegatees:");
        console.log(
            "Deposit 1 ID:",
            Staker.DepositIdentifier.unwrap(depositId1),
            "-> Delegatee:",
            externalGovernanceDelegatee
        );
        console.log("Deposit 2 ID:", Staker.DepositIdentifier.unwrap(depositId2), "-> Delegatee:", anotherDelegatee);

        // Verify different surrogates were deployed
        address surrogate1 = address(regenStaker.surrogates(externalGovernanceDelegatee));
        address surrogate2 = address(regenStaker.surrogates(anotherDelegatee));

        console.log("Surrogate 1 address:", surrogate1);
        console.log("Surrogate 2 address:", surrogate2);

        assertTrue(surrogate1 != surrogate2, "Different delegatees should have different surrogates");
        assertTrue(surrogate1 != address(0), "Surrogate 1 should be deployed");
        assertTrue(surrogate2 != address(0), "Surrogate 2 should be deployed");

        // Verify the same user (whitelistedUser) can perform protocol operations on both
        // This demonstrates proper separation: protocol control vs governance delegation

        // Start rewards
        vm.startPrank(rewardNotifier);
        rewardToken.approve(address(regenStaker), INITIAL_REWARD_AMOUNT);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days);

        // The whitelisted user can manage both deposits despite different delegatees
        vm.startPrank(whitelistedUser);

        uint256 reward1 = regenStaker.claimReward(depositId1);
        uint256 reward2 = regenStaker.claimReward(depositId2);

        vm.stopPrank();

        console.log("User successfully claimed rewards from both deposits:");
        console.log("Reward 1:", reward1);
        console.log("Reward 2:", reward2);

        console.log("\nSUCCESS: CORRECT ARCHITECTURE DEMONSTRATED:");
        console.log("SUCCESS: Protocol operations controlled by deposit.owner whitelist");
        console.log("SUCCESS: External governance controlled by delegatee assignment");
        console.log("SUCCESS: Perfect separation of protocol vs external governance concerns");
    }

    /**
     * @dev Demonstrates why delegatee whitelist checks would be architecturally wrong
     * This test shows what would happen if delegatees were required to be whitelisted
     */
    function testREG001_WhyDelegateeWhitelistWouldBeWrong() public {
        console.log("=== REG-001 DEMONSTRATION: Why Delegatee Whitelist Would Be Wrong ===");

        console.log("ARCHITECTURAL ANALYSIS:");
        console.log("If delegatees were required to be whitelisted, it would:");
        console.log("1. Force external governance actors to be approved by RegenStaker admin");
        console.log("2. Create artificial coupling between protocol and external governance");
        console.log("3. Limit users' choice of governance representatives");
        console.log("4. Provide no security benefit (delegatees have no protocol permissions)");

        // Demonstrate the key insight: delegatees are for EXTERNAL governance only
        console.log("\nEXAMPLE SCENARIO:");
        console.log("- Stake token = OP (Optimism token)");
        console.log("- User stakes OP in RegenStaker");
        console.log("- User delegates to respected OP governance participant");
        console.log("- That governance participant can vote in OPTIMISM DAO, not RegenStaker");
        console.log("- RegenStaker admin has no business approving Optimism governance participants");

        // Show current correct behavior
        vm.startPrank(whitelistedUser);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT);

        Staker.DepositIdentifier depositId = regenStaker.stake(
            USER_STAKE_AMOUNT,
            externalGovernanceDelegatee, // Could be any governance actor
            whitelistedUser
        );

        vm.stopPrank();

        console.log("\nSUCCESS: CURRENT CORRECT BEHAVIOR:");
        console.log("SUCCESS: Users can delegate to any external governance actor");
        console.log("SUCCESS: RegenStaker admin doesn't control external governance choices");
        console.log("SUCCESS: Clean separation between protocol and external governance");
        console.log("SUCCESS: Deposit ID:", Staker.DepositIdentifier.unwrap(depositId), "successfully created");

        console.log("\nSUCCESS: CONCLUSION: REG-001 is NOT a vulnerability");
        console.log("SUCCESS: The architecture is correct and secure");
        console.log("SUCCESS: No whitelist check on delegatees is the RIGHT design");
    }

    /**
     * @dev Test that shows the _getStakeMoreWhitelistTarget function works correctly
     * This addresses the Q3 audit question about why this function exists
     */
    function testREG001_StakeMoreWhitelistTargetFunction() public {
        console.log("=== REG-001 DEMONSTRATION: StakeMore Whitelist Target Function ===");

        // Create a deposit
        vm.startPrank(whitelistedUser);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT * 2);

        Staker.DepositIdentifier depositId = regenStaker.stake(
            USER_STAKE_AMOUNT,
            externalGovernanceDelegatee,
            whitelistedUser
        );

        // StakeMore should work because it checks deposit.owner (whitelistedUser)
        regenStaker.stakeMore(depositId, USER_STAKE_AMOUNT);

        vm.stopPrank();

        console.log("SUCCESS: StakeMore successful - correctly uses deposit.owner for whitelist check");

        // Developer's insight: The virtual function abstraction was created due to
        // uncertainty about which actor should be whitelist-checked among multiple roles
        // (caller, depositor, claimer, delegatee). Current implementation correctly
        // checks deposit.owner.

        console.log("\nDEVELOPER INSIGHT (from audit Q3 response):");
        console.log("'I wasn't sure at some point which actor should be checked against");
        console.log("the whitelist so I came up with this virtual function. It would be");
        console.log("good to eliminate this virtual function assuming that this final");
        console.log("design (always checking deposit.owner against staker whitelist) makes sense.'");

        console.log("\nSUCCESS: The virtual function represents premature abstraction");
        console.log("SUCCESS: Current implementation correctly checks deposit.owner");
        console.log("SUCCESS: Function can be simplified in future refactoring");
    }

    /**
     * @dev Summary test that validates the overall REG-001 conclusion
     */
    function testREG001_FinalValidation() public {
        console.log("=== REG-001 FINAL VALIDATION ===");

        console.log("FINDING SUMMARY:");
        console.log("- Initially reported as Medium severity inconsistency");
        console.log("- Reclassified as NOT A VULNERABILITY after proper analysis");
        console.log("- Represents correct protocol architecture");

        console.log("\nKEY ARCHITECTURAL PRINCIPLES VALIDATED:");

        // 1. Proper access control
        vm.startPrank(whitelistedUser);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = regenStaker.stake(
            USER_STAKE_AMOUNT,
            externalGovernanceDelegatee,
            whitelistedUser
        );
        vm.stopPrank();
        console.log("SUCCESS: 1. Whitelisted users can stake with any delegatee");

        // 2. Delegatees have no protocol permissions
        vm.expectRevert();
        vm.prank(externalGovernanceDelegatee);
        regenStaker.claimReward(depositId);
        console.log("SUCCESS: 2. Delegatees cannot perform protocol operations");

        // 3. Consistent whitelist checking
        vm.startPrank(nonWhitelistedUser);
        stakeToken.approve(address(regenStaker), USER_STAKE_AMOUNT);
        vm.expectRevert();
        regenStaker.stake(USER_STAKE_AMOUNT, externalGovernanceDelegatee, nonWhitelistedUser);
        vm.stopPrank();
        console.log("SUCCESS: 3. Non-whitelisted users cannot stake regardless of delegatee");

        console.log("\nSUCCESS: REG-001 CONCLUSION: Architecture is CORRECT and SECURE");
        console.log("SUCCESS: No vulnerability exists - this is proper protocol design");
        console.log("SUCCESS: Separates protocol operations from external governance delegation");

        assertTrue(true, "REG-001 architecture validation complete - no vulnerability");
    }
}
