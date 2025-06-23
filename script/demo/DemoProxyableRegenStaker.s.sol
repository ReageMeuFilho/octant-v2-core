// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console } from "forge-std/Script.sol";
import { ProxyableRegenStaker } from "src/regen/ProxyableRegenStaker.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

/// @notice Demo script showing ProxyableRegenStaker minimal proxy deployment
contract DemoProxyableRegenStaker is Script {
    function run() external {
        console.log("=== ProxyableRegenStaker Minimal Proxy Demo ===");

        // Deploy the implementation contract
        console.log("\n1. Deploying ProxyableRegenStaker implementation...");
        ProxyableRegenStaker implementation = new ProxyableRegenStaker();
        console.log("Implementation deployed at:", address(implementation));
        console.log("Implementation bytecode size:", address(implementation).code.length, "bytes");

        // Deploy the factory
        console.log("\n2. Deploying RegenStakerFactory...");
        RegenStakerFactory factory = new RegenStakerFactory(address(implementation));
        console.log("Factory deployed at:", address(factory));

        // Prepare parameters for creating a staker
        RegenStakerFactory.CreateStakerParams memory params = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(address(0x1)), // Mock address for demo
            stakeToken: IERC20Staking(address(0x2)), // Mock address for demo
            admin: address(0x3), // Mock admin
            stakerWhitelist: IWhitelist(address(0)), // No whitelist
            contributionWhitelist: IWhitelist(address(0)), // No whitelist
            allocationMechanismWhitelist: IWhitelist(address(0x4)), // Mock whitelist
            earningPowerCalculator: IEarningPowerCalculator(address(0x5)), // Mock calculator
            maxBumpTip: 1e18,
            maxClaimFee: 1e17,
            minimumStakeAmount: 1e18,
            rewardDuration: 30 days
        });

        bytes32 salt = keccak256("demo-salt-1");

        // Predict the address
        console.log("\n3. Predicting proxy address...");
        address predictedAddress = factory.predictStakerAddress(salt);
        console.log("Predicted address:", predictedAddress);

        // Deploy the proxy
        console.log("\n4. Deploying proxy via factory...");
        uint256 gasBefore = gasleft();
        address proxyAddress = factory.createStaker(params, salt);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Proxy deployed at:", proxyAddress);
        console.log("Gas used for deployment:", gasUsed);
        console.log("Proxy bytecode size:", proxyAddress.code.length, "bytes");
        console.log("Address prediction correct:", predictedAddress == proxyAddress);

        // Verify the proxy configuration
        console.log("\n5. Verifying proxy configuration...");
        ProxyableRegenStaker staker = ProxyableRegenStaker(proxyAddress);
        console.log("Admin:", staker.admin());
        console.log("Reward token:", address(staker.getRewardToken()));
        console.log("Stake token:", address(staker.getStakeToken()));
        console.log("Max claim fee:", staker.getMaxClaimFee());
        console.log("Reward duration:", staker.rewardDuration());
        console.log("Minimum stake amount:", staker.minimumStakeAmount());

        // Compare bytecode sizes
        console.log("\n6. Gas and size comparison:");
        console.log("Implementation size:", address(implementation).code.length, "bytes");
        console.log("Proxy size:", proxyAddress.code.length, "bytes");
        console.log(
            "Size reduction:",
            ((address(implementation).code.length - proxyAddress.code.length) * 100) /
                address(implementation).code.length,
            "%"
        );

        console.log("\n=== Demo completed successfully! ===");
        console.log("Each proxy saves ~99.8% storage space compared to full contract deployment");
        console.log("Deployment gas is also significantly reduced");
    }
}
